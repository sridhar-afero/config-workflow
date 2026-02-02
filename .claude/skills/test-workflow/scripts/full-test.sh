#!/bin/bash
# Full end-to-end workflow test with comprehensive summary

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
N8N_URL="${N8N_URL:-http://localhost:5678}"
JENKINS_URL="${JENKINS_URL:-http://localhost:9090}"
JENKINS_USER="${JENKINS_USER:-admin}"
JENKINS_TOKEN="${JENKINS_TOKEN:-}"
STATE_FILE="${STATE_FILE:-/tmp/workflow-test-state.json}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "========================================"
echo "  Full Workflow Test"
echo "========================================"
echo ""

# Get Jenkins credentials from Kubernetes if not set
if [ -z "$JENKINS_TOKEN" ]; then
    JENKINS_TOKEN=$(kubectl get secret my-jenkins -o jsonpath='{.data.jenkins-admin-password}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
fi
export JENKINS_TOKEN

AUTH_OPTS=""
if [ -n "$JENKINS_TOKEN" ]; then
    AUTH_OPTS="--user $JENKINS_USER:$JENKINS_TOKEN"
fi

# Step 1: Check prerequisites
echo "Step 1: Checking prerequisites..."
echo "----------------------------------------"
bash "$SCRIPT_DIR/check-prereqs.sh"

echo ""
echo ""

# Step 2: Check n8n
echo "Step 2: Checking n8n status..."
echo "----------------------------------------"
bash "$SCRIPT_DIR/check-n8n.sh"

echo ""
echo ""

# Step 3: Check Jenkins
echo "Step 3: Checking Jenkins status..."
echo "----------------------------------------"
bash "$SCRIPT_DIR/check-jenkins.sh" || true

echo ""
echo ""

# Step 4: Trigger workflow
echo "Step 4: Triggering workflow..."
echo "----------------------------------------"
bash "$SCRIPT_DIR/trigger-webhook.sh"

echo ""
echo ""

# Step 5: Wait for build and show status
echo "Step 5: Monitoring workflow execution..."
echo "----------------------------------------"

# Wait a moment for the workflow to start
sleep 3

# Get the build number before trigger from state file
TRIGGER_BUILD=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('jenkins_build_before', 0))" 2>/dev/null || echo "0")

# Poll for build completion
MAX_WAIT=60
WAITED=0
BUILD_COMPLETE=false
NEW_BUILD_NUM=""

echo "Waiting for Jenkins build to complete..."
while [ $WAITED -lt $MAX_WAIT ]; do
    if [ -n "$AUTH_OPTS" ]; then
        LAST_BUILD=$(curl -s $AUTH_OPTS "$JENKINS_URL/job/Test/lastBuild/api/json?tree=number,result,building" 2>/dev/null)
        CURRENT_NUM=$(echo "$LAST_BUILD" | python3 -c "import json,sys; print(json.load(sys.stdin).get('number', 0))" 2>/dev/null || echo "0")
        BUILDING=$(echo "$LAST_BUILD" | python3 -c "import json,sys; print(json.load(sys.stdin).get('building', True))" 2>/dev/null || echo "True")
        RESULT=$(echo "$LAST_BUILD" | python3 -c "import json,sys; print(json.load(sys.stdin).get('result', ''))" 2>/dev/null || echo "")

        if [ "$CURRENT_NUM" -gt "$TRIGGER_BUILD" ]; then
            NEW_BUILD_NUM=$CURRENT_NUM
            if [ "$BUILDING" = "False" ]; then
                BUILD_COMPLETE=true
                break
            fi
        fi
    fi
    echo -n "."
    sleep 2
    WAITED=$((WAITED + 2))
done

echo ""
echo ""

# Get n8n API key from Kubernetes secret
N8N_API_KEY="${N8N_API_KEY:-}"
if [ -z "$N8N_API_KEY" ]; then
    N8N_API_KEY=$(kubectl get secret n8n-api-key -o jsonpath='{.data.api-key}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
fi

# Function to get Jira ticket and Jenkins build info from n8n REST API
get_workflow_info_from_n8n() {
    if [ -z "$N8N_API_KEY" ]; then
        echo "|"
        return
    fi

    # Get recent executions from n8n API with data included
    local result=$(curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_URL/api/v1/executions?limit=10&includeData=true" 2>/dev/null)

    echo "$result" | python3 -c "
import json
import sys

def find_in_data(data, node_patterns, key_patterns):
    '''Search for values in execution data matching node and key patterns'''
    if not isinstance(data, dict):
        return None

    result_data = data.get('resultData', {})
    run_data = result_data.get('runData', {})

    for node_name, node_runs in run_data.items():
        node_lower = node_name.lower()
        if any(p in node_lower for p in node_patterns):
            if isinstance(node_runs, list):
                for run in node_runs:
                    if isinstance(run, dict) and 'data' in run:
                        main_data = run['data'].get('main', [])
                        if isinstance(main_data, list):
                            for items in main_data:
                                if isinstance(items, list):
                                    for item in items:
                                        if isinstance(item, dict) and 'json' in item:
                                            json_data = item['json']
                                            if isinstance(json_data, dict):
                                                for key_pattern in key_patterns:
                                                    if key_pattern in json_data:
                                                        return json_data[key_pattern]
    return None

try:
    response = json.load(sys.stdin)
    executions = response.get('data', [])

    jira_ticket = ''
    jenkins_build = ''

    for execution in executions:
        exec_data = execution.get('data', {})
        if not exec_data:
            continue

        # Look for Jira ticket
        if not jira_ticket:
            ticket = find_in_data(exec_data, ['jira', 'issue', 'create'], ['key', 'id'])
            if ticket:
                jira_ticket = str(ticket)

        # Look for Jenkins build info
        if not jenkins_build:
            build_info = find_in_data(exec_data, ['jenkins', 'http', 'build', 'deploy'], ['number', 'buildNumber', 'build_number'])
            if build_info:
                jenkins_build = str(build_info)

        if jira_ticket:
            break

    print(f'{jira_ticket}|{jenkins_build}')
except Exception as e:
    print('|')
" 2>/dev/null
}

# Simple wrapper for backward compatibility
get_jira_ticket() {
    local info=$(get_workflow_info_from_n8n)
    echo "$info" | cut -d'|' -f1
}

# Try to fetch Jira ticket if build succeeded
JIRA_TICKET=""
if [ "$BUILD_COMPLETE" = true ] && [ "$RESULT" = "SUCCESS" ]; then
    echo "Checking for Jira ticket creation..."
    sleep 2  # Give n8n time to complete the Jira step
    JIRA_TICKET=$(get_jira_ticket)

    # Update state file with Jira ticket
    if [ -n "$JIRA_TICKET" ] && [ -f "$STATE_FILE" ]; then
        python3 -c "
import json
with open('$STATE_FILE', 'r') as f:
    state = json.load(f)
state['jira_ticket'] = '$JIRA_TICKET'
with open('$STATE_FILE', 'w') as f:
    json.dump(state, f, indent=2)
" 2>/dev/null
    fi
fi

# Final Summary
echo "========================================"
echo "  WORKFLOW TEST SUMMARY"
echo "========================================"
echo ""

# Get final build details
if [ -n "$NEW_BUILD_NUM" ] && [ -n "$AUTH_OPTS" ]; then
    FINAL_BUILD=$(curl -s $AUTH_OPTS "$JENKINS_URL/job/Test/$NEW_BUILD_NUM/api/json?tree=number,result,duration,timestamp,building" 2>/dev/null)
    FINAL_RESULT=$(echo "$FINAL_BUILD" | python3 -c "import json,sys; print(json.load(sys.stdin).get('result', 'UNKNOWN'))" 2>/dev/null || echo "UNKNOWN")
    FINAL_DURATION=$(echo "$FINAL_BUILD" | python3 -c "import json,sys; print(json.load(sys.stdin).get('duration', 0) / 1000)" 2>/dev/null || echo "0")
    FINAL_BUILDING=$(echo "$FINAL_BUILD" | python3 -c "import json,sys; print(json.load(sys.stdin).get('building', False))" 2>/dev/null || echo "False")
fi

TRIGGER_TIME=$(python3 -c "import json; print(json.load(open('$STATE_FILE')).get('trigger_time_local', 'N/A'))" 2>/dev/null || echo "N/A")

echo "┌─────────────────────────────────────────────────────────┐"
echo "│  WORKFLOW STATUS                                        │"
echo "├─────────────────────────────────────────────────────────┤"
printf "│  %-20s │  %-32s │\n" "Triggered At" "$TRIGGER_TIME"
echo "├─────────────────────────────────────────────────────────┤"

# n8n status
N8N_STATUS="✅ Healthy"
N8N_HEALTH=$(curl -s "$N8N_URL/healthz" 2>/dev/null || echo "")
if ! echo "$N8N_HEALTH" | grep -q '"ok"'; then
    N8N_STATUS="❌ Not Accessible"
fi
printf "│  %-20s │  %-32s │\n" "n8n Status" "$N8N_STATUS"

# Webhook status
printf "│  %-20s │  %-32s │\n" "Webhook Trigger" "✅ Workflow Started"

echo "├─────────────────────────────────────────────────────────┤"
echo "│  JENKINS BUILD                                          │"
echo "├─────────────────────────────────────────────────────────┤"

if [ -n "$NEW_BUILD_NUM" ]; then
    printf "│  %-20s │  %-32s │\n" "Build Number" "#$NEW_BUILD_NUM"

    if [ "$FINAL_BUILDING" = "True" ]; then
        printf "│  %-20s │  %-32s │\n" "Status" "⏳ BUILDING"
    elif [ "$FINAL_RESULT" = "SUCCESS" ]; then
        printf "│  %-20s │  %-32s │\n" "Status" "✅ SUCCESS"
    elif [ "$FINAL_RESULT" = "FAILURE" ]; then
        printf "│  %-20s │  %-32s │\n" "Status" "❌ FAILURE"
    else
        printf "│  %-20s │  %-32s │\n" "Status" "$FINAL_RESULT"
    fi

    printf "│  %-20s │  %-32s │\n" "Duration" "${FINAL_DURATION}s"
else
    printf "│  %-20s │  %-32s │\n" "Build" "No new build detected"
fi

echo "├─────────────────────────────────────────────────────────┤"
echo "│  JIRA TICKET                                            │"
echo "├─────────────────────────────────────────────────────────┤"

if [ -n "$JIRA_TICKET" ]; then
    printf "│  %-20s │  %-32s │\n" "Ticket" "$JIRA_TICKET"
    printf "│  %-20s │  %-32s │\n" "Status" "📋 Awaiting Approval"
elif [ "$FINAL_RESULT" = "SUCCESS" ]; then
    printf "│  %-20s │  %-32s │\n" "Ticket" "✅ Created (check Jira)"
    printf "│  %-20s │  %-32s │\n" "Note" "Ticket # available after Done"
else
    printf "│  %-20s │  %-32s │\n" "Ticket" "⏸️  Waiting for build"
fi

echo "├─────────────────────────────────────────────────────────┤"
echo "│  WORKFLOW PROGRESS                                      │"
echo "├─────────────────────────────────────────────────────────┤"

# Show workflow stages
echo "│  Step 1: Webhook Triggered         ✅ Complete          │"

if [ -n "$NEW_BUILD_NUM" ]; then
    if [ "$FINAL_BUILDING" = "True" ]; then
        echo "│  Step 2: Non-Prod Deployment        ⏳ In Progress       │"
        echo "│  Step 3: Jira Ticket Created        ⏸️  Waiting          │"
        echo "│  Step 4: Prod Deployment            ⏸️  Waiting          │"
    elif [ "$FINAL_RESULT" = "SUCCESS" ]; then
        echo "│  Step 2: Non-Prod Deployment        ✅ Complete          │"
        if [ -n "$JIRA_TICKET" ]; then
            printf "│  Step 3: Jira Ticket Created        ✅ %-17s │\n" "$JIRA_TICKET"
        else
            echo "│  Step 3: Jira Ticket Created        ✅ Check Jira        │"
        fi
        echo "│  Step 4: Prod Deployment            ⏸️  Waiting for Jira │"
    else
        echo "│  Step 2: Non-Prod Deployment        ❌ Failed            │"
        echo "│  Step 3: Jira Ticket Created        ⏸️  Blocked          │"
        echo "│  Step 4: Prod Deployment            ⏸️  Blocked          │"
    fi
else
    echo "│  Step 2: Non-Prod Deployment        ⏳ Starting...        │"
    echo "│  Step 3: Jira Ticket Created        ⏸️  Waiting           │"
    echo "│  Step 4: Prod Deployment            ⏸️  Waiting           │"
fi

echo "└─────────────────────────────────────────────────────────┘"

echo ""
echo "========================================"
echo "  NEXT STEPS"
echo "========================================"
echo ""

if [ "$FINAL_BUILDING" = "True" ]; then
    echo "Build is still in progress. To check status:"
    echo "  bash $SCRIPT_DIR/check-status.sh"
elif [ "$FINAL_RESULT" = "SUCCESS" ]; then
    echo "Non-prod deployment completed. Next steps:"
    if [ -n "$JIRA_TICKET" ]; then
        echo "  1. Jira ticket created: $JIRA_TICKET"
    else
        echo "  1. Jira ticket created (check Jira for ticket number)"
        echo "     Note: Ticket # will show here after marking 'Done'"
    fi
    echo "  2. Mark the Jira ticket as 'Done' to trigger prod deployment"
    echo ""
    echo "To check workflow status:"
    echo "  bash $SCRIPT_DIR/check-status.sh"
else
    echo "To check current status:"
    echo "  bash $SCRIPT_DIR/check-status.sh"
fi

echo ""
echo "Jenkins Console: $JENKINS_URL/job/Test/$NEW_BUILD_NUM/console"
echo "n8n Dashboard:   $N8N_URL"
echo ""
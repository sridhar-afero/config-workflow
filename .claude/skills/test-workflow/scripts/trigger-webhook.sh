#!/bin/bash
# Trigger the n8n webhook and save state for status tracking

N8N_URL="${N8N_URL:-http://localhost:5678}"
JENKINS_URL="${JENKINS_URL:-http://localhost:9090}"
JENKINS_USER="${JENKINS_USER:-admin}"
JENKINS_TOKEN="${JENKINS_TOKEN:-}"
WORKFLOW_NAME="${WORKFLOW_NAME:-Publish Config Changes}"
STATE_FILE="${STATE_FILE:-/tmp/workflow-test-state.json}"

echo "Triggering n8n webhook"
echo "======================"
echo ""

# Get n8n API key from Kubernetes secret
N8N_API_KEY="${N8N_API_KEY:-}"
if [ -z "$N8N_API_KEY" ]; then
    N8N_API_KEY=$(kubectl get secret n8n-api-key -o jsonpath='{.data.api-key}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
fi

# Get webhook ID from n8n API
WEBHOOK_ID=""
if [ -n "$N8N_API_KEY" ]; then
    echo "Fetching webhook ID for workflow: $WORKFLOW_NAME"
    WORKFLOWS_RESPONSE=$(curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_URL/api/v1/workflows")

    WEBHOOK_ID=$(echo "$WORKFLOWS_RESPONSE" | python3 -c "
import json
import sys
import urllib.parse

try:
    data = json.load(sys.stdin)
    workflows = data.get('data', [])
    workflow_name = urllib.parse.unquote('$WORKFLOW_NAME')

    for wf in workflows:
        if wf.get('name') == workflow_name:
            for node in wf.get('nodes', []):
                if node.get('type') == 'n8n-nodes-base.webhook':
                    webhook_id = node.get('webhookId') or node.get('parameters', {}).get('path')
                    if webhook_id:
                        print(webhook_id)
                        break
            break
except Exception as e:
    pass
" 2>/dev/null)
fi

if [ -z "$WEBHOOK_ID" ]; then
    echo "❌ ERROR: Could not find webhook ID for workflow '$WORKFLOW_NAME'"
    echo "   Make sure:"
    echo "   - The workflow exists in n8n"
    echo "   - The n8n API key is configured (secret: n8n-api-key)"
    echo "   - The workflow has a Webhook trigger node"
    exit 1
fi

echo "Found webhook ID: $WEBHOOK_ID"
echo ""

# Get Jenkins credentials from Kubernetes if not set
if [ -z "$JENKINS_TOKEN" ]; then
    JENKINS_TOKEN=$(kubectl get secret my-jenkins -o jsonpath='{.data.jenkins-admin-password}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
fi

AUTH_OPTS=""
if [ -n "$JENKINS_TOKEN" ]; then
    AUTH_OPTS="--user $JENKINS_USER:$JENKINS_TOKEN"
fi

# Get current Jenkins build number before triggering
CURRENT_BUILD="0"
if [ -n "$AUTH_OPTS" ]; then
    BUILD_INFO=$(curl -s $AUTH_OPTS "$JENKINS_URL/job/Test/lastBuild/api/json?tree=number" 2>/dev/null)
    CURRENT_BUILD=$(echo "$BUILD_INFO" | python3 -c "import json,sys; print(json.load(sys.stdin).get('number', 0))" 2>/dev/null || echo "0")
    echo "Current Jenkins build #: $CURRENT_BUILD"
fi

echo "Webhook URL: $N8N_URL/webhook/$WEBHOOK_ID"
echo ""

# Trigger the webhook (using GET as configured in n8n)
TRIGGER_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
RESPONSE=$(curl -s -w "\n%{http_code}" "$N8N_URL/webhook/$WEBHOOK_ID")

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

echo "HTTP Status: $HTTP_CODE"
echo ""
echo "Response:"
echo "$BODY" | python3 -m json.tool 2>/dev/null || echo "$BODY"

if [ "$HTTP_CODE" -ge 200 ] && [ "$HTTP_CODE" -lt 300 ]; then
    echo ""
    echo "✅ SUCCESS: Webhook triggered successfully"

    # Save state for status tracking
    cat > "$STATE_FILE" << EOF
{
    "trigger_time": "$TRIGGER_TIME",
    "trigger_time_local": "$(date)",
    "webhook_id": "$WEBHOOK_ID",
    "workflow_name": "$WORKFLOW_NAME",
    "jenkins_build_before": "$CURRENT_BUILD",
    "webhook_response": $BODY
}
EOF
    echo ""
    echo "State saved to: $STATE_FILE"
    echo ""
    echo "Run check-status.sh to monitor workflow progress"
else
    echo ""
    echo "❌ ERROR: Webhook trigger failed (HTTP $HTTP_CODE)"
    if [ "$HTTP_CODE" = "404" ]; then
        echo "   The workflow may not be activated. Activate it in n8n UI."
    fi
    exit 1
fi
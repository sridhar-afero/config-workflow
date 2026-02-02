#!/bin/bash
# Check n8n status and recent executions

N8N_URL="${N8N_URL:-http://localhost:5678}"
WORKFLOW_NAME="${WORKFLOW_NAME:-Publish Config Changes}"

echo "Checking n8n status"
echo "==================="
echo ""
echo "n8n URL: $N8N_URL"
echo ""

# Check health
echo "1. Health check..."
HEALTH=$(curl -s --connect-timeout 5 "$N8N_URL/healthz" 2>/dev/null || echo "unavailable")
echo "   Status: $HEALTH"

# Check if we can access the web UI
echo ""
echo "2. Web interface..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "$N8N_URL" 2>/dev/null)
if [ "$HTTP_CODE" == "200" ] || [ "$HTTP_CODE" == "302" ]; then
    echo "   Web UI: ACCESSIBLE (HTTP $HTTP_CODE)"
else
    echo "   Web UI: Status $HTTP_CODE"
fi

# Get n8n API key from Kubernetes secret
N8N_API_KEY="${N8N_API_KEY:-}"
if [ -z "$N8N_API_KEY" ]; then
    N8N_API_KEY=$(kubectl get secret n8n-api-key -o jsonpath='{.data.api-key}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
fi

if [ -z "$N8N_API_KEY" ]; then
    echo ""
    echo "3. API Access..."
    echo "   ⚠️  n8n API key not found"
    echo "   Create one in n8n Settings → API and store in Kubernetes:"
    echo "   kubectl create secret generic n8n-api-key --from-literal=api-key=YOUR_KEY"
    echo ""
    echo "==================="
    echo "n8n Dashboard: $N8N_URL"
    exit 0
fi

# Get workflow info
echo ""
echo "3. Workflow: $WORKFLOW_NAME"
WORKFLOWS_RESPONSE=$(curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_URL/api/v1/workflows" 2>/dev/null)

echo "$WORKFLOWS_RESPONSE" | python3 -c "
import json
import sys
import urllib.parse

try:
    data = json.load(sys.stdin)
    workflows = data.get('data', [])
    workflow_name = urllib.parse.unquote('$WORKFLOW_NAME')

    found = False
    for wf in workflows:
        if wf.get('name') == workflow_name:
            found = True
            active = wf.get('active', False)
            wf_id = wf.get('id', 'N/A')

            # Find webhook
            webhook_id = ''
            for node in wf.get('nodes', []):
                if node.get('type') == 'n8n-nodes-base.webhook':
                    webhook_id = node.get('webhookId') or node.get('parameters', {}).get('path', '')
                    break

            print(f'   Found: YES (ID: {wf_id})')
            if active:
                print('   Status: ✅ ACTIVE')
            else:
                print('   Status: ⚠️  INACTIVE')
            if webhook_id:
                print(f'   Webhook: $N8N_URL/webhook/{webhook_id}')
            break

    if not found:
        print('   Found: NO')
        print('   Please import the workflow into n8n')
except Exception as e:
    print(f'   Error: {e}')
" 2>/dev/null

# Get recent executions
echo ""
echo "4. Recent Executions..."

EXECUTIONS=$(curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_URL/api/v1/executions?limit=5&includeData=true" 2>/dev/null)

echo "$EXECUTIONS" | python3 -c "
import json
import sys
from datetime import datetime

def find_in_data(data, node_patterns, key_patterns):
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

    if not executions:
        print('   No executions found')
    else:
        print('')
        print('   ID    STATUS     JIRA       STARTED')
        print('   ----  ---------  ---------  -------------------')

        for execution in executions:
            exec_id = str(execution.get('id', 'N/A'))
            status = execution.get('status', 'unknown')
            started = execution.get('startedAt', '')

            # Status icon
            if status == 'success':
                status_str = '✅ success'
            elif status == 'error':
                status_str = '❌ error  '
            elif status == 'running':
                status_str = '⏳ running'
            elif status == 'waiting':
                status_str = '⏸️  waiting'
            else:
                status_str = f'   {status[:7]}'

            # Get Jira ticket
            exec_data = execution.get('data', {})
            jira_ticket = find_in_data(exec_data, ['jira', 'issue', 'create'], ['key', 'id']) or '-'

            # Format time
            time_str = ''
            if started:
                try:
                    dt = datetime.fromisoformat(started.replace('Z', '+00:00'))
                    time_str = dt.strftime('%Y-%m-%d %H:%M')
                except:
                    time_str = started[:16]

            print(f'   {exec_id:<5} {status_str:<10} {str(jira_ticket):<9}  {time_str}')

except Exception as e:
    print(f'   Error: {e}')
" 2>/dev/null

echo ""
echo "==================="
echo "n8n Dashboard: $N8N_URL"
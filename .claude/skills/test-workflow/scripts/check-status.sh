#!/bin/bash
# Check workflow status using n8n REST API as the single source of truth

N8N_URL="${N8N_URL:-http://localhost:5678}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo ""
echo "========================================"
echo "  Workflow Status"
echo "========================================"
echo ""

# Get n8n API key from Kubernetes secret
N8N_API_KEY="${N8N_API_KEY:-}"
if [ -z "$N8N_API_KEY" ]; then
    N8N_API_KEY=$(kubectl get secret n8n-api-key -o jsonpath='{.data.api-key}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
fi

# Check n8n health
N8N_HEALTH=$(curl -s "$N8N_URL/healthz" 2>/dev/null)
if ! echo "$N8N_HEALTH" | grep -q '"ok"'; then
    echo -e "  n8n:       ${RED}NOT ACCESSIBLE${NC}"
    echo ""
    echo "  Cannot check workflow status without n8n access."
    exit 1
fi
echo -e "  n8n:       ${GREEN}RUNNING${NC} ($N8N_URL)"

# Check if we have API access
if [ -z "$N8N_API_KEY" ]; then
    echo ""
    echo -e "  ${YELLOW}n8n API key not available${NC}"
    echo "  Set N8N_API_KEY or create secret:"
    echo "    kubectl create secret generic n8n-api-key --from-literal=api-key=YOUR_KEY"
    exit 1
fi

echo ""
echo "----------------------------------------"
echo "  Latest Workflow Execution"
echo "----------------------------------------"

# Get the most recent execution from n8n
EXEC_DATA=$(curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_URL/api/v1/executions?limit=1&includeData=true" 2>/dev/null)

# Parse execution data and display status
echo "$EXEC_DATA" | python3 -c "
import json
import sys
from datetime import datetime

RED = '\033[0;31m'
GREEN = '\033[0;32m'
YELLOW = '\033[1;33m'
BLUE = '\033[0;34m'
NC = '\033[0m'

try:
    data = json.load(sys.stdin)
    executions = data.get('data', [])

    if not executions:
        print('  No workflow executions found.')
        print('')
        print('  To trigger a workflow:')
        print('    bash .claude/skills/test-workflow/scripts/trigger-webhook.sh')
        sys.exit(0)

    exec = executions[0]
    exec_id = exec.get('id', 'N/A')
    status = exec.get('status', 'unknown')
    finished = exec.get('finished', False)
    wait_till = exec.get('waitTill')
    started_at = exec.get('startedAt', '')
    stopped_at = exec.get('stoppedAt', '')

    # Parse timestamps
    start_time = ''
    duration = ''
    if started_at:
        try:
            start_dt = datetime.fromisoformat(started_at.replace('Z', '+00:00'))
            start_time = start_dt.strftime('%Y-%m-%d %H:%M:%S')
            if stopped_at:
                stop_dt = datetime.fromisoformat(stopped_at.replace('Z', '+00:00'))
                delta = stop_dt - start_dt
                duration = f'{delta.total_seconds():.1f}s'
        except:
            start_time = started_at

    print(f'  Execution ID:  {exec_id}')
    print(f'  Started:       {start_time}')
    if duration:
        print(f'  Duration:      {duration}')

    # Get execution details from runData
    run_data = exec.get('data', {}).get('resultData', {}).get('runData', {})

    # Extract key information from nodes
    jira_ticket = ''
    nonprod_success = False
    prod_success = False
    waiting_for_jira = False

    nodes_executed = list(run_data.keys())

    # Check for Jira ticket
    if 'Create an issue' in run_data:
        node_runs = run_data['Create an issue']
        if node_runs:
            main_data = node_runs[0].get('data', {}).get('main', [[]])
            if main_data and main_data[0]:
                json_data = main_data[0][0].get('json', {})
                jira_ticket = json_data.get('key', '')

    # Check non-prod deployment
    if 'Publish changes to non-prod' in run_data:
        node_runs = run_data['Publish changes to non-prod']
        if node_runs:
            node_status = node_runs[0].get('executionStatus', '')
            nonprod_success = node_status == 'success'

    # Check prod deployment
    if 'Trigger Jenkins Job' in run_data:
        node_runs = run_data['Trigger Jenkins Job']
        if node_runs:
            node_status = node_runs[0].get('executionStatus', '')
            prod_success = node_status == 'success'

    # Check if waiting for Jira
    if not finished and wait_till:
        waiting_for_jira = True
    elif 'Check if Done' in run_data and 'Trigger Jenkins Job' not in run_data:
        waiting_for_jira = True

    print('')
    print('----------------------------------------')
    print('  Workflow Progress')
    print('----------------------------------------')
    print('')

    # Step 1: Webhook
    if 'Webhook' in run_data:
        print('  Step 1: Webhook Triggered     ✅ Complete')
    else:
        print('  Step 1: Webhook Triggered     ⏳ Pending')

    # Step 2: Non-prod deployment
    if nonprod_success:
        print('  Step 2: Non-Prod Deployment   ✅ Complete')
    elif 'Publish changes to non-prod' in run_data:
        print('  Step 2: Non-Prod Deployment   ⏳ In Progress')
    else:
        print('  Step 2: Non-Prod Deployment   ⏸️  Waiting')

    # Step 3: Jira ticket
    if jira_ticket:
        if prod_success or (finished and status == 'success'):
            print(f'  Step 3: Jira Ticket           ✅ {jira_ticket} (Done)')
        elif waiting_for_jira:
            print(f'  Step 3: Jira Ticket           📋 {jira_ticket} (Awaiting Done)')
        else:
            print(f'  Step 3: Jira Ticket           ✅ {jira_ticket}')
    elif 'Create an issue' in run_data:
        print('  Step 3: Jira Ticket           ⏳ Creating...')
    else:
        print('  Step 3: Jira Ticket           ⏸️  Waiting')

    # Step 4: Prod deployment
    if prod_success:
        print('  Step 4: Prod Deployment       ✅ Complete')
    elif 'Trigger Jenkins Job' in run_data:
        print('  Step 4: Prod Deployment       ⏳ In Progress')
    else:
        print('  Step 4: Prod Deployment       ⏸️  Waiting')

    print('')

    # Overall status
    if status == 'success' and finished:
        print(f'  {GREEN}Overall Status: WORKFLOW COMPLETE{NC}')
    elif status == 'error':
        print(f'  {RED}Overall Status: FAILED{NC}')
    elif status == 'running' or not finished:
        if waiting_for_jira:
            print(f'  {BLUE}Overall Status: AWAITING JIRA APPROVAL ({jira_ticket}){NC}')
        elif 'Trigger Jenkins Job' in run_data:
            print(f'  {YELLOW}Overall Status: PROD DEPLOYMENT IN PROGRESS{NC}')
        elif 'Publish changes to non-prod' in run_data:
            print(f'  {YELLOW}Overall Status: NON-PROD DEPLOYMENT IN PROGRESS{NC}')
        else:
            print(f'  {YELLOW}Overall Status: IN PROGRESS{NC}')
    else:
        print(f'  Overall Status: {status}')

    # Show details
    print('')
    print('----------------------------------------')
    print('  Details')
    print('----------------------------------------')
    if jira_ticket:
        print(f'  Jira Ticket:     {jira_ticket}')

    # Jenkins builds info
    jenkins_nodes = [n for n in nodes_executed if 'jenkins' in n.lower() or 'publish' in n.lower() or 'trigger' in n.lower()]
    if jenkins_nodes:
        print(f'  Jenkins Builds:  {len(set(jenkins_nodes))} triggered')
        for node in sorted(set(jenkins_nodes)):
            node_runs = run_data.get(node, [])
            if node_runs:
                node_status = node_runs[0].get('executionStatus', 'unknown')
                icon = '✅' if node_status == 'success' else '❌' if node_status == 'error' else '⏳'
                print(f'    - {node}: {icon}')

except Exception as e:
    print(f'  Error parsing execution data: {e}')
    sys.exit(1)
"

echo ""
echo "========================================"
echo ""
echo "To trigger a new workflow:"
echo "  bash .claude/skills/test-workflow/scripts/trigger-webhook.sh"
echo ""
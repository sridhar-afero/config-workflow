---
name: test-workflow
description: Test the n8n publish-config-changes workflow. Triggers webhooks, checks Jenkins jobs, and verifies the workflow execution.
allowed-tools: Bash(curl:*), Bash(kubectl:*), Read, Grep
---

# Test n8n Workflow

Test the publish-config-changes workflow end-to-end.

## Available Scripts

### 1. Check Prerequisites
Verify that all services are running and accessible:
```bash
bash .claude/skills/test-workflow/scripts/check-prereqs.sh
```

### 2. Trigger Workflow
Trigger the n8n webhook to start the workflow:
```bash
bash .claude/skills/test-workflow/scripts/trigger-webhook.sh
```

### 3. Check Jenkins Job Status
Monitor the Jenkins job execution:
```bash
bash .claude/skills/test-workflow/scripts/check-jenkins.sh
```

### 4. View n8n Executions
Check recent workflow executions in n8n:
```bash
bash .claude/skills/test-workflow/scripts/check-n8n.sh
```

### 5. Full Test
Run a complete end-to-end test with summary:
```bash
bash .claude/skills/test-workflow/scripts/full-test.sh
```

### 6. Check Workflow Status
Check the current status of a triggered workflow (can be run anytime):
```bash
bash .claude/skills/test-workflow/scripts/check-status.sh
```

## Environment Variables

Set these before running tests:
- `N8N_URL` - n8n base URL (default: http://localhost:5678)
- `JENKINS_URL` - Jenkins base URL (default: http://localhost:9090)
- `JENKINS_USER` - Jenkins username (default: admin)
- `JENKINS_TOKEN` - Jenkins API token (auto-retrieved from Kubernetes if available)
- `WORKFLOW_NAME` - n8n workflow name (default: Publish Config Changes)
- `N8N_API_KEY` - n8n API key (auto-retrieved from Kubernetes secret `n8n-api-key`)

## Workflow Under Test

The workflow:
1. Receives webhook trigger
2. Creates a Jira ticket
3. Triggers Jenkins non-prod deployment
4. Waits for Jira ticket to be marked "Done"
5. Triggers Jenkins prod deployment

## Setup Requirements

### n8n API Key
The scripts use the n8n API to dynamically fetch the webhook ID. Create an API key:
1. Login to n8n at http://localhost:5678
2. Go to Settings → API
3. Create an API key
4. Store it in Kubernetes:
```bash
kubectl create secret generic n8n-api-key --from-literal=api-key="YOUR_API_KEY"
```

### Workflow Activation
The workflow must be **active** in n8n for the webhook to work:
1. Open the workflow in n8n
2. Toggle the "Active" switch in the top-right corner

## Quick Test

To quickly verify the setup is working:
```bash
# Check services are up
curl -s http://localhost:5678/healthz
curl -s http://localhost:9090/login

# Check n8n workflow status
bash .claude/skills/test-workflow/scripts/check-n8n.sh
```

## Status Tracking

After triggering a workflow, you can check its status at any time:
```bash
bash .claude/skills/test-workflow/scripts/check-status.sh
```

This will show:
- Execution ID and timing
- Workflow progress (all 4 steps with status)
- Jira ticket number
- Jenkins builds triggered

## Data Source

All status information comes from the **n8n REST API** (`/api/v1/executions`):
- Execution status (running, success, error, waiting)
- Node execution results from workflow run data
- Jira ticket extracted from "Create an issue" node output
- Jenkins build status from deployment node outputs

n8n is the single source of truth - no need to query Jenkins or Jira directly.
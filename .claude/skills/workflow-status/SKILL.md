---
name: workflow-status
description: Check the status of the last workflow execution using n8n as the single source of truth.
allowed-tools: Bash(curl:*), Bash(kubectl:*), Bash(python3:*)
---

# Check Workflow Status

Check the current status of the last triggered workflow execution.

## Usage

Run the status check:
```bash
bash .claude/skills/workflow-status/scripts/check-status.sh
```

## What It Shows

- **Execution Info**: ID, start time, duration
- **Workflow Progress**:
  - Step 1: Webhook Triggered
  - Step 2: Non-Prod Deployment
  - Step 3: Jira Ticket (with ticket number)
  - Step 4: Prod Deployment
- **Details**: Jira ticket number, Jenkins builds triggered

## Data Source

This skill uses the **n8n REST API** (`/api/v1/executions`) as the single source of truth:
- Execution status (running, success, error, waiting)
- Node execution results (which steps completed)
- Jira ticket from "Create an issue" node output
- Jenkins build status from deployment nodes

No need to query Jenkins or Jira directly - all information comes from n8n execution data.

## Environment Variables

- `N8N_URL` - n8n base URL (default: http://localhost:5678)
- `N8N_API_KEY` - n8n API key (auto-retrieved from Kubernetes secret `n8n-api-key`)

## Prerequisites

- n8n must be running and accessible
- n8n API key must be configured (either env var or Kubernetes secret)
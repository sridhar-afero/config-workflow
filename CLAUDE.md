# CLAUDE.md - Project Context for Claude Code

## Project Overview

**Config Workflow** is a local development environment for testing an automated configuration deployment workflow. It orchestrates configuration changes across multiple environments (sandbox, dev, staging, prod) with Jira-based approval gates.

**Architecture Pattern**: Webhook trigger → Jira ticket creation → Non-prod deployment → Approval wait → Production deployment

## Tech Stack

| Component | Technology | Local Port | Purpose |
|-----------|------------|------------|---------|
| Orchestration | Kubernetes (Docker Desktop) | - | Container platform |
| Workflow Engine | n8n | 5678 | Automation orchestration |
| CI/CD | Jenkins | 9090 | Build and deployment |
| Database | PostgreSQL | 31544 | n8n backend |
| Issue Tracking | Jira Cloud | - | Approval gates |

## Directory Structure

```
config-workflow/
├── helm/
│   ├── setup.sh              # Install all services to K8s
│   └── values.yml            # n8n Helm chart config
├── jenkins/
│   └── pipeline              # Jenkinsfile (parameterized stages)
├── n8n/
│   └── publish-config-changes-workflow.json  # n8n workflow export
└── .claude/
    └── skills/
        ├── test-workflow/    # End-to-end testing scripts
        └── workflow-status/  # Status monitoring scripts
```

## Workflow Execution Flow

```
1. Webhook Trigger (curl to n8n)
   ↓
2. Create Jira Ticket (approval tracking)
   ↓
3. Jenkins Non-Prod Deployment (sandbox, dev, staging)
   ↓
4. Wait for Jira Approval (ticket status = "Done")
   ↓
5. Jenkins Prod Deployment
   ↓
6. Workflow Complete
```

## Key Files

| File | Purpose |
|------|---------|
| `helm/setup.sh` | Deploys PostgreSQL, Jenkins, n8n to Kubernetes |
| `helm/values.yml` | n8n configuration (DB connection, API enabled) |
| `jenkins/pipeline` | Declarative pipeline with environment-based stages |
| `n8n/publish-config-changes-workflow.json` | Complete workflow definition (import to n8n) |

## Common Commands

### Service Access (requires port-forwarding)
```bash
# Terminal 1: Jenkins
kubectl port-forward svc/my-jenkins 9090:8080

# Terminal 2: n8n
kubectl port-forward svc/my-n8n 5678:5678
```

### Health Checks
```bash
kubectl get pods                              # Check pod status
curl -s http://localhost:5678/healthz         # n8n health
curl -s http://localhost:9090/login           # Jenkins accessibility
```

### Testing
```bash
# Full end-to-end test
bash .claude/skills/test-workflow/scripts/full-test.sh

# Check workflow status
bash .claude/skills/workflow-status/scripts/check-status.sh

# Trigger webhook manually
bash .claude/skills/test-workflow/scripts/trigger-webhook.sh
```

### Jenkins Password
```bash
kubectl exec -it svc/my-jenkins -c jenkins -- cat /run/secrets/additional/chart-admin-password
```

## Claude Skills Available

| Skill | Command | Purpose |
|-------|---------|---------|
| test-workflow | `/test-workflow` | Run end-to-end workflow tests |
| workflow-status | `/workflow-status` | Check current workflow execution status |

## Environment Variables (for scripts)

| Variable | Default | Purpose |
|----------|---------|---------|
| `N8N_URL` | http://localhost:5678 | n8n base URL |
| `JENKINS_URL` | http://localhost:9090 | Jenkins base URL |
| `JENKINS_USER` | admin | Jenkins username |
| `JENKINS_TOKEN` | (from K8s secret) | Jenkins API token |
| `N8N_API_KEY` | (from K8s secret) | n8n API key |
| `WORKFLOW_NAME` | Publish Config Changes | n8n workflow name |

## n8n Workflow Nodes

1. **Webhook** - Entry point (GET request trigger)
2. **Create an issue** - Creates Jira ticket for approval
3. **Publish changes to non-prod** - Triggers Jenkins with `ENVIRONMENT=non-prod`
4. **Get Issue Status** - Polls Jira ticket status
5. **Check if Done** - Branches based on ticket status
6. **Trigger Jenkins Job** - Triggers Jenkins with `ENVIRONMENT=prod`

## Jenkins Pipeline Stages

- **Non-prod** (when ENVIRONMENT=non-prod):
  - Push config to Sandbox
  - Push config to Dev
  - Push config to Staging
- **Prod** (when ENVIRONMENT=prod):
  - Push config to Prod

## Database Configuration

```yaml
Type: PostgreSQL
Host: n8n-postgresql (K8s service)
Port: 5432
Database: n8n
User: n8n
Password: n8n123
```

## Troubleshooting

### Check Pod Logs
```bash
kubectl logs -f deployment/my-n8n
kubectl logs -f my-jenkins-0
```

### Restart Services
```bash
kubectl rollout restart deployment/my-n8n
kubectl delete pod my-jenkins-0  # StatefulSet will recreate
```

### Reset Everything
```bash
helm uninstall my-n8n my-jenkins n8n-postgresql
bash helm/setup.sh
```

## Data Source

**n8n is the single source of truth** for workflow status. All monitoring scripts query the n8n REST API (`/api/v1/executions`) to get:
- Execution status (running, success, error, waiting)
- Node execution results
- Jira ticket numbers
- Jenkins build status

## Setup Requirements

1. Docker Desktop with Kubernetes enabled
2. Helm 3.x installed
3. Jira Cloud account with API credentials
4. n8n API key stored in K8s secret: `kubectl create secret generic n8n-api-key --from-literal=api-key="KEY"`
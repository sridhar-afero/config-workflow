# Config Workflow

Local development environment for testing an automated configuration deployment workflow that integrates n8n, Jenkins, and Jira with approval gates.

## Overview

This project sets up a local environment on macOS to run and test a configuration management workflow that:

1. Receives configuration change requests via webhook
2. Creates a Jira ticket for tracking and approval
3. Automatically deploys to non-prod environments (sandbox, dev, staging)
4. Waits for Jira ticket approval (status: "Done")
5. Deploys to production upon approval

## Architecture

```
Webhook → n8n → Jira (create ticket) → Jenkins (non-prod deploy)
                     ↓
              Wait for approval
                     ↓
              Jira status = Done?
                     ↓
              Jenkins (prod deploy)
```

## Prerequisites

- macOS
- Docker Desktop with Kubernetes enabled
- Helm 3.x installed (`brew install helm`)
- kubectl configured (`brew install kubectl`)
- Jira Cloud account with API access

### Verify Prerequisites

```bash
# Check Docker Desktop is running with Kubernetes
kubectl config get-contexts
kubectl get nodes

# Check Helm is installed
helm version
```

## Directory Structure

```
├── helm/
│   ├── setup.sh          # Helm installation script
│   └── values.yml        # n8n configuration values
├── jenkins/
│   └── pipeline          # Jenkins pipeline definition
└── n8n/
    └── publish-config-changes-workflow.json  # n8n workflow export
```

## Setup

### 1. Install Helm Charts

Run the setup script to deploy PostgreSQL, Jenkins, and n8n to your local Kubernetes:

```bash
cd helm
chmod +x setup.sh
./setup.sh
```

This installs:
- **PostgreSQL** - Database backend for n8n (NodePort 31544)
- **Jenkins** - CI/CD server
- **n8n** - Workflow automation platform

### 2. Port Forward Services

Open two terminal windows and run:

```bash
# Terminal 1: Jenkins (k8s 8080 → local 9090)
kubectl port-forward svc/my-jenkins 9090:8080

# Terminal 2: n8n (k8s 5678 → local 5678)
kubectl port-forward svc/my-n8n 5678:5678
```

### 3. Access Services

- **Jenkins**: http://localhost:9090
- **n8n**: http://localhost:5678

### 4. Get Jenkins Admin Password

```bash
kubectl exec -it svc/my-jenkins -c jenkins -- cat /run/secrets/additional/chart-admin-password
```

### 5. Configure Jenkins

1. Log into Jenkins at http://localhost:9090
2. Create a new Pipeline job named "Test"
3. In the Pipeline section, paste the contents of `jenkins/pipeline`
4. Save the job

### 6. Configure n8n

1. Access n8n at http://localhost:5678
2. Create an account if first time
3. Go to Workflows → Import from File
4. Select `n8n/publish-config-changes-workflow.json`
5. Configure credentials:
   - **Jira**: Add your Jira Cloud API credentials
   - **Jenkins**: Add Jenkins API credentials (admin user + API token)
6. Update workflow nodes with your Jira project ID and issue type
7. Activate the workflow

## Testing the Workflow

### Trigger via Webhook

```bash
curl -X POST http://localhost:5678/webhook/17846341-fcdc-4839-b0dc-aa9ba822c93a
```

### Workflow Execution Flow

1. Webhook triggers the workflow
2. Jira ticket is created and assigned
3. Jenkins deploys to non-prod environments
4. Workflow pauses, waiting for Jira approval
5. Mark the Jira ticket as "Done"
6. Production deployment triggers automatically

### Manual Jenkins Execution

Run the Jenkins job directly with parameters:

- **non-prod**: Deploys to sandbox, dev, and staging
- **prod**: Deploys to production only

## Useful Commands

```bash
# Check pod status
kubectl get pods

# View n8n logs
kubectl logs -f deployment/my-n8n

# View Jenkins logs
kubectl logs -f deployment/my-jenkins

# Restart n8n
kubectl rollout restart deployment/my-n8n

# Uninstall everything
helm uninstall my-n8n my-jenkins n8n-postgresql
```

## Troubleshooting

### Port forward disconnects
Re-run the port-forward commands. Consider using a tool like `kubefwd` for persistent forwarding.

### n8n can't connect to Jenkins
Ensure Jenkins is accessible from within the cluster:
```bash
kubectl exec -it deployment/my-n8n -- curl http://my-jenkins:8080
```

### Webhook not responding
Check if the workflow is activated in n8n (toggle should be ON).

## Configuration

### Helm Values (values.yml)

```yaml
config:
  database:
    type: postgresdb
    postgresdb:
      host: n8n-postgresql
      user: n8n
      password: n8n123
```

### Kubernetes Context

The setup script uses `docker-desktop` context. Modify `kube_context` in `setup.sh` if different.

## Using Claude Code

This project includes Claude Code skills for automated setup assistance, testing, and monitoring.

### Available Skills

| Skill | Command | Purpose |
|-------|---------|---------|
| **test-workflow** | `/test-workflow` | Run end-to-end workflow tests |
| **workflow-status** | `/workflow-status` | Check current workflow execution status |

### Setup with Claude Code

Claude Code can help you set up and configure the environment:

```
# Ask Claude to help with initial setup
"Help me set up the config workflow environment"

# Claude will guide you through:
# 1. Running helm/setup.sh
# 2. Setting up port forwarding
# 3. Configuring Jenkins and n8n
# 4. Creating necessary API keys and secrets
```

### Testing with Claude Code

Run the test workflow skill to execute end-to-end tests:

```
/test-workflow
```

This will:
1. Check all prerequisites (kubectl, pods, services)
2. Verify n8n and Jenkins are accessible
3. Trigger the workflow webhook
4. Monitor Jenkins build execution
5. Display Jira ticket creation
6. Show comprehensive test summary

**Example Output:**
```
┌─────────────────────────────────────────────────────────┐
│  WORKFLOW STATUS                                        │
├─────────────────────────────────────────────────────────┤
│  Webhook Trigger      │  ✅ Workflow Started             │
│  Jenkins Build        │  ✅ SUCCESS                      │
│  Jira Ticket          │  ✅ TES-42                       │
│  Prod Deployment      │  ⏸️  Waiting for Jira            │
└─────────────────────────────────────────────────────────┘
```

### Checking Workflow Status

Check the status of a running or completed workflow:

```
/workflow-status
```

This queries the n8n REST API (single source of truth) and displays:
- Execution ID and timing
- 4-step workflow progress with status indicators
- Jira ticket number
- Jenkins builds triggered

**Example Output:**
```
  [1] Webhook Triggered        ✅ Complete
  [2] Non-Prod Deployment      ✅ Complete
  [3] Jira Ticket              ✅ TES-42 (Done)
  [4] Prod Deployment          ✅ Complete

  Status: WORKFLOW COMPLETE
```

### Typical Workflow with Claude Code

1. **Start the test:**
   ```
   /test-workflow
   ```

2. **Check status while waiting:**
   ```
   /workflow-status
   ```

3. **After approving Jira ticket, verify completion:**
   ```
   /workflow-status
   ```

### Prerequisites for Claude Skills

Before using the skills, ensure:

1. **n8n API Key** is configured:
   ```bash
   # Create API key in n8n UI: Settings → API
   kubectl create secret generic n8n-api-key --from-literal=api-key="YOUR_KEY"
   ```

2. **Workflow is active** in n8n (toggle ON in workflow editor)

3. **Port forwarding** is running for both services

### Manual Script Execution

Scripts can also be run directly without Claude Code:

```bash
# Check prerequisites
bash .claude/skills/test-workflow/scripts/check-prereqs.sh

# Check n8n status
bash .claude/skills/test-workflow/scripts/check-n8n.sh

# Trigger the workflow
bash .claude/skills/test-workflow/scripts/trigger-webhook.sh

# Check workflow status
bash .claude/skills/workflow-status/scripts/check-status.sh

# Full end-to-end test
bash .claude/skills/test-workflow/scripts/full-test.sh
```

### Environment Variables

Scripts auto-retrieve credentials from Kubernetes secrets, but you can override:

| Variable | Default | Description |
|----------|---------|-------------|
| `N8N_URL` | http://localhost:5678 | n8n base URL |
| `JENKINS_URL` | http://localhost:9090 | Jenkins base URL |
| `JENKINS_USER` | admin | Jenkins username |
| `JENKINS_TOKEN` | (from K8s secret) | Jenkins API token |
| `N8N_API_KEY` | (from K8s secret) | n8n API key |
| `WORKFLOW_NAME` | Publish Config Changes | Workflow to test |

## License

Internal use only.
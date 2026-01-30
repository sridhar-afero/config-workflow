# Config Workflow

An automated configuration deployment workflow that integrates n8n, Jenkins, and Jira for controlled deployments with approval gates.

## Overview

This project provides infrastructure-as-code for deploying a configuration management workflow that:

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

- Kubernetes cluster (tested with Docker Desktop)
- Helm 3.x
- kubectl configured with cluster access
- Jira Cloud account with API access
- Jenkins credentials

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

### 1. Deploy Infrastructure

Run the Helm setup script to deploy PostgreSQL, Jenkins, and n8n:

```bash
cd helm
chmod +x setup.sh
./setup.sh
```

This installs:
- **PostgreSQL** - Database backend for n8n (exposed on NodePort 31544)
- **Jenkins** - CI/CD server for deployments
- **n8n** - Workflow automation platform

### 2. Configure Jenkins

1. Access Jenkins and create a new pipeline job named "Test"
2. Copy the contents of `jenkins/pipeline` into the pipeline configuration
3. Configure deployment scripts for each environment stage

### 3. Configure n8n

1. Access the n8n web interface
2. Import the workflow from `n8n/publish-config-changes-workflow.json`
3. Configure credentials:
   - Jira Cloud API credentials
   - Jenkins API credentials
4. Update the workflow nodes with your:
   - Jira project ID
   - Jira issue type
   - Jenkins job name

### 4. Configure Jira Integration

Ensure your Jira account has:
- API token generated
- Project created for tracking config changes
- Appropriate issue types configured

## Usage

### Triggering a Deployment

Send a POST request to the n8n webhook endpoint:

```bash
curl -X POST https://your-n8n-instance/webhook/17846341-fcdc-4839-b0dc-aa9ba822c93a
```

### Workflow Execution

1. Webhook triggers the workflow
2. A Jira ticket is created and assigned
3. Jenkins deploys to non-prod environments automatically
4. Workflow pauses and waits for Jira ticket approval
5. When the ticket is marked "Done", production deployment triggers

### Manual Jenkins Execution

The Jenkins pipeline can also be run directly with environment selection:

- **non-prod**: Deploys to sandbox, dev, and staging
- **prod**: Deploys to production only

## Configuration

### Helm Values (values.yml)

```yaml
config:
  database:
    type: postgresdb
    postgresdb:
      host: n8n-postgresql
      user: n8n
      password: n8n123    # Change in production
```

### Environment Variables

Update `helm/setup.sh` for your environment:

- `kube_context` - Kubernetes context to use

## Security Notes

- Change default database passwords before production use
- Store credentials in Kubernetes secrets
- Use HTTPS for webhook endpoints
- Restrict Jenkins and n8n access with proper authentication

## License

Internal use only.
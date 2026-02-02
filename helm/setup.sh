#!/bin/bash
# Setup script for config-workflow infrastructure
# Installs PostgreSQL, Jenkins, and n8n on Kubernetes

set -e

kube_context="${KUBE_CONTEXT:-docker-desktop}"

echo "=== Installing PostgreSQL for n8n ==="
helm install n8n-postgresql oci://registry-1.docker.io/bitnamicharts/postgresql \
  --set auth.username=n8n \
  --set auth.password=n8n123 \
  --set auth.database=n8n \
  --set primary.service.type=NodePort \
  --set primary.service.nodePorts.postgresql=31544 \
  --set service.nodePorts.postgresql=31544 \
  --kube-context ${kube_context}

echo "=== Installing Jenkins ==="
helm repo add jenkins https://charts.jenkins.io
helm repo update
helm install my-jenkins jenkins/jenkins --kube-context ${kube_context}

echo "=== Waiting for PostgreSQL to be ready ==="
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=postgresql --timeout=120s --context ${kube_context}

echo "=== Installing n8n (configured for PostgreSQL) ==="
helm install my-n8n oci://8gears.container-registry.com/library/n8n \
  -f values.yml \
  --kube-context ${kube_context}

echo ""
echo "=== Setup Complete ==="
echo "Services installed:"
echo "  - PostgreSQL: localhost:31544"
echo "  - Jenkins: kubectl port-forward svc/my-jenkins 9090:8080"
echo "  - n8n: kubectl port-forward svc/my-n8n 5678:80"
echo ""
echo "To verify n8n is using PostgreSQL, check the logs:"
echo "  kubectl logs deploy/my-n8n | grep -i postgres"

#!/bin/bash
set -e

N8N_URL="${N8N_URL:-http://localhost:5678}"
JENKINS_URL="${JENKINS_URL:-http://localhost:9090}"

echo "Checking prerequisites for config-workflow testing"
echo "==================================================="
echo ""

# Check kubectl
echo "1. Checking kubectl..."
if command -v kubectl &> /dev/null; then
    echo "   kubectl: OK"
    CONTEXT=$(kubectl config current-context 2>/dev/null || echo "none")
    echo "   Current context: $CONTEXT"
else
    echo "   kubectl: NOT FOUND"
    exit 1
fi

# Check Kubernetes cluster
echo ""
echo "2. Checking Kubernetes cluster..."
if kubectl get nodes &> /dev/null; then
    NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
    echo "   Cluster: OK ($NODE_COUNT nodes)"
else
    echo "   Cluster: NOT ACCESSIBLE"
    exit 1
fi

# Check pods
echo ""
echo "3. Checking deployed pods..."
echo "   Pods in default namespace:"
kubectl get pods --no-headers 2>/dev/null | while read line; do
    NAME=$(echo "$line" | awk '{print $1}')
    STATUS=$(echo "$line" | awk '{print $3}')
    echo "   - $NAME: $STATUS"
done

# Check n8n accessibility
echo ""
echo "4. Checking n8n at $N8N_URL..."
if curl -s --connect-timeout 5 "$N8N_URL" > /dev/null 2>&1; then
    echo "   n8n: ACCESSIBLE"
else
    echo "   n8n: NOT ACCESSIBLE"
    echo "   Hint: Run 'kubectl port-forward svc/my-n8n 5678:5678'"
fi

# Check Jenkins accessibility
echo ""
echo "5. Checking Jenkins at $JENKINS_URL..."
if curl -s --connect-timeout 5 "$JENKINS_URL" > /dev/null 2>&1; then
    echo "   Jenkins: ACCESSIBLE"
else
    echo "   Jenkins: NOT ACCESSIBLE"
    echo "   Hint: Run 'kubectl port-forward svc/my-jenkins 9090:8080'"
fi

echo ""
echo "==================================================="
echo "Prerequisites check complete"
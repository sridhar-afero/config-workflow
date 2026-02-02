#!/bin/bash
# Check Jenkins job status with automatic credential retrieval

JENKINS_URL="${JENKINS_URL:-http://localhost:9090}"
JENKINS_USER="${JENKINS_USER:-admin}"
JENKINS_TOKEN="${JENKINS_TOKEN:-}"
JOB_NAME="${JOB_NAME:-Test}"

echo "Checking Jenkins job status"
echo "============================"
echo ""
echo "Jenkins URL: $JENKINS_URL"
echo "Job: $JOB_NAME"
echo ""

# Get Jenkins credentials from Kubernetes if not set
if [ -z "$JENKINS_TOKEN" ]; then
    echo "Fetching credentials from Kubernetes..."
    JENKINS_TOKEN=$(kubectl get secret my-jenkins -o jsonpath='{.data.jenkins-admin-password}' 2>/dev/null | base64 -d 2>/dev/null || echo "")
    if [ -n "$JENKINS_TOKEN" ]; then
        echo "Credentials retrieved successfully"
    fi
fi

# Build auth header if credentials provided
AUTH_OPTS=""
if [ -n "$JENKINS_TOKEN" ]; then
    AUTH_OPTS="--user $JENKINS_USER:$JENKINS_TOKEN"
else
    echo "WARNING: No Jenkins credentials available"
    echo ""
    echo "To set credentials:"
    echo "  export JENKINS_USER=admin"
    echo "  export JENKINS_TOKEN=your-api-token"
    echo ""
    echo "Or run from a context with kubectl access to retrieve from k8s secret"
    exit 1
fi

echo ""

# Get job info
echo "Fetching job information..."
JOB_INFO=$(curl -s $AUTH_OPTS "$JENKINS_URL/job/$JOB_NAME/api/json?tree=name,color,lastBuild\[number,result,timestamp,duration\]" 2>/dev/null)

if [ -z "$JOB_INFO" ] || echo "$JOB_INFO" | grep -q "Authentication required"; then
    echo "ERROR: Could not fetch job info. Check credentials or job name."
    exit 1
fi

echo ""
echo "Job Info:"
echo "$JOB_INFO" | python3 -m json.tool 2>/dev/null || echo "$JOB_INFO"

# Get last build info
echo ""
echo "Last Build Details:"
LAST_BUILD=$(curl -s $AUTH_OPTS "$JENKINS_URL/job/$JOB_NAME/lastBuild/api/json?tree=number,result,timestamp,duration,building" 2>/dev/null)

if [ -n "$LAST_BUILD" ] && ! echo "$LAST_BUILD" | grep -q "404"; then
    echo "$LAST_BUILD" | python3 -m json.tool 2>/dev/null || echo "$LAST_BUILD"

    BUILDING=$(echo "$LAST_BUILD" | python3 -c "import sys,json; print(json.load(sys.stdin).get('building', False))" 2>/dev/null || echo "False")
    RESULT=$(echo "$LAST_BUILD" | python3 -c "import sys,json; print(json.load(sys.stdin).get('result', 'N/A'))" 2>/dev/null || echo "N/A")

    echo ""
    if [ "$BUILDING" = "True" ]; then
        echo "Status: ⏳ BUILDING"
    elif [ "$RESULT" = "SUCCESS" ]; then
        echo "Status: ✅ SUCCESS"
    elif [ "$RESULT" = "FAILURE" ]; then
        echo "Status: ❌ FAILURE"
    else
        echo "Status: $RESULT"
    fi
else
    echo "No builds found for this job"
fi

echo ""
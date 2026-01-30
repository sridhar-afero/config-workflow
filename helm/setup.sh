kube_context="docker-desktop"

helm install n8n-postgresql oci://registry-1.docker.io/bitnamicharts/postgresql \
  --set auth.username=n8n \
  --set auth.password=n8n123 \
  --set auth.database=n8n \
  --set primary.service.type=NodePort \
  --set primary.service.nodePorts.postgresql=31544 \
  --set service.nodePorts.postgresql=31544 \
  --kube-context ${kube_context}

helm repo add jenkins https://charts.jenkins.io
helm repo update
helm install my-jenkins jenkins/jenkins --kube-context ${kube_context}

helm install my-n8n oci://8gears.container-registry.com/library/n8n -f values.yml --kube-context ${kube_context}
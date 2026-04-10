#!/bin/bash
# Create maven-settings-secret from github-maven-credentials

set -e

NAMESPACE="tekton-pipelines"

# Get credentials from the secret
USERNAME=$(kubectl get secret github-maven-credentials -n "$NAMESPACE" -o jsonpath='{.data.username}' | base64 -d)
TOKEN=$(kubectl get secret github-maven-credentials -n "$NAMESPACE" -o jsonpath='{.data.token}' | base64 -d)

# Create settings.xml content
SETTINGS_XML=$(cat <<EOF
<settings>
  <servers>
    <server>
      <id>github</id>
      <username>$USERNAME</username>
      <password>$TOKEN</password>
    </server>
  </servers>
</settings>
EOF
)

# Create the secret
kubectl create secret generic maven-settings-secret \
  --from-literal=settings.xml="$SETTINGS_XML" \
  -n "$NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✅ maven-settings-secret created/updated in namespace: $NAMESPACE"

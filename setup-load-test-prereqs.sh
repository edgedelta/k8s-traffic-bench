#!/bin/bash
# Usage: ./setup-load-test-prereqs.sh [NAMESPACE]

# Default to 'default' namespace if not specified
NAMESPACE=${1:-default}

echo "Setting up load test prerequisites in namespace: $NAMESPACE"

kubectl get namespace $NAMESPACE &>/dev/null || {
  echo "Namespace '$NAMESPACE' does not exist. Creating it..."
  kubectl create namespace $NAMESPACE
}

# Create service account in the specified namespace
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: load-test-sa
  namespace: $NAMESPACE
EOF

# Create ClusterRole (this is cluster-wide, not namespaced)
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: load-test-role
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list"]
- apiGroups: [""]
  resources: ["pods/exec"]
  verbs: ["create"]
- apiGroups: ["metrics.k8s.io"]
  resources: ["pods"]
  verbs: ["get", "list"]
EOF

# Create ClusterRoleBinding with the namespace-specific service account
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: load-test-rolebinding-$NAMESPACE
subjects:
- kind: ServiceAccount
  name: load-test-sa
  namespace: $NAMESPACE
roleRef:
  kind: ClusterRole
  name: load-test-role
  apiGroup: rbac.authorization.k8s.io
EOF

# Check if secret already exists in the namespace
if ! kubectl -n $NAMESPACE get secret load-test-credentials &>/dev/null; then
  echo "Creating empty load-test-credentials secret in namespace '$NAMESPACE'..."
  kubectl -n $NAMESPACE create secret generic load-test-credentials \
    --from-literal=access-key="" \
    --from-literal=secret-key="" \
    --from-literal=region="" \
    --from-literal=bucket="" \
    --from-literal=slack-url=""
  
  echo ""
  echo "Secret 'load-test-credentials' created with placeholder values in namespace '$NAMESPACE'."
  echo "Update it with your actual credentials using:"
  echo ""
  echo "kubectl -n $NAMESPACE create secret generic load-test-credentials \\"
  echo "  --from-literal=access-key='YOUR_AWS_ACCESS_KEY' \\"
  echo "  --from-literal=secret-key='YOUR_AWS_SECRET_KEY' \\"
  echo "  --from-literal=region='YOUR_AWS_REGION' \\"
  echo "  --from-literal=bucket='YOUR_S3_BUCKET' \\"
  echo "  --from-literal=slack-url='YOUR_SLACK_WEBHOOK_URL' \\"
  echo "  --dry-run=client -o yaml | kubectl apply -f -"
else
  echo "Secret 'load-test-credentials' already exists in namespace '$NAMESPACE'."
fi

echo "Load test prerequisites setup complete in namespace '$NAMESPACE'."
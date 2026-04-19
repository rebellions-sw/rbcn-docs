#!/usr/bin/env bash
# Headlamp ↔ Keycloak SSO + OIDC impersonation
#
# 효과: Headlamp 가 Keycloak token 의 groups 를 K8s impersonate header 로 변환
#       → cluster-admin SA 토큰 제거 가능

set -euo pipefail
ENV="${1:-dev}"
KEYCLOAK_URL="${KEYCLOAK_URL:-https://keycloak.rebellions.ai}"
REALM="${REALM:-rebellions}"

KCFG="$HOME/.kube/config-$ENV"
export KUBECONFIG="$KCFG"

CLIENT_ID="headlamp"
CLIENT_SECRET="${CLIENT_SECRET:-$(vault kv get -field=client_secret secret/sso/headlamp 2>/dev/null || echo CHANGE_ME)}"

# 1. ClusterRoleBindings 으로 group → K8s 권한 매핑 (한 번만)
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata: { name: rbcn-admins }
subjects: [ { kind: Group, name: rbcn-admins, apiGroup: rbac.authorization.k8s.io } ]
roleRef: { kind: ClusterRole, name: cluster-admin, apiGroup: rbac.authorization.k8s.io }
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata: { name: rbcn-platform }
subjects: [ { kind: Group, name: rbcn-platform, apiGroup: rbac.authorization.k8s.io } ]
roleRef: { kind: ClusterRole, name: edit, apiGroup: rbac.authorization.k8s.io }
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata: { name: rbcn-dev }
subjects: [ { kind: Group, name: rbcn-dev, apiGroup: rbac.authorization.k8s.io } ]
roleRef: { kind: ClusterRole, name: edit, apiGroup: rbac.authorization.k8s.io }
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata: { name: rbcn-readonly }
subjects: [ { kind: Group, name: rbcn-readonly, apiGroup: rbac.authorization.k8s.io } ]
roleRef: { kind: ClusterRole, name: view, apiGroup: rbac.authorization.k8s.io }
EOF

# 2. K8s API server 에 OIDC flag 추가 (cluster-init 시 더 안전)
echo ""
echo "  K8s API server flags 필요 (kube-apiserver):"
cat <<EOF
    --oidc-issuer-url=${KEYCLOAK_URL}/realms/${REALM}
    --oidc-client-id=${CLIENT_ID}
    --oidc-username-claim=email
    --oidc-groups-claim=groups
EOF

# 3. Headlamp configmap
kubectl -n headlamp create cm headlamp-config --dry-run=client -o yaml --from-literal=oidc-issuer-url=${KEYCLOAK_URL}/realms/${REALM} --from-literal=oidc-client-id=${CLIENT_ID} | kubectl apply -f -

echo ""
echo "Restart headlamp:"
echo "  kubectl -n headlamp rollout restart deploy headlamp"

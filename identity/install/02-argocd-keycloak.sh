#!/usr/bin/env bash
# ArgoCD ↔ Keycloak SSO 통합
#
# 사전조건:
#   1. Keycloak 에 'argocd' client 생성 (PKCE off, code flow, secret 생성)
#   2. group claim 매핑: groups → user.groups
#   3. Vault 에 client_secret 저장: vault kv put secret/sso/argocd client_secret=...

set -euo pipefail
ENV="${1:-dev}"
KEYCLOAK_URL="${KEYCLOAK_URL:-https://keycloak.rebellions.ai}"
REALM="${REALM:-rebellions}"

KCFG="$HOME/.kube/config-$ENV"
[ -f "$KCFG" ] || { echo "no kubeconfig $KCFG"; exit 1; }
export KUBECONFIG="$KCFG"

CLIENT_ID="argocd"
CLIENT_SECRET="${CLIENT_SECRET:-$(vault kv get -field=client_secret secret/sso/argocd 2>/dev/null || echo CHANGE_ME)}"

echo "[*] Patching argocd-cm with OIDC config..."
kubectl -n argocd patch cm argocd-cm --type=merge -p "$(cat <<EOF
{
  "data": {
    "url": "https://argocd.${ENV}.infra.rblnconnect.ai",
    "oidc.config": "name: Keycloak\nissuer: ${KEYCLOAK_URL}/realms/${REALM}\nclientID: ${CLIENT_ID}\nclientSecret: ${CLIENT_SECRET}\nrequestedScopes: [\"openid\", \"profile\", \"email\", \"groups\"]\nrequestedIDTokenClaims: { groups: { essential: true } }\n"
  }
}
EOF
)"

echo "[*] Patching argocd-rbac-cm with group→role mapping..."
kubectl -n argocd patch cm argocd-rbac-cm --type=merge -p "$(cat <<'EOF'
{
  "data": {
    "policy.default": "role:readonly",
    "policy.csv": "g, rbcn-admins, role:admin\ng, rbcn-platform, role:admin\ng, rbcn-dev, role:dev\ng, rbcn-readonly, role:readonly\np, role:dev, applications, sync, default/*, allow\np, role:dev, applications, get, default/*, allow\np, role:dev, applications, action/*, default/*, allow\np, role:dev, logs, get, default/*, allow\n",
    "scopes": "[groups, email]"
  }
}
EOF
)"

echo "[*] Restart argocd-server to pick up changes..."
kubectl -n argocd rollout restart deploy argocd-server
kubectl -n argocd rollout status deploy argocd-server --timeout=2m

echo "OK. 로그인: https://argocd.${ENV}.infra.rblnconnect.ai → Login via Keycloak"

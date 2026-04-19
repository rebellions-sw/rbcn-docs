#!/usr/bin/env bash
# CloudNative-PG Operator 설치 (모든 클러스터)
#
# DB 셀프서비스의 핵심: 1 CR 한 장으로 PostgreSQL HA 클러스터 + 백업 + PITR.
#
# 사용:
#   bash install.sh dev
#   bash install.sh stage
#   bash install.sh prod

set -euo pipefail
ENV="${1:-dev}"
KCFG="$HOME/.kube/config-$ENV"

[ -f "$KCFG" ] || { echo "[FAIL] kubeconfig not found: $KCFG"; exit 1; }
export KUBECONFIG="$KCFG"

echo "[*] Adding cnpg helm repo..."
helm repo add cnpg https://cloudnative-pg.github.io/charts 2>/dev/null || true
helm repo update cnpg

echo "[*] Installing cnpg operator..."
helm upgrade --install cnpg cnpg/cloudnative-pg \
  -n cnpg-system --create-namespace \
  --set crds.create=true \
  --version 0.22.* \
  --wait

echo "[*] Verifying CRDs..."
kubectl get crd | grep postgresql.cnpg.io || { echo "[FAIL] CRDs not installed"; exit 1; }

echo "[*] Operator pods:"
kubectl -n cnpg-system get pods

echo ""
echo "OK. New DB 만들기:"
echo "  cp /opt/rbcn-docs/operators/cloudnative-pg/db-template.yaml /tmp/mydb.yaml"
echo "  vi /tmp/mydb.yaml  # name 만 바꾸면 됨"
echo "  kubectl apply -f /tmp/mydb.yaml"

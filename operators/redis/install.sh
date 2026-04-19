#!/usr/bin/env bash
# Bitnami Redis Helm 표준 설치 스크립트.
# 새 캐시: bash install.sh dev my-svc my-svc-cache
set -euo pipefail
ENV="${1:?env}"; NS="${2:?namespace}"; NAME="${3:?release name}"

export KUBECONFIG="$HOME/.kube/config-$ENV"

helm repo add bitnami https://charts.bitnami.com/bitnami 2>/dev/null || true
helm repo update bitnami

helm upgrade --install "$NAME" bitnami/redis \
  -n "$NS" --create-namespace \
  --version 19.* \
  --set architecture=replication \
  --set auth.enabled=true \
  --set auth.usePasswordFiles=true \
  --set master.persistence.enabled=true \
  --set master.persistence.storageClass=local-path \
  --set master.persistence.size=5Gi \
  --set replica.replicaCount=2 \
  --set metrics.enabled=true \
  --set metrics.serviceMonitor.enabled=true \
  --set networkPolicy.enabled=true \
  --set tls.enabled=false \
  --wait

echo ""
echo "OK: redis://${NAME}-master.${NS}.svc:6379"
echo "비밀번호: kubectl -n ${NS} get secret ${NAME} -o jsonpath='{.data.redis-password}' | base64 -d"

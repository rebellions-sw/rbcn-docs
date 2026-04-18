#!/bin/bash
# Finalized post-mortem 을 Vault 에 백업
set -euo pipefail
ID=${1:?'PM ID required (e.g. PM-2026-04-19-my-incident)'}
DIR="$(dirname "$0")"

# 파일 찾기 (slug 기반 매칭)
SLUG=$(echo "$ID" | sed 's/^PM-[0-9-]\{10\}-//')
FILE=$(find "$DIR" -name "*${SLUG}*.md" -path "*[0-9][0-9][0-9][0-9]/*" | head -1)
[[ -z "$FILE" ]] && { echo "파일을 찾을 수 없음: $ID (slug=$SLUG)"; exit 1; }

# Vault 토큰 로드 (common.sh 와 동일 로직)
if [ -z "${VAULT_TOKEN:-}" ] && [ -f /root/.vault/vault-init.json ]; then
    export VAULT_TOKEN=$(jq -r '.root_token' /root/.vault/vault-init.json)
fi

B64=$(base64 -w0 < "$FILE")
SIZE=$(stat -c %s "$FILE")
SHA=$(sha256sum "$FILE" | awk '{print $1}')

vault kv put -mount=secret "postmortems/${ID}" \
    content="$B64" \
    file_path="$FILE" \
    size_bytes="$SIZE" \
    sha256="$SHA" \
    backed_up_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "Vault 백업 완료: secret/postmortems/${ID} (${SIZE} bytes)"

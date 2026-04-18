#!/bin/bash
# 새 post-mortem 생성 헬퍼
# 사용법: ./new-postmortem.sh <slug> <severity> <category>
set -euo pipefail
SLUG=${1:?slug required}
SEV=${2:-P2}
CAT=${3:-app}
DATE=$(date -u +%Y-%m-%d)
YEAR=$(date -u +%Y)
ID="PM-${DATE}-${SLUG}"
DIR="$(dirname "$0")/${YEAR}"
FILE="${DIR}/${DATE}-${SLUG}.md"

mkdir -p "$DIR"
if [[ -f "$FILE" ]]; then
    echo "이미 존재: $FILE"
    exit 1
fi

sed -e "s|<간결한 제목>|${SLUG}|" \
    -e "s|PM-YYYY-MM-DD-<slug>|${ID}|" \
    -e "0,/YYYY-MM-DD/{s|YYYY-MM-DD|${DATE}|}" \
    -e "s|YYYY-MM-DD HH:MM UTC|$(date -u +'%Y-%m-%d %H:%M UTC')|g" \
    -e "s|P1 / P2 / P3|${SEV}|" \
    -e "s|infra / k8s / network / security / data / app / human|${CAT}|" \
    "$(dirname "$0")/TEMPLATE.md" > "$FILE"

echo "새 post-mortem 생성: $FILE"
echo ""
echo "다음 단계:"
echo "  1. \$EDITOR $FILE  # 작성"
echo "  2. cd /opt/rbcn-docs && git add postmortems/ && git commit -m 'pm: ${ID}'"
echo "  3. cd \$(dirname \"$FILE\")/.. && bash update-index.sh"
echo "  4. # Finalized 후: bash backup-to-vault.sh ${ID}"

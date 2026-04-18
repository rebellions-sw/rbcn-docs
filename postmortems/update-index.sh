#!/bin/bash
# INDEX.md 자동 생성
set -uo pipefail   # set -e 제거: 빈 디렉토리/매치없음 정상 처리
shopt -s nullglob
cd "$(dirname "$0")"

cat > INDEX.md <<EOF
# Post-mortem Index

생성일: $(date -u +%Y-%m-%dT%H:%M:%SZ)

## 통계

EOF

# 모든 PM 파일 수집
PMS=()
for year in [0-9][0-9][0-9][0-9]; do
    [[ -d "$year" ]] || continue
    for f in "$year"/*.md; do
        [[ -f "$f" ]] && PMS+=("$f")
    done
done

total=${#PMS[@]}

# 연도별 통계
for year in [0-9][0-9][0-9][0-9]; do
    [[ -d "$year" ]] || continue
    cnt=0
    for f in "$year"/*.md; do
        [[ -f "$f" ]] && cnt=$((cnt+1))
    done
    echo "- **$year**: $cnt 건" >> INDEX.md
done
echo "- **Total**: $total 건" >> INDEX.md
echo "" >> INDEX.md

# Severity 분포
echo "## Severity 분포" >> INDEX.md
for sev in P1 P2 P3; do
    cnt=0
    for f in "${PMS[@]}"; do
        grep -q "^| \*\*Severity\*\* | $sev" "$f" 2>/dev/null && cnt=$((cnt+1))
    done
    echo "- **$sev**: $cnt 건" >> INDEX.md
done
echo "" >> INDEX.md

# Category 분포
echo "## Category 분포" >> INDEX.md
for cat in infra k8s network security data app human; do
    cnt=0
    for f in "${PMS[@]}"; do
        grep -q "^| \*\*Category\*\* | $cat" "$f" 2>/dev/null && cnt=$((cnt+1))
    done
    echo "- **$cat**: $cnt 건" >> INDEX.md
done
echo "" >> INDEX.md

# 시간 역순 목록
echo "## 시간 역순 목록" >> INDEX.md
echo "" >> INDEX.md
echo "| Date | ID | Severity | Category | Title | Status |" >> INDEX.md
echo "|------|-----|----------|----------|-------|--------|" >> INDEX.md

# 역순 정렬
IFS=$'\n' SORTED=($(printf '%s\n' "${PMS[@]}" | sort -r)); unset IFS
for f in "${SORTED[@]}"; do
    fname=$(basename "$f" .md)
    date=$(echo "$fname" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}')
    id=$(grep -m1 '| \*\*ID\*\* |' "$f" 2>/dev/null | sed 's/.*| \([^|]*\) |/\1/' | xargs || echo "?")
    sev=$(grep -m1 '| \*\*Severity\*\* |' "$f" 2>/dev/null | sed 's/.*| \([^|]*\) |/\1/' | xargs || echo "?")
    cat=$(grep -m1 '| \*\*Category\*\* |' "$f" 2>/dev/null | sed 's/.*| \([^|]*\) |/\1/' | xargs || echo "?")
    title=$(grep -m1 '^# Incident' "$f" 2>/dev/null | sed 's/# Incident Post-mortem: //' || echo "?")
    status=$(grep -m1 '| \*\*Status\*\* |' "$f" 2>/dev/null | sed 's/.*| \([^|]*\) |/\1/' | xargs || echo "?")
    echo "| $date | [$id]($f) | $sev | $cat | $title | $status |" >> INDEX.md
done

echo "INDEX.md 갱신 완료 (총 $total건)"

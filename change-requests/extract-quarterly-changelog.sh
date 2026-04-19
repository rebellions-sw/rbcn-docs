#!/bin/bash
# 분기별 CR/PR changelog 추출 (SOC2 evidence)
QUARTER="${1:-Q1-2026}"
START="${2:-2026-01-01}"
END="${3:-2026-03-31}"

OUT=$HOME/changelog-${QUARTER}.md

cat > $OUT <<HEADER
# Changelog - ${QUARTER} (${START} ~ ${END})

> SOC2 audit evidence — 변경 내역, 승인자, 검증 결과
HEADER

for repo_dir in /opt/rbcn-docs/cost-reports /opt/rbcn-docs/incidents /opt/rbcn-docs/runbooks; do
    if [ -d "$repo_dir/.git" ]; then
        echo "" >> $OUT
        echo "## $(basename $repo_dir)" >> $OUT
        cd $repo_dir
        git log --since="$START" --until="$END" --pretty=format:"- [%h] %s — %an" >> $OUT
    fi
done

echo "" >> $OUT
echo "## ArgoCD Applications (sync history)" >> $OUT
for env in dev stage prod; do
    echo "" >> $OUT
    echo "### $env" >> $OUT
    kubectl --kubeconfig $HOME/.kube/config-${env} -n argocd get application -o jsonpath='{range .items[*]}- {.metadata.name}: {.status.sync.revision}{"\n"}{end}' >> $OUT 2>/dev/null
done

echo "Generated: $OUT"

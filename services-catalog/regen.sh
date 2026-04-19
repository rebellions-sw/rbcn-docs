#!/usr/bin/env bash
# services.yaml → services/<svc>-<env>.yaml 평탄화 (ApplicationSet git generator 가 file 단위 펼침)
#
# 사용: ./regen.sh
# 또는: rbcn catalog regen
#
# 새 서비스를 추가했거나 environments 가 바뀌었으면 호출.

set -euo pipefail
cd "$(dirname "$0")"

[ -f services.yaml ] || { echo "services.yaml not found"; exit 1; }
command -v python3 >/dev/null || { echo "python3 missing"; exit 1; }

rm -rf services/
mkdir -p services/

python3 << 'EOF'
import yaml, os, sys

CLUSTERS = {
    'dev':   os.environ.get('DEV_CLUSTER',   'https://kubernetes.default.svc'),
    'stage': os.environ.get('STAGE_CLUSTER', 'https://kubernetes.default.svc'),
    'prod':  os.environ.get('PROD_CLUSTER',  'https://kubernetes.default.svc'),
}

data = yaml.safe_load(open('services.yaml'))
count = 0
for s in data.get('services', []):
    for env in s.get('environments', ['dev']):
        if env not in CLUSTERS:
            print(f'  WARN: unknown env "{env}" in {s["name"]}', file=sys.stderr)
            continue
        out = {
            'name':    s['name'],
            'env':     env,
            'branch':  env,
            'cluster': CLUSTERS[env],
            'type':    s['type'],
            'owner':   s['owner'],
            'tier':    s['tier'],
            'repo':    s['repo'],
        }
        fp = f'services/{s["name"]}-{env}.yaml'
        with open(fp, 'w') as f:
            yaml.dump(out, f, sort_keys=False, default_flow_style=False)
        count += 1
        print(f'  + {fp}')

print(f'\ngenerated {count} per-env service files')
EOF

echo
echo "다음:"
echo "  1) git diff services/ → 변화 검토"
echo "  2) git add -A && git commit -m \"chore: regen catalog\""
echo "  3) git push → ApplicationSet 가 자동 reconcile (3 분 이내)"

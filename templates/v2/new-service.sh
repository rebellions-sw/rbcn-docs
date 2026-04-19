#!/usr/bin/env bash
# Golden Path v2 — 1 명령으로 신규 서비스 전체 부트스트랩.
#
# 차이점 from v1:
#   - gh repo create + push 자동
#   - type 별 (api / web / mfe / db / cache / worker) 템플릿
#   - reusable workflow 호출 (drift 0)
#   - service catalog 자동 등록 → ApplicationSet 이 자동 onboard
#
# 사용:
#   rbcn new <name> --type=api  --owner=platform [--lang=go|node|python] [--tier=T1]
#   rbcn new <name> --type=web  --owner=platform [--lang=node]
#   rbcn new <name> --type=mfe  --owner=platform   # micro-frontend remote
#   rbcn new <name> --type=db   --owner=platform
#   rbcn new <name> --type=cache --owner=platform
#
# 산출물 (type=api 기준, 13 개):
#   1. App repo  (rebellions-sw/<name>)
#       - main.go|index.ts|app.py + Dockerfile + Makefile
#       - .github/workflows/ci.yml         (reusable-build.yaml 호출)
#       - .pre-commit-config.yaml, commitlint.config.js, CODEOWNERS, ...
#   2. Manifests repo (rebellions-sw/<name>-manifests)
#       - base/ (deployment, service, ingress, cert, sm, pr, netpol)
#       - overlays/{dev,stage,prod}/kustomization.yaml
#       - .github/workflows/{promote.yml,validate.yml}
#       - branches dev, stage, prod
#   3. Service catalog entry (rbcn-docs/services-catalog/services.yaml)
#       → ApplicationSet 이 자동으로 Application 3개 생성
#   4. Vault secret skeleton (secret/services/<name>)
#   5. Service docs stub (rbcn-docs/services/<name>.md)

set -euo pipefail

# ─────────── parse args ───────────
NAME=""; TYPE="api"; LANG="go"; OWNER="platform"; TIER="T1"; ENVS="dev,stage,prod"; DRY_RUN="false"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --type=*)  TYPE="${1#*=}" ;;
    --lang=*)  LANG="${1#*=}" ;;
    --owner=*) OWNER="${1#*=}" ;;
    --tier=*)  TIER="${1#*=}" ;;
    --envs=*)  ENVS="${1#*=}" ;;
    --dry-run) DRY_RUN="true" ;;
    -h|--help)
      sed -n '3,30p' "$0"; exit 0 ;;
    --*) echo "unknown flag $1"; exit 1 ;;
    *)   NAME="$1" ;;
  esac
  shift
done

[ -z "$NAME" ] && { echo "usage: rbcn new <name> --type=api|web|mfe|db|cache --owner=team"; exit 1; }
[[ "$NAME" =~ ^[a-z][a-z0-9-]*$ ]] || { echo "name must be lowercase, digits, hyphen, start with letter"; exit 1; }

case "$TYPE" in api|web|mfe|db|cache|worker) ;; *) echo "type must be api|web|mfe|db|cache|worker"; exit 1;; esac

ORG="${ORG:-rebellions-sw}"
SVCDIR="${HOME}/svc/${NAME}"
MANDIR="${HOME}/svc/${NAME}-manifests"
DOCS="${RBCN_DOCS:-/opt/rbcn-docs}"
CATALOG="${DOCS}/services-catalog/services.yaml"

cyan() { printf "\033[36m%s\033[0m\n" "$*"; }
green() { printf "\033[32m%s\033[0m\n" "$*"; }
red() { printf "\033[31m%s\033[0m\n" "$*"; }

cyan "================================================================"
cyan " rbcn new — golden path v2"
cyan "  name=$NAME  type=$TYPE  lang=$LANG  owner=$OWNER  tier=$TIER  envs=$ENVS"
cyan "================================================================"
[ "$DRY_RUN" = "true" ] && red "DRY RUN — 파일만 만들고 push 안 함"

# ─────────── 0. Pre-checks ───────────
need=(git gh yq)
for c in "${need[@]}"; do command -v "$c" >/dev/null || { red "missing: $c"; exit 1; }; done
gh auth status >/dev/null 2>&1 || { red "gh not authenticated. run: gh auth login"; exit 1; }

# ─────────── DB / Cache 는 별도 처리 ───────────
if [ "$TYPE" = "db" ]; then
  cyan "[db] CloudNative-PG cluster manifest 생성 중..."
  mkdir -p "$MANDIR"
  cp "$DOCS/operators/cloudnative-pg/db-template.yaml" "$MANDIR/cluster.yaml"
  sed -i "s/my-db/${NAME}/g; s/my-svc/${NAME}/g; s/owner: platform/owner: ${OWNER}/" "$MANDIR/cluster.yaml"
  green "[OK] $MANDIR/cluster.yaml"
  green "다음: kubectl apply -f $MANDIR/cluster.yaml"
  green "또는: rbcn deploy $MANDIR/cluster.yaml"
  exit 0
fi

if [ "$TYPE" = "cache" ]; then
  cyan "[cache] Redis 설치 명령:"
  green "bash $DOCS/operators/redis/install.sh <env> <namespace> ${NAME}"
  green "또는: rbcn cache create ${NAME} --ns=<namespace>"
  exit 0
fi

# ─────────── 1. App skeleton ───────────
cyan "[1/9] App skeleton  →  $SVCDIR"
mkdir -p "$SVCDIR/.github/workflows" "$SVCDIR/.github/ISSUE_TEMPLATE"
rsync -a "${DOCS}/org-templates/base-app/" "$SVCDIR/" --exclude README-template.md

case "$LANG" in
  go)
    cat > "$SVCDIR/main.go" <<EOF
package main

import (
	"fmt"
	"log"
	"net/http"
	"os"
	"time"
)

func main() {
	mux := http.NewServeMux()
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		fmt.Fprintf(w, "${NAME} v0.1.0 (build: %s)", os.Getenv("BUILD_TAG"))
	})
	mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
		w.Write([]byte("ok"))
	})
	mux.HandleFunc("/metrics", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/plain")
		fmt.Fprintf(w, "# HELP ${NAME//-/_}_up 1 if up\n")
		fmt.Fprintf(w, "# TYPE ${NAME//-/_}_up gauge\n")
		fmt.Fprintf(w, "${NAME//-/_}_up 1\n")
	})
	srv := &http.Server{Addr: ":8080", Handler: mux, ReadHeaderTimeout: 10 * time.Second}
	log.Println("listening :8080")
	log.Fatal(srv.ListenAndServe())
}
EOF
    cat > "$SVCDIR/go.mod" <<EOF
module github.com/${ORG}/${NAME}

go 1.22
EOF
    cat > "$SVCDIR/Dockerfile" <<'EOF'
FROM golang:1.22-alpine AS build
WORKDIR /src
COPY go.mod ./
COPY *.go ./
RUN CGO_ENABLED=0 go build -o /out/app .

FROM gcr.io/distroless/static
COPY --from=build /out/app /app
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/app"]
EOF
    ;;
  node)
    cat > "$SVCDIR/index.ts" <<EOF
import express from 'express';
import client from 'prom-client';

const app = express();
const reg = new client.Registry();
client.collectDefaultMetrics({ register: reg });

app.get('/', (_, res) => res.send('${NAME} v0.1.0'));
app.get('/healthz', (_, res) => res.send('ok'));
app.get('/metrics', async (_, res) => res.type('text/plain').send(await reg.metrics()));

app.listen(8080, () => console.log('listening :8080'));
EOF
    cat > "$SVCDIR/package.json" <<EOF
{
  "name": "${NAME}",
  "version": "0.1.0",
  "main": "index.ts",
  "scripts": { "build": "tsc", "start": "node dist/index.js", "dev": "ts-node-dev index.ts" },
  "dependencies": { "express": "^4.19.2", "prom-client": "^15.1.3" },
  "devDependencies": { "typescript": "^5.5", "ts-node-dev": "^2.0", "@types/express": "^4.17", "@types/node": "^20" }
}
EOF
    cat > "$SVCDIR/tsconfig.json" <<EOF
{ "compilerOptions": { "target": "ES2022", "module": "commonjs", "outDir": "dist", "strict": true, "esModuleInterop": true } }
EOF
    cat > "$SVCDIR/Dockerfile" <<'EOF'
FROM node:20-alpine AS build
WORKDIR /app
COPY package.json ./
RUN npm install
COPY . .
RUN npm run build

FROM node:20-alpine
WORKDIR /app
COPY --from=build /app/dist ./dist
COPY --from=build /app/node_modules ./node_modules
USER node
EXPOSE 8080
CMD ["node", "dist/index.js"]
EOF
    ;;
  python)
    cat > "$SVCDIR/app.py" <<EOF
from fastapi import FastAPI
from prometheus_client import make_asgi_app

app = FastAPI(title="${NAME}")
app.mount("/metrics", make_asgi_app())

@app.get("/")
def root():
    return {"service": "${NAME}", "version": "0.1.0"}

@app.get("/healthz")
def healthz():
    return "ok"
EOF
    cat > "$SVCDIR/requirements.txt" <<EOF
fastapi==0.115.0
uvicorn[standard]==0.30.6
prometheus-client==0.20.0
EOF
    cat > "$SVCDIR/Dockerfile" <<'EOF'
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
USER 65532
EXPOSE 8080
CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8080"]
EOF
    ;;
esac

cat > "$SVCDIR/Makefile" <<EOF
.PHONY: dev build push test

IMG ?= harbor.rebellions.ai/library/${NAME}
TAG ?= dev-\$(shell git rev-parse --short HEAD 2>/dev/null || echo sandbox)

dev:
	docker build -t \$(IMG):dev .
	docker run --rm -p 8080:8080 \$(IMG):dev

build:
	docker build -t \$(IMG):\$(TAG) .

push:
	docker push \$(IMG):\$(TAG)

test:
	@echo "TODO: tests"
EOF

cat > "$SVCDIR/.github/workflows/ci.yml" <<EOF
name: ci
on:
  push:
    branches: [main, dev]
  pull_request:
jobs:
  build:
    uses: ${ORG}/.github/.github/workflows/reusable-build.yaml@main
    with:
      service: ${NAME}
      language: ${LANG}
    secrets: inherit
EOF

cat > "$SVCDIR/skaffold.yaml" <<EOF
apiVersion: skaffold/v4beta12
kind: Config
metadata: { name: ${NAME} }
build:
  artifacts:
    - image: harbor.rebellions.ai/library/${NAME}
      docker: { dockerfile: Dockerfile }
deploy:
  kustomize:
    paths: ["../${NAME}-manifests/overlays/dev"]
portForward:
  - resourceType: service
    resourceName: ${NAME}
    port: 80
    localPort: 8080
EOF

cp "$DOCS/org-templates/base-app/README-template.md" "$SVCDIR/README.md"
sed -i "s/<service-name>/${NAME}/g; s/<team>/${OWNER}/g" "$SVCDIR/README.md"

(cd "$SVCDIR" && git init -b main >/dev/null && git add -A >/dev/null && git -c user.name=rbcn -c user.email=rbcn@rebellions.ai commit -m "feat: bootstrap ${NAME}" >/dev/null)
green "[OK] $SVCDIR ready (init commit)"

# ─────────── 2. Manifests repo ───────────
cyan "[2/9] Manifests skeleton  →  $MANDIR"
mkdir -p "$MANDIR/base" "$MANDIR/overlays"/{dev,stage,prod} "$MANDIR/.github/workflows"

cat > "$MANDIR/base/deployment.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${NAME}
  labels: { app: ${NAME} }
spec:
  replicas: 2
  selector: { matchLabels: { app: ${NAME} } }
  template:
    metadata:
      labels: { app: ${NAME} }
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/port: "8080"
    spec:
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        runAsUser: 65532
        runAsGroup: 65532
        seccompProfile: { type: RuntimeDefault }
      containers:
        - name: app
          image: harbor.rebellions.ai/library/${NAME}:placeholder
          ports:
            - containerPort: 8080
              name: http
          env:
            - name: BUILD_TAG
              value: "placeholder"
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 500m
              memory: 256Mi
          readinessProbe:
            httpGet:
              path: /healthz
              port: 8080
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /healthz
              port: 8080
            periodSeconds: 30
          securityContext:
            allowPrivilegeEscalation: false
            readOnlyRootFilesystem: true
            capabilities:
              drop:
                - ALL
EOF

cat > "$MANDIR/base/service.yaml" <<EOF
apiVersion: v1
kind: Service
metadata: { name: ${NAME} }
spec:
  type: ClusterIP
  selector: { app: ${NAME} }
  ports: [{ port: 80, targetPort: http, name: http }]
EOF

cat > "$MANDIR/base/hpa.yaml" <<EOF
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata: { name: ${NAME} }
spec:
  scaleTargetRef: { apiVersion: apps/v1, kind: Deployment, name: ${NAME} }
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource: { name: cpu, target: { type: Utilization, averageUtilization: 70 } }
EOF

cat > "$MANDIR/base/pdb.yaml" <<EOF
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: { name: ${NAME} }
spec:
  minAvailable: 1
  selector: { matchLabels: { app: ${NAME} } }
EOF

cat > "$MANDIR/base/servicemonitor.yaml" <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata: { name: ${NAME} }
spec:
  selector: { matchLabels: { app: ${NAME} } }
  endpoints: [{ port: http, interval: 30s, path: /metrics }]
EOF

cat > "$MANDIR/base/prometheusrule.yaml" <<EOF
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata: { name: ${NAME} }
spec:
  groups:
    - name: ${NAME}
      rules:
        - alert: ${NAME//-/_}_HighErrorRate
          expr: sum(rate(${NAME//-/_}_http_requests_total{code=~"5.."}[5m])) / sum(rate(${NAME//-/_}_http_requests_total[5m])) > 0.05
          for: 10m
          labels: { severity: warning, owner: ${OWNER}, tier: ${TIER} }
          annotations: { summary: "${NAME} 5xx > 5% (10m)" }
        - alert: ${NAME//-/_}_HighLatency
          expr: histogram_quantile(0.99, sum(rate(${NAME//-/_}_http_request_duration_seconds_bucket[5m])) by (le)) > 1
          for: 10m
          labels: { severity: warning, owner: ${OWNER}, tier: ${TIER} }
        - alert: ${NAME//-/_}_PodCrashLoop
          expr: rate(kube_pod_container_status_restarts_total{namespace="${NAME}"}[10m]) > 0.1
          for: 10m
          labels: { severity: critical, owner: ${OWNER}, tier: ${TIER} }
EOF

cat > "$MANDIR/base/networkpolicy.yaml" <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: ${NAME}-allow-ingress }
spec:
  podSelector: { matchLabels: { app: ${NAME} } }
  policyTypes: [Ingress]
  ingress:
    - from:
        - namespaceSelector: { matchLabels: { kubernetes.io/metadata.name: ingress-nginx } }
        - namespaceSelector: { matchLabels: { kubernetes.io/metadata.name: monitoring } }
      ports: [{ port: 8080, protocol: TCP }]
EOF

cat > "$MANDIR/base/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - service.yaml
  - hpa.yaml
  - pdb.yaml
  - servicemonitor.yaml
  - prometheusrule.yaml
  - networkpolicy.yaml
commonLabels:
  app.kubernetes.io/name: ${NAME}
  app.kubernetes.io/managed-by: argocd
  owner: ${OWNER}
  tier: ${TIER}
EOF

# overlays
for env in dev stage prod; do
  case $env in
    dev)   HOST="${NAME}.dev.infra.rblnconnect.ai";   REPLICAS=1 ;;
    stage) HOST="${NAME}.stage.infra.rblnconnect.ai"; REPLICAS=2 ;;
    prod)  HOST="${NAME}.infra.rblnconnect.ai";       REPLICAS=3 ;;
  esac
  cat > "$MANDIR/overlays/${env}/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ${NAME}
resources:
  - ../../base
  - ingress.yaml
  - certificate.yaml
images:
  - name: harbor.rebellions.ai/library/${NAME}
    newTag: "0.1.0"
patches:
  - target: { kind: Deployment, name: ${NAME} }
    patch: |
      - op: replace
        path: /spec/replicas
        value: ${REPLICAS}
EOF

  cat > "$MANDIR/overlays/${env}/ingress.yaml" <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ${NAME}
  annotations:
    cert-manager.io/cluster-issuer: vault-internal
    nginx.ingress.kubernetes.io/proxy-body-size: 10m
spec:
  ingressClassName: nginx
  tls:
    - hosts: [${HOST}]
      secretName: ${NAME}-tls
  rules:
    - host: ${HOST}
      http:
        paths:
          - path: /
            pathType: Prefix
            backend: { service: { name: ${NAME}, port: { number: 80 } } }
EOF

  cat > "$MANDIR/overlays/${env}/certificate.yaml" <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata: { name: ${NAME}-tls }
spec:
  secretName: ${NAME}-tls
  dnsNames: [${HOST}]
  issuerRef:
    name: vault-internal
    kind: ClusterIssuer
  duration: 720h
  renewBefore: 240h
EOF
done

# manifests repo workflows
cat > "$MANDIR/.github/workflows/promote.yml" <<EOF
name: promote
on:
  workflow_dispatch:
    inputs:
      from: { type: choice, options: [dev, stage] }
      to:   { type: choice, options: [stage, prod] }
jobs:
  promote:
    uses: ${ORG}/.github/.github/workflows/reusable-promote.yaml@main
    with:
      from: \${{ inputs.from }}
      to:   \${{ inputs.to }}
    secrets: inherit
EOF

cat > "$MANDIR/.github/workflows/validate.yml" <<EOF
name: validate
on: [pull_request]
jobs:
  v:
    uses: ${ORG}/.github/.github/workflows/reusable-manifest-validate.yaml@main
EOF

cp "$DOCS/org-templates/base-app/.github/CODEOWNERS"            "$MANDIR/.github/CODEOWNERS"
cp "$DOCS/org-templates/base-app/.github/PULL_REQUEST_TEMPLATE.md" "$MANDIR/.github/PULL_REQUEST_TEMPLATE.md"

cat > "$MANDIR/README.md" <<EOF
# ${NAME}-manifests

Kustomize manifests for **${NAME}** (auto-deployed by ArgoCD via services-catalog).

## 구조

\`\`\`
base/         - 공통 (deployment, service, hpa, pdb, sm, pr, netpol)
overlays/dev    - dev 환경 (replicas=1, dev.infra.* host)
overlays/stage  - stage
overlays/prod   - prod
\`\`\`

## Promote

\`\`\`bash
gh workflow run promote.yml -f from=dev -f to=stage
\`\`\`

또는 운영자 CLI:

\`\`\`bash
rbcn promote ${NAME} dev stage
\`\`\`
EOF

(cd "$MANDIR" && git init -b dev >/dev/null && git add -A >/dev/null && git -c user.name=rbcn -c user.email=rbcn@rebellions.ai commit -m "feat: bootstrap ${NAME} manifests" >/dev/null)

# stage/prod branches
(cd "$MANDIR" && git branch stage && git branch prod) || true

green "[OK] $MANDIR ready (init commit + dev/stage/prod branches)"

# ─────────── 3. GitHub repos ───────────
if [ "$DRY_RUN" = "true" ]; then
  red "[3/9] DRY RUN — skip gh repo create + push"
else
  cyan "[3/9] gh repo create  →  ${ORG}/${NAME}"
  if gh repo view "${ORG}/${NAME}" >/dev/null 2>&1; then
    red "  exists, skip create"
  else
    (cd "$SVCDIR" && gh repo create "${ORG}/${NAME}" --private --source=. --remote=origin --push)
  fi
  cyan "[3/9] gh repo create  →  ${ORG}/${NAME}-manifests"
  if gh repo view "${ORG}/${NAME}-manifests" >/dev/null 2>&1; then
    red "  exists, skip create"
  else
    (cd "$MANDIR" && gh repo create "${ORG}/${NAME}-manifests" --private --source=. --remote=origin --push -b dev)
    (cd "$MANDIR" && git push origin stage prod) || true
  fi
fi

# ─────────── 4. Service catalog (auto-onboard via ApplicationSet) ───────────
cyan "[4/9] Catalog onboard  →  $CATALOG"
if [ "$DRY_RUN" = "true" ]; then
  red "  DRY RUN — skip catalog modification"
elif grep -qE "^  - name: ${NAME}$" "$CATALOG" 2>/dev/null; then
  red "  already in catalog"
else
  ENV_LIST="[$(echo "$ENVS" | sed 's/,/, /g')]"
  cat >> "$CATALOG" <<EOF

  - name: ${NAME}
    type: ${TYPE}
    owner: ${OWNER}
    tier: ${TIER}
    repo: https://github.com/${ORG}/${NAME}-manifests.git
    environments: ${ENV_LIST}
EOF
  green "  added"
fi

# ─────────── 5. Vault secret skeleton ───────────
cyan "[5/9] Vault secret  →  secret/services/${NAME}"
if command -v vault >/dev/null && vault token lookup >/dev/null 2>&1; then
  vault kv put "secret/services/${NAME}" \
    LOG_LEVEL=info \
    OWNER="$OWNER" >/dev/null 2>&1 && green "  ok" || red "  vault put failed (check VAULT_ADDR/TOKEN)"
else
  red "  skip (vault cli not authenticated)"
  echo "  manual: vault kv put secret/services/${NAME} LOG_LEVEL=info"
fi

# ─────────── 6. Service docs stub ───────────
cyan "[6/9] Docs stub  →  ${DOCS}/services/${NAME}.md"
cat > "${DOCS}/services/${NAME}.md" <<EOF
# ${NAME}

| 속성 | 값 |
|------|----|
| Type     | ${TYPE} |
| Owner    | @${ORG}/${OWNER} |
| Tier     | ${TIER} |
| Source   | https://github.com/${ORG}/${NAME} |
| Manifests| https://github.com/${ORG}/${NAME}-manifests |
| Endpoint | https://${NAME}.infra.rblnconnect.ai (prod) |
| Lang     | ${LANG} |

## Operations

\`\`\`bash
rbcn diag ${NAME}
rbcn logs ${NAME}
rbcn promote ${NAME} dev stage
rbcn rollback ${NAME}
\`\`\`

## Related

- [PLATFORM SOT](../PLATFORM.md)
- [Catalog](../services-catalog/services.yaml)
EOF
green "  ok"

# ─────────── 7. Summary ───────────
cyan "================================================================"
green "DONE — ${NAME} (${TYPE}) bootstrapped"
cyan "================================================================"
cat <<EOF

산출물:
  1. App repo       : ${SVCDIR}    (push 됨: $([ "$DRY_RUN" = "true" ] && echo NO || echo YES))
  2. Manifests repo : ${MANDIR}    (3 branch: dev/stage/prod)
  3. CI workflow    : reusable-build.yaml 호출 (조직 표준)
  4. Promote        : reusable-promote.yaml 호출
  5. ArgoCD App     : ApplicationSet 이 자동 생성 (60초 내)
  6. Vault secret   : secret/services/${NAME}
  7. Docs           : services/${NAME}.md

다음:
  - 코드 작업: cd ${SVCDIR}; vi main.go|index.ts|app.py
  - 로컬 dev:  cd ${SVCDIR}; skaffold dev
  - PR/merge → 자동 배포 (dev)
  - 승격:     rbcn promote ${NAME} dev stage
EOF

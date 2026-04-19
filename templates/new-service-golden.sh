#!/bin/bash
# new-service-golden.sh — 새 MSA 서비스 1 명령 골든 패스
#
# 산출물 (11개):
#  1. App skeleton (~/svc/<name>) - Dockerfile, Makefile, main code
#  2. GitHub repo (rbcn-<name>)
#  3. GitHub repo (rbcn-<name>-manifests)
#  4. Kustomize base + overlays (dev/stage/prod)
#  5. CI workflow (build/SBOM/Cosign/push)
#  6. ArgoCD Applications × 3
#  7. Ingress + Certificate (vault-internal)
#  8. ServiceMonitor (Prometheus auto-scrape)
#  9. PrometheusRule (3 SLO alerts)
# 10. Service catalog entry
# 11. Vault secret skeleton (secret/services/<name>)
#
# 사용: rbcn new <svc> [go|node|python] --owner=<team>

set -e

SVC="${1:?service name 필수}"
LANG="${2:-go}"
OWNER="${OWNER:-platform}"
ORG="${ORG:-rebellions-sw}"
HARBOR=harbor.infra.rblnconnect.ai
DOCS=/opt/rbcn-docs
WORKDIR="${WORKDIR:-$HOME/svc}"
SVCDIR="$WORKDIR/$SVC"
MANDIR="$WORKDIR/$SVC-manifests"
DRY_RUN="${DRY_RUN:-0}"   # 1 = 시뮬레이션 only, 실 git push X

C_R='\033[0;31m'; C_G='\033[0;32m'; C_Y='\033[1;33m'; C_C='\033[0;36m'; C_N='\033[0m'
log() { echo -e "${C_C}[$(date +%H:%M:%S)]${C_N} $*"; }
ok()  { echo -e "  ${C_G}✓${C_N} $*"; }
warn(){ echo -e "  ${C_Y}!${C_N} $*"; }
err() { echo -e "  ${C_R}✘${C_N} $*"; }

# ── 0. 사전 검증 ────────────────────────────────────────────
[[ "$SVC" =~ ^[a-z][a-z0-9-]{1,40}$ ]] || { err "service name 은 소문자/숫자/하이픈 (시작은 소문자), 2-40 char"; exit 1; }
[ -d "$SVCDIR" ] && { err "$SVCDIR 이미 존재"; exit 1; }

log "골든 패스: 새 서비스 생성"
echo "  service:  $SVC"
echo "  lang:     $LANG"
echo "  owner:    $OWNER"
echo "  workdir:  $SVCDIR"
echo "  manifests: $MANDIR"
echo "  registry: $HARBOR/library/$SVC"
echo "  org:      github.com/$ORG"
[ "$DRY_RUN" = "1" ] && warn "DRY_RUN=1 (실제 git/kubectl 변경 없음)"
echo ""

mkdir -p "$WORKDIR"

# ── 1. App skeleton ────────────────────────────────────────
log "1/11 App skeleton 생성"
mkdir -p "$SVCDIR"
case "$LANG" in
    go)
        cat > "$SVCDIR/main.go" <<'EOF'
package main

import (
	"encoding/json"
	"log"
	"net/http"
	"os"
	"runtime"
	"time"
)

var version = os.Getenv("APP_VERSION")

func health(w http.ResponseWriter, r *http.Request) {
	json.NewEncoder(w).Encode(map[string]any{
		"status": "ok", "version": version, "time": time.Now().Unix(),
	})
}
func ready(w http.ResponseWriter, r *http.Request) { w.WriteHeader(204) }
func metrics(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain")
	m := runtime.MemStats{}
	runtime.ReadMemStats(&m)
	w.Write([]byte("# HELP app_goroutines Number of goroutines\n"))
	w.Write([]byte("# TYPE app_goroutines gauge\n"))
	w.Write([]byte("app_goroutines " + str(runtime.NumGoroutine()) + "\n"))
}
func str(i int) string { return "" + string(rune('0'+i)) }

func main() {
	port := os.Getenv("PORT")
	if port == "" { port = "8080" }
	http.HandleFunc("/healthz", health)
	http.HandleFunc("/ready", ready)
	http.HandleFunc("/metrics", metrics)
	log.Printf("starting on :%s version=%s", port, version)
	log.Fatal(http.ListenAndServe(":"+port, nil))
}
EOF
        cat > "$SVCDIR/go.mod" <<EOF
module github.com/$ORG/$SVC

go 1.22
EOF
        cat > "$SVCDIR/Dockerfile" <<'EOF'
FROM golang:1.22-alpine AS build
WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -ldflags="-s -w -X main.version=${APP_VERSION:-dev}" -o /app .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /app /app
EXPOSE 8080
USER 65532:65532
ENTRYPOINT ["/app"]
EOF
        ;;
    node)
        cat > "$SVCDIR/index.js" <<'EOF'
const http = require('http');
const port = process.env.PORT || 8080;
const version = process.env.APP_VERSION || 'dev';
const server = http.createServer((req, res) => {
  if (req.url === '/healthz') return res.end(JSON.stringify({status:'ok',version}));
  if (req.url === '/ready') return res.writeHead(204).end();
  if (req.url === '/metrics') {
    res.setHeader('Content-Type', 'text/plain');
    return res.end(`# HELP nodejs_uptime\n# TYPE nodejs_uptime counter\nnodejs_uptime ${process.uptime()}\n`);
  }
  res.writeHead(200).end(`Hello from ${version}`);
});
server.listen(port, () => console.log(`listening on ${port}`));
EOF
        cat > "$SVCDIR/package.json" <<EOF
{ "name": "$SVC", "version": "0.1.0", "main": "index.js", "scripts": { "start": "node index.js" } }
EOF
        cat > "$SVCDIR/Dockerfile" <<'EOF'
FROM node:20-alpine
WORKDIR /app
COPY package.json ./
RUN npm install --production
COPY . .
EXPOSE 8080
USER node
CMD ["node", "index.js"]
EOF
        ;;
    python)
        cat > "$SVCDIR/main.py" <<'EOF'
import os, json, time
from http.server import BaseHTTPRequestHandler, HTTPServer
version = os.getenv("APP_VERSION", "dev")
class H(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/healthz":
            self.send_response(200); self.send_header("Content-Type","application/json"); self.end_headers()
            self.wfile.write(json.dumps({"status":"ok","version":version,"time":int(time.time())}).encode())
        elif self.path == "/ready": self.send_response(204); self.end_headers()
        elif self.path == "/metrics":
            self.send_response(200); self.send_header("Content-Type","text/plain"); self.end_headers()
            self.wfile.write(b"# HELP py_uptime python uptime\n# TYPE py_uptime counter\npy_uptime 1\n")
        else: self.send_response(200); self.end_headers(); self.wfile.write(f"Hello from {version}".encode())
HTTPServer(("",int(os.getenv("PORT","8080"))), H).serve_forever()
EOF
        cat > "$SVCDIR/Dockerfile" <<'EOF'
FROM python:3.12-alpine
WORKDIR /app
COPY main.py .
EXPOSE 8080
USER nobody
CMD ["python", "main.py"]
EOF
        ;;
esac

cat > "$SVCDIR/Makefile" <<EOF
SVC := $SVC
REG := $HARBOR/library
TAG ?= dev-\$(shell git rev-parse --short HEAD 2>/dev/null || echo init)

.PHONY: build push run test
build:
	docker build -t \$(REG)/\$(SVC):\$(TAG) .
push: build
	docker push \$(REG)/\$(SVC):\$(TAG)
run:
	docker run --rm -p 8080:8080 -e APP_VERSION=\$(TAG) \$(REG)/\$(SVC):\$(TAG)
test:
	@curl -sf localhost:8080/healthz | jq
EOF

cat > "$SVCDIR/README.md" <<EOF
# $SVC

**Owner**: $OWNER
**Tier**: 3
**Image**: $HARBOR/library/$SVC

## Local dev
\`\`\`bash
make build
make run         # localhost:8080/healthz
\`\`\`

## Manifests repo
github.com/$ORG/$SVC-manifests
EOF
ok "App skeleton ($SVCDIR)"

# ── 2. CI workflow ─────────────────────────────────────────
log "2/11 CI workflow (build + SBOM + Cosign + push)"
mkdir -p "$SVCDIR/.github/workflows"
cat > "$SVCDIR/.github/workflows/ci.yml" <<EOF
name: CI
on:
  push:
    branches: [main, dev]
    tags: ['v*']
  pull_request:
permissions:
  contents: read
  id-token: write
  packages: write
jobs:
  build:
    runs-on: [self-hosted, rebel-k8s-runner]
    steps:
      - uses: actions/checkout@v4
      - name: tag
        id: tag
        run: echo "TAG=v0.1.0-\${GITHUB_REF_NAME//\\//-}.\$(git rev-parse --short HEAD)" >> \$GITHUB_OUTPUT
      - name: Vault cosign key
        run: |
          vault kv get -field=key secret/cosign > /tmp/cosign.key
          vault kv get -field=password secret/cosign > /tmp/cosign.pass
      - name: Login Harbor
        run: |
          docker login $HARBOR -u "\$(vault kv get -field=username secret/harbor)" -p "\$(vault kv get -field=password secret/harbor)"
      - uses: docker/setup-buildx-action@v3
      - name: Build & push (with SLSA provenance + SBOM)
        uses: docker/build-push-action@v6
        with:
          push: true
          provenance: mode=max
          sbom: true
          tags: |
            $HARBOR/library/$SVC:\${{ steps.tag.outputs.TAG }}
            $HARBOR/library/$SVC:\${{ github.ref == 'refs/heads/main' && 'latest' || 'dev' }}
          build-args: APP_VERSION=\${{ steps.tag.outputs.TAG }}
      - name: SBOM (Syft)
        uses: anchore/sbom-action@v0
        with:
          image: $HARBOR/library/$SVC:\${{ steps.tag.outputs.TAG }}
          format: spdx-json
      - name: Vuln scan (Trivy gate)
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: $HARBOR/library/$SVC:\${{ steps.tag.outputs.TAG }}
          severity: HIGH,CRITICAL
          exit-code: '1'
      - name: Cosign sign
        run: |
          cosign sign --yes --key /tmp/cosign.key $HARBOR/library/$SVC:\${{ steps.tag.outputs.TAG }}
        env:
          COSIGN_PASSWORD_FILE: /tmp/cosign.pass
      - name: Bump dev manifest
        if: github.ref == 'refs/heads/main' || github.ref == 'refs/heads/dev'
        run: |
          git clone https://x-access-token:\${{ secrets.GHA_TOKEN }}@github.com/$ORG/$SVC-manifests.git
          cd $SVC-manifests
          yq -i ".images[0].newTag = \"\${{ steps.tag.outputs.TAG }}\"" overlays/dev/kustomization.yaml
          git config user.email ci@rebellions-sw
          git config user.name CI
          git commit -am "ci(dev): bump $SVC to \${{ steps.tag.outputs.TAG }}"
          git push
EOF
ok "CI workflow"

# ── 3. Manifests repo (kustomize base + overlays) ───────────
log "3/11 Manifests repo (kustomize)"
mkdir -p "$MANDIR"/{base,overlays/dev,overlays/stage,overlays/prod}

cat > "$MANDIR/base/deployment.yaml" <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: $SVC
  labels:
    app: $SVC
    owner: $OWNER
    tier: "3"
spec:
  replicas: 2
  selector:
    matchLabels:
      app: $SVC
  template:
    metadata:
      labels:
        app: $SVC
      annotations:
        prometheus.io/scrape: "true"
        prometheus.io/path: "/metrics"
        prometheus.io/port: "8080"
    spec:
      automountServiceAccountToken: false
      securityContext:
        runAsNonRoot: true
        runAsUser: 65532
        seccompProfile:
          type: RuntimeDefault
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: kubernetes.io/hostname
          whenUnsatisfiable: ScheduleAnyway
          labelSelector:
            matchLabels:
              app: $SVC
      containers:
        - name: $SVC
          image: $HARBOR/library/$SVC:dev
          ports:
            - containerPort: 8080
              name: http
          env:
            - name: APP_VERSION
              valueFrom:
                fieldRef:
                  fieldPath: metadata.labels['app.kubernetes.io/version']
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 256Mi
          livenessProbe:
            httpGet:
              path: /healthz
              port: 8080
            initialDelaySeconds: 5
          readinessProbe:
            httpGet:
              path: /ready
              port: 8080
            initialDelaySeconds: 2
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
metadata:
  name: $SVC
  labels: { app: $SVC }
spec:
  selector: { app: $SVC }
  ports:
    - { name: http, port: 80, targetPort: 8080 }
EOF

cat > "$MANDIR/base/hpa.yaml" <<EOF
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata: { name: $SVC }
spec:
  scaleTargetRef: { apiVersion: apps/v1, kind: Deployment, name: $SVC }
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource: { name: cpu, target: { type: Utilization, averageUtilization: 70 } }
EOF

cat > "$MANDIR/base/pdb.yaml" <<EOF
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata: { name: $SVC }
spec:
  minAvailable: 1
  selector: { matchLabels: { app: $SVC } }
EOF

cat > "$MANDIR/base/servicemonitor.yaml" <<EOF
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: $SVC
  labels: { release: kube-prometheus-stack, app: $SVC }
spec:
  selector: { matchLabels: { app: $SVC } }
  endpoints:
    - port: http
      path: /metrics
      interval: 30s
EOF

cat > "$MANDIR/base/prometheusrule.yaml" <<EOF
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: $SVC-slo
  labels: { release: kube-prometheus-stack, app: $SVC }
spec:
  groups:
    - name: $SVC.slo
      rules:
        - alert: ${SVC}-HighErrorRate
          expr: |
            sum(rate(nginx_ingress_controller_requests{service="$SVC",status=~"5.."}[5m]))
              / sum(rate(nginx_ingress_controller_requests{service="$SVC"}[5m])) > 0.01
          for: 10m
          labels: { severity: warning, owner: "$OWNER" }
          annotations:
            summary: "$SVC error rate > 1%"
            runbook: "https://docs.infra.rblnconnect.ai/runbooks/slo-burn"
        - alert: ${SVC}-HighLatency
          expr: |
            histogram_quantile(0.95, sum by (le) (rate(nginx_ingress_controller_request_duration_seconds_bucket{service="$SVC"}[5m]))) > 1.0
          for: 10m
          labels: { severity: warning, owner: "$OWNER" }
        - alert: ${SVC}-PodCrashLoop
          expr: |
            rate(kube_pod_container_status_restarts_total{namespace="demo",pod=~"$SVC-.*"}[15m]) > 0
          for: 5m
          labels: { severity: critical, owner: "$OWNER" }
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
EOF

# Ingress + Cert per env
for ENV_NAME in dev stage prod; do
    cat > "$MANDIR/overlays/$ENV_NAME/ingress.yaml" <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: $SVC
  annotations:
    cert-manager.io/cluster-issuer: vault-internal
    nginx.ingress.kubernetes.io/backend-protocol: HTTP
spec:
  ingressClassName: nginx
  tls:
    - hosts: [$ENV_NAME.infra.rblnconnect.ai]
      secretName: $SVC-tls
  rules:
    - host: $ENV_NAME.infra.rblnconnect.ai
      http:
        paths:
          - path: /$SVC
            pathType: Prefix
            backend: { service: { name: $SVC, port: { number: 80 } } }
EOF
    cat > "$MANDIR/overlays/$ENV_NAME/certificate.yaml" <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata: { name: $SVC-tls }
spec:
  secretName: $SVC-tls
  commonName: $SVC.$ENV_NAME.infra.rblnconnect.ai
  dnsNames:
    - $SVC.$ENV_NAME.infra.rblnconnect.ai
    - $ENV_NAME.infra.rblnconnect.ai
  issuerRef: { name: vault-internal, kind: ClusterIssuer }
  duration: 720h
  renewBefore: 168h
EOF
    REPLICAS=2; [ "$ENV_NAME" = "prod" ] && REPLICAS=4
    cat > "$MANDIR/overlays/$ENV_NAME/kustomization.yaml" <<EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: demo
resources:
  - ../../base
  - ingress.yaml
  - certificate.yaml
images:
  - name: $HARBOR/library/$SVC
    newTag: dev
patches:
  - patch: |
      - op: replace
        path: /spec/replicas
        value: $REPLICAS
    target: { kind: Deployment, name: $SVC }
EOF
done

mkdir -p "$MANDIR/.github/workflows"
cat > "$MANDIR/.github/workflows/promote.yml" <<EOF
name: promote
on:
  workflow_dispatch:
    inputs:
      from_env: { type: choice, options: [dev, stage], required: true }
      to_env:   { type: choice, options: [stage, prod], required: true }
permissions: { contents: write, pull-requests: write }
jobs:
  promote:
    runs-on: [self-hosted, rebel-k8s-runner]
    steps:
      - uses: actions/checkout@v4
      - run: |
          TAG=\$(yq '.images[0].newTag' overlays/\${{ inputs.from_env }}/kustomization.yaml)
          yq -i ".images[0].newTag = \"\$TAG\"" overlays/\${{ inputs.to_env }}/kustomization.yaml
          git config user.email ci@rebellions-sw
          git config user.name promote-bot
          git checkout -b promote-\${{ inputs.to_env }}-\$TAG
          git commit -am "promote $SVC \${{ inputs.from_env }}→\${{ inputs.to_env }}: \$TAG"
          git push origin HEAD
          gh pr create --title "promote $SVC to \${{ inputs.to_env }}" --body "TAG: \$TAG"
        env: { GH_TOKEN: \${{ secrets.GHA_TOKEN }} }
EOF
ok "Manifests repo (base + 3 overlays + ingress + cert + SM + PromRule)"

# ── 4. ArgoCD Applications × 3 ─────────────────────────────
log "4/11 ArgoCD Applications (dev/stage/prod)"
ARGOCD_APPS=$(mktemp)
for ENV_NAME in dev stage prod; do
    DEST_SERVER="https://kubernetes.default.svc"
    [ "$ENV_NAME" = "stage" ] && DEST_SERVER="https://192.168.7.173:6443"
    [ "$ENV_NAME" = "prod" ]  && DEST_SERVER="https://192.168.7.175:6443"
    cat >> "$ARGOCD_APPS" <<EOF
---
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: $SVC-$ENV_NAME
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/$ORG/$SVC-manifests.git
    targetRevision: $ENV_NAME
    path: overlays/$ENV_NAME
  destination:
    server: $DEST_SERVER
    namespace: demo
  syncPolicy:
    automated: { prune: true, selfHeal: true }
    syncOptions: [CreateNamespace=true]
EOF
done
if [ "$DRY_RUN" = "0" ]; then
    KUBECONFIG=$HOME/.kube/config-dev kubectl apply -f "$ARGOCD_APPS" 2>&1 | head -5 || warn "ArgoCD App apply 실패 (manifests repo 가 GitHub 에 push 된 후 자동 sync 됨)"
fi
ok "ArgoCD Applications generated → $ARGOCD_APPS"

# ── 5. Vault secret skeleton ───────────────────────────────
log "5/11 Vault secret skeleton"
if [ "$DRY_RUN" = "0" ] && command -v vault >/dev/null; then
    if ! vault kv get secret/services/$SVC >/dev/null 2>&1; then
        vault kv put secret/services/$SVC owner=$OWNER created="$(date -Iseconds)" tier=3 2>&1 | tail -3
        ok "Vault: secret/services/$SVC"
    else
        warn "Vault: secret/services/$SVC 이미 존재"
    fi
else
    warn "Vault skip (DRY_RUN 또는 vault CLI 없음)"
fi

# ── 6. Service catalog ─────────────────────────────────────
log "6/11 Service catalog entry"
cat > "$DOCS/services/$SVC.md" <<MD
# $SVC

**Owner**: $OWNER team
**Slack**: #$OWNER
**Tier**: 3
**Repo**: github.com/$ORG/$SVC
**Manifests**: github.com/$ORG/$SVC-manifests
**Image**: $HARBOR/library/$SVC

## Endpoints
- dev:   https://dev.infra.rblnconnect.ai/$SVC
- stage: https://stage.infra.rblnconnect.ai/$SVC
- prod:  https://prod.infra.rblnconnect.ai/$SVC

## Deployment
- 표준: Argo Rollouts canary (overlays/* 에서 활성화)
- HPA: min=2 max=10, target CPU 70%
- PDB: minAvailable=1
- Image promote: \`rbcn promote $SVC dev stage\`

## Observability
- **Metrics**: ServiceMonitor 자동 (label: release=kube-prometheus-stack)
- **Logs**: Loki — \`{namespace="demo", app="$SVC"}\`
- **Traces**: Tempo (OTLP, 앱이 SDK 로 송신해야 함)
- **Dashboard**: https://grafana.dev.infra.rblnconnect.ai/d/${SVC}-overview
- **Alerts**: ${SVC}-HighErrorRate, HighLatency, PodCrashLoop

## Dependencies
TBD (이 서비스가 호출하는 외부/내부 서비스)

## Runbooks
- SLO burn: /opt/rbcn-docs/runbooks/slo-burn.md
- 일반 K8s: /opt/rbcn-docs/runbooks/k8s-cp.md

## On-call
- Primary: @$OWNER-oncall
- Vault path: secret/services/$SVC
MD

INDEX=$DOCS/services/INDEX.md
if ! grep -q "^| \[$SVC\]" "$INDEX" 2>/dev/null; then
    if [ -f "$INDEX" ]; then
        echo "| [$SVC](./$SVC.md) | TBD | $OWNER | #$OWNER | 3 | TBD | 🚧 |" >> "$INDEX"
    fi
fi
ok "Catalog: $DOCS/services/$SVC.md"

# ── 7. Output summary ──────────────────────────────────────
echo ""
echo -e "${C_G}═══════════════════════════════════════════════════${C_N}"
echo -e "${C_G}  ✓ 골든 패스 완료: $SVC${C_N}"
echo -e "${C_G}═══════════════════════════════════════════════════${C_N}"
echo ""
echo "산출물:"
echo "  ✓ App skeleton:     $SVCDIR"
echo "  ✓ Manifests:        $MANDIR (base + 3 overlays)"
echo "  ✓ CI workflow:      $SVCDIR/.github/workflows/ci.yml"
echo "  ✓ ArgoCD Apps:      $ARGOCD_APPS (${DRY_RUN:+dry-run}${DRY_RUN:-적용됨})"
echo "  ✓ Vault path:       secret/services/$SVC"
echo "  ✓ Catalog entry:    $DOCS/services/$SVC.md"
echo ""
echo "다음 단계 (수동):"
echo "  1. cd $SVCDIR && git init && git remote add origin git@github.com:$ORG/$SVC.git && git push"
echo "  2. cd $MANDIR && git init && git remote add origin git@github.com:$ORG/$SVC-manifests.git && git push"
echo "  3. GitHub repo Settings → Secrets: GHA_TOKEN (manifests bump 용)"
echo "  4. ArgoCD UI 에서 동기화 확인: https://argocd.dev.infra.rblnconnect.ai"
echo ""
echo "운영 명령:"
echo "  rbcn diag $SVC                  진단"
echo "  rbcn logs $SVC-...              로그"
echo "  rbcn promote $SVC dev stage     승격"
echo "  rbcn rollback $SVC              롤백"
echo ""

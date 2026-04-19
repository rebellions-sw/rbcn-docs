# Developer Guide — 신규 서비스 1 페이지 (Single Source of Truth for Devs)

> **새 서비스 (DB / API / Web / Micro Frontend) 추가 = 1 명령**
>
> ```bash
> rbcn new <name> --type=<api|web|mfe|db|cache> --owner=<team>
> ```

---

## 0. 30 초 onboarding

```bash
# 1) GitHub 인증
gh auth login

# 2) Vault 인증
export VAULT_ADDR=https://vault.infra.rblnconnect.ai
vault login -method=oidc

# 3) kubeconfig (운영자가 발급)
export KUBECONFIG=~/.kube/config-dev

# 4) 동작 확인
rbcn status
```

---

## 1. 새 서비스 만들기 (타입별)

### API (Go / Node / Python)

```bash
rbcn new payments --type=api --lang=go --owner=billing
# 산출물:
#   ~/svc/payments               (앱 코드, Dockerfile, Makefile, CI workflow)
#   ~/svc/payments-manifests     (kustomize base + dev/stage/prod overlays)
#   github.com/rebellions-sw/payments               (push 됨)
#   github.com/rebellions-sw/payments-manifests     (push 됨)
#   services-catalog/services.yaml 에 entry 추가
#   ApplicationSet 이 60초 내 ArgoCD Application 3개 자동 생성
#   secret/services/payments (Vault) 골격
#   docs/services/payments.md
```

### Web (Next.js)

```bash
rbcn new dashboard --type=web --lang=node --owner=platform
# 동일 + Next.js standalone Dockerfile + ingress public
```

### Micro Frontend (Module Federation remote)

```bash
rbcn new billing-mfe --type=mfe --owner=billing
# 동일 + next.config.js 에 NextFederationPlugin 설정
# Host (demo-nextjs) 의 next.config.js 에 remote 등록 (수동 1회)
```

### DB (CloudNative-PG)

```bash
rbcn db create payments-db --ns=payments --instances=3
# /tmp/cnpg-payments-db.yaml 생성 → 검토 후 apply
kubectl apply -f /tmp/cnpg-payments-db.yaml

# 3분 후:
kubectl -n payments get cluster.postgresql.cnpg.io
# NAME            INSTANCES  READY  STATUS
# payments-db     3          3      Cluster in healthy state
```

### Cache (Redis HA)

```bash
rbcn cache create payments-cache --ns=payments
# Bitnami helm chart, master + 2 replica, persistent, ServiceMonitor 자동
```

---

## 2. 로컬 개발

### 가장 빠른 방법: Skaffold + kind

```bash
rbcn kind up                  # local cluster (1회)
cd ~/svc/payments
skaffold dev                  # code save → 자동 build → 자동 deploy
# 종료: Ctrl+C
```

### 멀티 서비스: Tilt

```bash
cd ~/dev
cp /opt/rbcn-docs/dev-loop/Tiltfile.example Tiltfile
# 편집
tilt up                       # http://localhost:10350 (UI)
```

### 가장 단순: Docker Compose

```bash
cd ~/svc/payments
docker compose up
```

---

## 3. CI/CD (자동)

### push → main / dev 브랜치

→ `rebellions-sw/.github/.github/workflows/reusable-build.yaml` 자동 실행:

1. Build (multi-arch 가능)
2. SBOM 생성 (Syft)
3. Trivy scan (HIGH/CRITICAL fail)
4. Cosign 서명
5. Harbor push
6. **`payments-manifests` 의 dev overlay tag 자동 bump** → ArgoCD 자동 sync

**개발자 작업: 0** (PR merge 만)

### 승격 (dev → stage → prod)

```bash
rbcn promote payments dev stage    # PR 자동 생성
# 검토 후 merge → ArgoCD 자동 sync
rbcn promote payments stage prod   # prod 도 동일
```

---

## 4. 시크릿 / 설정

### Vault 에 시크릿 추가

```bash
vault kv put secret/services/payments \
  STRIPE_KEY=sk_live_... \
  DB_PASSWORD="$(openssl rand -base64 32)"
```

### k8s Secret 자동 동기화 (ExternalSecret)

```yaml
# overlays/dev/externalsecret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata: { name: payments-secrets }
spec:
  refreshInterval: 1h
  secretStoreRef: { name: vault, kind: ClusterSecretStore }
  target: { name: payments-secrets }
  dataFrom: [{ extract: { key: services/payments } }]
```

---

## 5. 모니터링 / 로그 / 알림

### Prometheus (자동)

`base/servicemonitor.yaml` 가 자동 생성됩니다 (golden path).
Grafana 에서 `up{app="payments"}` 즉시 검색.

### Loki

```bash
rbcn logs payments-xxxxx           # 단순
# Grafana → Explore → Loki:
{namespace="payments", app="payments"} | json
```

### 알람

`base/prometheusrule.yaml` 에 3 SLO alert 자동 (5xx, latency, crash loop).
필요시 수정 후 PR.

---

## 6. 이슈 추적 / 협업

### 표준 (모든 repo)

- **Branch**: `main` (prod-ready), 작업은 `feat/`, `fix/`, `chore/` prefix
- **Commit**: Conventional commits (`feat:`, `fix:`, `chore:` ...) — pre-commit 훅이 강제
- **PR**: `.github/PULL_REQUEST_TEMPLATE.md` 자동 적용 (CODEOWNERS 자동 reviewer)
- **Pre-commit**: gitleaks, shellcheck, markdownlint (자동 설치: `pre-commit install`)
- **Issue**: `.github/ISSUE_TEMPLATE/bug.yaml` 사용

---

## 7. 운영자에게 요청 / 권한

### 본인이 할 수 있는 것 (개발자 그룹: `rbcn-dev`)

- 모든 namespace `read`
- 본인 service namespace `edit` (kubectl, Headlamp)
- ArgoCD: 본인 service `sync`
- Vault: `secret/services/<own>` `read/write`

### 운영자에게 요청

- 새 namespace 생성 (rbcn dev 가 자동으로 생기지 않으면)
- 외부 도메인 (`*.infra.rblnconnect.ai`) DNS
- T0 tier (incident pager 포함) 승격

---

## 8. 빠른 명령 모음 (rbcn)

```bash
# 신규
rbcn new <name> --type=api|web|mfe|db|cache --owner=team

# 상태/로그
rbcn status                     # 모든 환경 health
rbcn diag <pod-prefix>          # 한 서비스 종합 진단
rbcn logs <pod>                 # log tail
rbcn pf <svc> 8080              # port-forward

# 배포
rbcn promote <svc> dev stage    # PR 생성
rbcn rollback <svc>             # 즉시 이전 ReplicaSet

# 카탈로그
rbcn catalog                    # 등록된 서비스 목록
rbcn appset                     # ApplicationSet 상태

# 시크릿
rbcn secret get secret/services/<svc>
rbcn secret put secret/services/<svc> KEY=val

# 도움말
rbcn -h
```

---

## 9. 문제 해결

| 증상 | 첫 명령 | 그 다음 |
|------|---------|---------|
| Pod CrashLoop | `rbcn diag <name>`     | `rbcn logs`                       |
| ArgoCD OutOfSync | `rbcn sync <app>`     | `kubectl -n argocd describe app`  |
| Cert expired  | `rbcn cert ls --expiring` | `rbcn cert renew <name>`        |
| Promote 실패  | GitHub Actions log    | `rbcn rollback`                   |
| DB 느림       | `rbcn diag <db>`       | CNPG `kubectl cnpg status`       |
| 알 수 없음     | `rbcn problems`        | `rbcn runbook`                   |

---

## 10. 어디서 더 읽을지

- **Platform SOT**: [PLATFORM.md](./PLATFORM.md)
- **Catalog**: [services-catalog/services.yaml](./services-catalog/services.yaml)
- **DB**: [operators/cloudnative-pg/README.md](./operators/cloudnative-pg/README.md)
- **Cache**: [operators/redis/README.md](./operators/redis/README.md)
- **MFE**: [microfrontend/README.md](./microfrontend/README.md)
- **Dev Loop**: [dev-loop/README.md](./dev-loop/README.md)
- **Identity**: [identity/README.md](./identity/README.md)
- **DR**: [dr/dr-runbook/INDEX.md](./dr/dr-runbook/INDEX.md)

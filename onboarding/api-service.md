# 📘 API 서비스 만들기 (Step-by-Step)

> 대상: 신입 개발자.
> 소요시간: **30분** (첫 push 부터 dev 클러스터 배포 + 외부 호출 확인까지)
> 사전: [`ONBOARDING.md`](../ONBOARDING.md) §1 (Day-0 환경 준비) 완료
> 결과물: dev 클러스터에 살아있는 HTTP API + Harbor 이미지 + manifest repo + ArgoCD app 3개 (dev/stage/prod)

---

## 0. 시나리오

`payments` 라는 결제 백엔드 API 를 Go 로 만든다고 가정합니다. 다른 언어는 `--lang=node` 또는 `--lang=python` 으로 바꾸면 됩니다.

| 항목 | 값 |
|---|---|
| 서비스명 | `payments` |
| 언어 | `go` (또는 node, python) |
| 팀 | `billing` |
| 티어 | `T1` (장애 시 즉시 응답 필요) |
| 환경 | `dev`, `stage`, `prod` |

---

## 1. 부트스트랩 한 줄 (30초)

```bash
rbcn new payments --type=api --lang=go --owner=billing --tier=T1
```

이 명령이 실행하는 8단계:

| # | 작업 | 결과 |
|---|------|------|
| 1 | `gh repo create rebellions-sw/payments --private` | 앱 repo |
| 2 | `~/svc/payments/` 생성 + base-app skeleton rsync | Dockerfile, Makefile, .pre-commit, CODEOWNERS, SECURITY.md |
| 3 | `main.go + go.mod + Dockerfile` 생성 | "Hello, payments" + `/healthz` + `/metrics` |
| 4 | `.github/workflows/ci.yml` 생성 | `uses: rebellions-sw/.github/.github/workflows/reusable-build.yaml@main` |
| 5 | `gh repo create rebellions-sw/payments-manifests --private` | manifests repo |
| 6 | `~/svc/payments-manifests/base/...` 와 `overlays/{dev,stage,prod}/` push | k8s 매니페스트 |
| 7 | `services-catalog/services.yaml` 추가 + `regen.sh` | ApplicationSet 자동 onboard |
| 8 | Vault `secret/services/payments` skeleton + docs stub | 시크릿 자리 + 문서 |

콘솔 출력 예:

```
================================================================
 rbcn new — golden path v2
  name=payments  type=api  lang=go  owner=billing  tier=T1  envs=dev,stage,prod
================================================================
[1/9] App skeleton  →  /home/rbcn/svc/payments
[2/9] Lang stub (go)
[3/9] CI workflow (reusable-build.yaml)
[4/9] App repo create + push (rebellions-sw/payments)
[5/9] Manifests skeleton  →  /home/rbcn/svc/payments-manifests
[6/9] Manifests repo create + push (3 branches: dev, stage, prod)
[7/9] services-catalog 등록 → ApplicationSet 자동 onboard
[8/9] Vault secret/services/payments skeleton
[9/9] services/payments.md docs stub
================================================================
✔ DONE
  app repo:        https://github.com/rebellions-sw/payments
  manifests repo:  https://github.com/rebellions-sw/payments-manifests
  catalog entry:   /opt/rbcn-docs/services-catalog/services/payments-{dev,stage,prod}.yaml
  argocd apps:     payments-dev / payments-stage / payments-prod
================================================================
```

---

## 2. 첫 commit + push (5분)

```bash
cd ~/svc/payments
ls                                              # main.go, go.mod, Dockerfile, Makefile, .github/, README.md ...
cat main.go                                     # 자동 생성된 hello + /healthz + /metrics 확인
```

코드 수정 (예: `/charge` 엔드포인트 추가):

```bash
cat >> main.go <<'EOF'

func chargeHandler(w http.ResponseWriter, r *http.Request) {
    w.Header().Set("Content-Type","application/json")
    fmt.Fprint(w, `{"status":"accepted","amount":1000}`)
}
EOF

# main 함수의 핸들러 등록 라인 위에 추가
sed -i 's|mux.HandleFunc("/healthz"|mux.HandleFunc("/charge", chargeHandler)\n\tmux.HandleFunc("/healthz"|' main.go

git add main.go
git commit -m "feat: add /charge endpoint"
git push origin main
```

---

## 3. CI 동작 확인 (3~4분)

```bash
gh run list -R rebellions-sw/payments -L 3      # 가장 최근 run 확인
gh run watch -R rebellions-sw/payments          # 실시간으로 watch (Ctrl-C 로 빠져나옴)
```

CI 의 24 단계를 모두 GREEN 으로 통과해야 합니다.

| Job | Runner | 단계 |
|-----|--------|------|
| **build** | `[self-hosted, rbcn]` (VM, docker) | checkout → tag 계산 → buildx 확인/설치 → harbor login → buildx build+push → SBOM (syft) → upload artifact → trivy scan → cosign install → cosign sign |
| **bump-dev-manifest** | `[self-hosted, rebel-k8s-runner]` (ARC pod) | manifests checkout → yq 설치 → dev overlay tag bump → commit & push |

> 어디서 막혔다면 [`ONBOARDING.md`](../ONBOARDING.md) §9 FAQ Q5~Q9.

---

## 4. ArgoCD 가 dev 에 배포 확인 (2분)

```bash
rbcn apps | grep payments                       # payments-dev / payments-stage / payments-prod
rbcn sync payments-dev                          # 강제 sync (필요 시)

# 실제 pod 가 떴는지
eval $(rbcn ctx dev)
kubectl get pods -n payments -w
# NAME                        READY   STATUS    AGE
# payments-7d9b8f4c6c-vxqzn   1/1     Running   30s
```

엔드포인트 호출:

```bash
rbcn pf payments 8080                            # localhost:8080 ←→ svc:8080
# (다른 터미널)
curl http://localhost:8080/healthz               # → ok
curl http://localhost:8080/charge                # → {"status":"accepted","amount":1000}
```

🎉 **여기까지 보이면 첫 API 배포 완료**.

---

## 5. Ingress 로 외부 노출 (자동, 확인만)

`base/ingress.yaml` 가 자동 생성됨:

```bash
kubectl get ingress -n payments
# NAME       CLASS   HOSTS                                ADDRESS         PORTS
# payments   nginx   payments.dev.infra.rblnconnect.ai   <ingress-ip>    80, 443

curl https://payments.dev.infra.rblnconnect.ai/healthz
# → ok
```

> stage / prod 에서는 hostname 이 `payments.stage.infra.rblnconnect.ai` / `payments.infra.rblnconnect.ai`.

---

## 6. SLO + 메트릭 확인 (3분)

base/servicemonitor.yaml 도 자동. Prometheus 가 `/metrics` 를 자동 수집.

```bash
rbcn slo payments                               # SLO 대시보드 직접 링크
rbcn url grafana                                # Grafana → "Service Detail" → payments 검색
```

기본 대시보드 (RED method):
- Rate (req/s)
- Errors (5xx %)
- Duration (P50/P95/P99 latency)

---

## 7. stage / prod 로 promote (5분)

```bash
rbcn promote payments dev   stage               # PR 자동 생성
                                                # PR 머지 → ArgoCD 가 stage 배포
rbcn promote payments stage prod                # prod (보통 review 후 머지)
```

문제 시 즉시 롤백:

```bash
rbcn rollback payments                          # Argo Rollouts 의 직전 stable revision
```

---

## 8. 시크릿 / DB 연결 추가 (선택, 5분)

DB connection string 같은 시크릿:

```bash
rbcn secret put secret/services/payments \
    DB_URL='postgres://payments_user:hunter2@payments-db.payments:5432/main'
```

manifests repo 의 `base/externalsecret.yaml` (자동 생성됨) 가 30초 안에 K8s `Secret` 으로 동기화 → Pod 의 `envFrom.secretRef` 가 자동 수령 → reloader 가 pod 재시작.

> DB 자체를 만들려면 [`db-service.md`](./db-service.md).

---

## 9. 자동 생성된 파일들 (참고)

### 9.1 앱 repo (`rebellions-sw/payments`)

```
payments/
├── main.go                       (또는 index.ts / app.py)
├── go.mod                        (또는 package.json / pyproject.toml)
├── Dockerfile                    (multi-stage, distroless, USER 65532)
├── Makefile                      (build/test/lint/docker)
├── README.md
├── SECURITY.md                   (취약점 신고 정책)
├── .editorconfig
├── .markdownlint.json
├── .pre-commit-config.yaml       (hooks: yamllint, markdownlint, trivy fs)
├── commitlint.config.js          (Conventional Commits)
├── skaffold.yaml                 (rbcn dev 용)
└── .github/
    ├── CODEOWNERS                (@billing-team)
    ├── ISSUE_TEMPLATE/
    ├── workflows/
    │   └── ci.yml                (reusable-build.yaml @ main 호출)
    └── pull_request_template.md
```

### 9.2 manifests repo (`rebellions-sw/payments-manifests`)

```
payments-manifests/
├── base/
│   ├── deployment.yaml           (replicas=1, resources, probes)
│   ├── service.yaml              (ClusterIP, port 8080)
│   ├── ingress.yaml              (nginx-class, payments.<env>.infra.rblnconnect.ai)
│   ├── certificate.yaml          (cert-manager + Let's Encrypt)
│   ├── servicemonitor.yaml       (Prometheus scrape)
│   ├── peerauthentication.yaml   (Istio mTLS STRICT)
│   ├── networkpolicy.yaml        (deny-by-default + allow-istio)
│   ├── externalsecret.yaml       (Vault → K8s Secret)
│   └── kustomization.yaml
├── overlays/
│   ├── dev/    (replicas=1, hostname=*.dev.infra)
│   ├── stage/  (replicas=2, hostname=*.stage.infra)
│   └── prod/   (replicas=3, hostname=*.infra, anti-affinity, PDB)
└── .github/workflows/
    ├── promote.yml               (수동 promote helper)
    └── validate.yml              (PR 시 manifest validate)
```

### 9.3 services-catalog 항목 (`rbcn-docs/services-catalog/services/`)

```yaml
# payments-dev.yaml
name: payments
env: dev
branch: dev
cluster: https://kubernetes.default.svc
type: api
owner: billing
tier: T1
repo: https://github.com/rebellions-sw/payments-manifests.git
```

`payments-stage.yaml` / `payments-prod.yaml` 도 동일 구조.

ApplicationSet 이 이 파일을 읽어 ArgoCD `Application` 3개를 자동 생성.

---

## 10. 다음 가이드

- [`web-service.md`](./web-service.md) — Next.js web
- [`mfe-service.md`](./mfe-service.md) — Module Federation remote
- [`db-service.md`](./db-service.md) — CloudNative-PG
- [`cheatsheet.md`](./cheatsheet.md) — 1-page 인쇄용
- [`../ONBOARDING.md`](../ONBOARDING.md) — 전체 신입 가이드

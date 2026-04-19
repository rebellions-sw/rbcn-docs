# 🚀 신입 온보딩 가이드 — RBCN Platform

> **이 문서 하나만 따라 해도 첫 PR 까지 갑니다.**
> 대상: 처음 입사한 개발자/SRE. Kubernetes/GitOps 경험 없어도 OK.
> 소요시간: **첫 시작 ~ Day-1 첫 PR 까지 약 90분**, 환경 준비 포함.

---

## 0. 시작 전에 알아야 할 것 (3분)

우리 플랫폼은 다음 흐름으로 모든 것이 자동화되어 있습니다.

```
GitHub repo (코드 push)
   │
   ▼
GitHub Actions (self-hosted runner)
   │   1) docker buildx build → image
   │   2) syft SBOM
   │   3) trivy scan (CRITICAL/HIGH 차단)
   │   4) cosign sign
   │   5) Harbor push
   │   6) manifests repo 의 dev overlay tag bump
   ▼
ArgoCD (GitOps)
   │   manifest 변경 감지 → cluster 에 apply
   ▼
Kubernetes (dev → stage → prod)
   │   Argo Rollouts (canary), Istio (traffic), Prometheus (metric)
   ▼
사용자
```

**개발자가 직접 만지는 것은 단 두 가지**:
1. **앱 repo** (`rebellions-sw/<svc>`): 코드 + Dockerfile + ci.yml
2. **manifests repo** (`rebellions-sw/<svc>-manifests`): kustomize overlays/{dev,stage,prod}

나머지 모두 (`rbcn new` 한 줄로) 자동 생성됩니다.

> 그림으로 더 보고 싶다면: [`PLATFORM.md`](./PLATFORM.md) §1 (architecture)

---

## 1. Day-0: 환경 준비 (30분, 최초 1회)

### 1.1 사전 요청 (관리자에게 받기)

다음 4가지를 **입사 첫날 plat-team(`#platform-help`)에 요청** 합니다:

| 항목 | 받을 것 | 누구에게 |
|---|---|---|
| 1. SSH 접근 | bastion / workspace VM 의 IP + SSH key 등록 | 인프라 관리자 |
| 2. GitHub 조직 초대 | `rebellions-sw` org 의 본인 권한 (write 이상) | 조직 관리자 |
| 3. Keycloak 계정 | `https://keycloak.rebellions.ai` SSO 계정 | 인프라 관리자 |
| 4. Vault read 권한 | LDAP/Keycloak group `platform-dev` 추가 | 인프라 관리자 |

> ⚠️ 이 4 가지가 안 되면 아무것도 못합니다. **꼭 먼저 받으세요.**

### 1.2 워크스페이스 VM 접속

평상시 작업은 우리가 만들어 둔 **`workspace VM`** 에서 합니다 (kubectl/helm/vault/ansible/rbcn 가 모두 설치돼 있음).

```bash
# 본인 노트북 (macOS/Linux/WSL) 에서
ssh-add ~/.ssh/id_ed25519                       # 키 등록
ssh rbcn@<workspace-vm-ip>                      # workspace 접속
# 처음이라면 SSH host key 수락 'yes'
```

> bastion 을 거쳐야 한다면 `~/.ssh/config` 에 ProxyJump 설정. 자세한 건 [§9 Troubleshooting](#9-troubleshooting--faq).

### 1.3 GitHub CLI 인증 (workspace VM 안에서)

```bash
gh auth login                                   # GitHub.com / HTTPS / browser 선택
                                                #  → 8자리 코드를 브라우저에 입력
gh auth status                                  # ✓ Logged in to github.com  ← 보이면 성공
```

> **주의**: 받은 토큰의 scope 에는 `repo`, `admin:org`, `workflow` 가 있어야 합니다.

### 1.4 Kubernetes 접근 확인

```bash
ls ~/.kube/                                     # config-dev / config-stage / config-prod 가 있어야 함
                                                # 없으면 관리자에게 요청

# 방법 1) 환경변수로 cluster 전환
eval $(rbcn ctx dev)                            # KUBECONFIG=~/.kube/config-dev
kubectl get nodes                               # 노드 4~5개 보이면 OK

# 방법 2) rbcn CLI 만 사용
rbcn ctx dev
rbcn nodes
```

### 1.5 5분 sanity check (진짜 잘 되었는지)

```bash
rbcn status                                     # 클러스터 + 핵심 서비스 한번에 OK 표시
rbcn whoami                                     # 본인 계정 정보
rbcn svc                                        # 서비스 카탈로그 + URL
rbcn problems                                   # 현재 문제 (정상이면 비어있음)
```

다 잘 나오면 **Day-0 환경 준비 끝**. 점심 먹으러 가세요. 🍱

---

## 2. Day-1: 첫 서비스 만들기 (30분)

오늘 목표: **`my-first-svc` 라는 새 API 서비스를 만들어 dev 클러스터에 배포** 합니다.

### 2.1 한 줄로 부트스트랩

```bash
rbcn new my-first-svc --type=api --lang=go --owner=<본인팀이름> --tier=T2
```

이 한 줄이 자동으로 해 주는 일 (약 30초):

| # | 액션 | 결과 |
|---|------|------|
| 1 | `gh repo create rebellions-sw/my-first-svc` | 앱 repo 생성 (private) |
| 2 | `main.go + go.mod + Dockerfile + .pre-commit-config.yaml + Makefile` push | 표준 base-app skeleton |
| 3 | `.github/workflows/ci.yml` 생성 (reusable-build.yaml 호출) | CI 자동 연결 |
| 4 | `gh repo create rebellions-sw/my-first-svc-manifests` | manifests repo 생성 |
| 5 | `base/{deploy,svc,ingress,cert,sm,pr,netpol}.yaml + overlays/{dev,stage,prod}/kustomization.yaml` push | k8s 매니페스트 |
| 6 | `services-catalog/services.yaml` 에 1줄 추가 + `regen.sh` | ApplicationSet 자동 등록 |
| 7 | Vault `secret/services/my-first-svc` skeleton 생성 | 시크릿 자리 |
| 8 | `services/my-first-svc.md` docs stub 생성 | 카탈로그 docs |

> **dry run** 으로 미리 보고 싶다면: `rbcn new my-first-svc --type=api --dry-run`

### 2.2 첫 commit + push 로 CI 동작 확인

```bash
cd ~/svc/my-first-svc                           # 위 1번에서 만든 폴더
echo "// my first change" >> main.go
git add main.go
git commit -m "feat: add my first change"
git push origin main
```

이 push 가 정확히 다음을 발동시킵니다:

```
GitHub push
  → ci.yml workflow trigger
  → reusable-build.yaml @ rebellions-sw/.github
    → [build job @ rbcn VM]   docker buildx → SBOM → trivy → cosign → harbor push
    → [bump job   @ ARC pod]  manifests repo dev overlay 의 image tag 갱신 + commit
  → ArgoCD가 manifests dev 변경 감지 → dev 클러스터에 자동 배포
```

### 2.3 진행 상황 보기

```bash
# 1) GitHub Actions 진행 상황
gh run list -R rebellions-sw/my-first-svc -L 3
gh run watch -R rebellions-sw/my-first-svc      # 실시간 watch

# 2) Harbor 에 이미지가 올라갔나
rbcn url harbor                                 # Harbor URL → 브라우저 로그인
                                                # 또는: curl -u rbcn-bot:$(vault kv get -field=password secret/harbor/admin) \
                                                #         https://harbor.infra.rblnconnect.ai/api/v2.0/projects/library/repositories/my-first-svc/artifacts | jq

# 3) ArgoCD Application 상태
rbcn apps | grep my-first-svc                   # Sync/Health 컬럼이 Synced/Healthy 여야 OK
rbcn sync my-first-svc-dev                      # 강제 sync 가 필요하면

# 4) Kubernetes 에 실제 떴는지
eval $(rbcn ctx dev)
kubectl get pods -n my-first-svc -w             # Running 1/1 이 보일 때까지 watch
rbcn pf my-first-svc 8080                       # localhost:8080 → svc:8080 (port-forward)
curl http://localhost:8080/healthz              # → "ok"
```

🎉 **여기까지 보이면 첫 배포 완료**. 첫 PR 의 stack 은 자동으로 dev 환경에 살아있습니다.

### 2.4 첫 PR 까지 (10분)

```bash
git checkout -b feat/hello-endpoint
# main.go 의 / 핸들러를 적절히 수정
git commit -am "feat: add /hello endpoint"
gh pr create --fill                             # PR 자동 생성
```

PR 의 CI 가 GREEN 이면 머지 → main 으로 push 되고 위 §2.3 흐름이 자동 동작.

---

## 3. Day-2: stage / prod 로 promote 하기 (5분)

dev 환경에서 잘 도는 이미지를 stage 와 prod 로 올리려면:

```bash
rbcn promote my-first-svc dev stage             # stage overlay 의 image tag 갱신 + PR 자동 생성
                                                # PR 머지하면 ArgoCD가 stage 클러스터에 배포

# stage 검증 끝나면
rbcn promote my-first-svc stage prod            # prod 도 동일
```

> 프로덕션 promote 는 보통 review 받고 머지. 자세한 환경별 정책은 [`change-requests/POLICY.md`](./change-requests/POLICY.md).

문제가 생기면 즉시 롤백:

```bash
rbcn rollback my-first-svc                      # Argo Rollouts 의 직전 stable revision 으로
```

---

## 4. 서비스 종류별 부트스트랩 (선택)

### 4.1 API (Go / Node / Python)

가장 흔한 백엔드 마이크로서비스.

```bash
rbcn new payments        --type=api --lang=go     --owner=billing --tier=T1
rbcn new notifications   --type=api --lang=node   --owner=growth  --tier=T2
rbcn new recommender     --type=api --lang=python --owner=ml      --tier=T2
```

자세한 step-by-step: [`onboarding/api-service.md`](./onboarding/api-service.md)

### 4.2 Web (Next.js)

사용자가 보는 웹 서비스.

```bash
rbcn new portal --type=web --lang=node --owner=frontend --tier=T1
```

자세한 step-by-step: [`onboarding/web-service.md`](./onboarding/web-service.md)

### 4.3 Micro-frontend (MFE)

기존 web 에 붙는 동적 remote 모듈 (Module Federation).

```bash
rbcn new search-widget --type=mfe --owner=search
```

자세한 step-by-step: [`onboarding/mfe-service.md`](./onboarding/mfe-service.md)

### 4.4 Database (CloudNative-PG)

Postgres 클러스터 1개.

```bash
rbcn db create payments-db --ns=payments --instances=3
```

자세한 step-by-step: [`onboarding/db-service.md`](./onboarding/db-service.md)

### 4.5 Cache (Redis HA)

```bash
rbcn cache create payments-cache --ns=payments
```

자세한 step-by-step: [`onboarding/cache-service.md`](./onboarding/cache-service.md)

---

## 5. 시크릿 다루기 (10분)

DB password, 외부 API key 등을 코드에 넣지 마세요. **반드시 Vault** 사용.

### 5.1 시크릿 추가

```bash
# 본인 service 의 path 는 'secret/services/<svc>' (rbcn new 가 자동으로 만들어둠)
rbcn secret put secret/services/my-first-svc \
    DB_URL='postgres://user:pass@payments-db.payments:5432/main' \
    THIRD_PARTY_TOKEN='xxxxxxxx'

# 잘 들어갔는지
rbcn secret get secret/services/my-first-svc
```

### 5.2 K8s 에서 사용

만들어진 manifests repo 의 `base/externalsecret.yaml` (자동 생성됨) 가 Vault 의 `secret/services/<svc>` 를 자동으로 K8s `Secret` 으로 만들어 줍니다 (External Secrets Operator).

Pod 안에서는 평소대로 환경변수로 사용:

```yaml
# base/deployment.yaml 의 일부 (자동 생성됨)
envFrom:
  - secretRef:
      name: my-first-svc                # ESO 가 만들어 주는 Secret
```

### 5.3 시크릿 회전 (rotation)

```bash
rbcn secret put secret/services/my-first-svc DB_URL='새로운-값'
# ESO가 30초 안에 K8s Secret 갱신, 앱은 reloader annotation 으로 자동 재시작
```

> 90 일마다 회전이 권장됩니다. 자동 알림: [`runbooks/secret-rotation.md`](./runbooks/secret-rotation.md)

---

## 6. 디버깅 / 로그 / 메트릭 (실전 5분)

```bash
# 6.1) 어떤 pod 가 죽고 있나?
rbcn problems                                   # CrashLoop / Pending / ImagePull 모두 한 화면

# 6.2) 특정 서비스 종합 진단 (status + events + logs 한번에)
rbcn diag my-first-svc                          # ← 이거 한 줄이면 99% 원인 파악

# 6.3) 로그 tail
rbcn logs my-first-svc                          # 최근 pod 의 stdout 자동
rbcn logs my-first-svc-7d9c-xx -f               # 특정 pod follow

# 6.4) 컨테이너 안 들어가기
rbcn exec my-first-svc                          # sh 로 들어감

# 6.5) 임시 port-forward
rbcn pf my-first-svc 8080                       # localhost:8080 → svc:8080 (port=local:remote 도 가능, 예: 9090:8080)

# 6.6) 메트릭 / 대시보드
rbcn url grafana                                # Grafana 열기
rbcn slo my-first-svc                           # SLO 대시보드 직접 링크
```

웹 UI 접근:

| UI | 명령 | URL 패턴 |
|---|---|---|
| Grafana | `rbcn url grafana` | `https://grafana.dev.infra.rblnconnect.ai` |
| ArgoCD | `rbcn url argocd` | `https://argocd.infra.rblnconnect.ai` |
| Harbor | `rbcn url harbor` | `https://harbor.infra.rblnconnect.ai` |
| Vault | `rbcn url vault` | `https://vault.infra.rblnconnect.ai` |
| Keycloak | `rbcn url keycloak` | `https://keycloak.rebellions.ai` |
| Kiali | `rbcn url kiali` | `https://kiali.dev.infra.rblnconnect.ai` |

> 모두 SSO (Keycloak). 별도 비밀번호 없음.

---

## 7. 로컬 개발 (선택)

작은 변경은 push → CI 가 1~2분이라 충분하지만, 빠른 inner-loop 가 필요하면:

```bash
# kind (로컬 1-노드 k8s) 부트스트랩
rbcn kind up

# Skaffold dev (저장 시 자동 재배포)
cd ~/svc/my-first-svc
rbcn dev my-first-svc                           # skaffold dev

# 여러 서비스 동시 (Tilt)
rbcn dev all
```

자세한 가이드: [`dev-loop/README.md`](./dev-loop/README.md)

---

## 8. 자주 쓰는 명령 1-page (북마크)

```bash
# 환경
rbcn ctx dev|stage|prod          eval $(rbcn ctx dev)         rbcn whoami

# 신규 서비스
rbcn new <svc> --type=api|web|mfe|db|cache --owner=team [--lang=go|node|python] [--dry-run]
rbcn db create <name> --ns=<ns>
rbcn cache create <name> --ns=<ns>

# 배포
rbcn promote <svc> dev stage          rbcn promote <svc> stage prod
rbcn rollback <svc>                   rbcn sync <app>
rbcn apps                             rbcn appset

# 운영
rbcn status      rbcn problems        rbcn diag <svc>
rbcn pods [ns]   rbcn logs <pod>      rbcn exec <pod>
rbcn pf <svc> <port>                  rbcn restart <deploy>
rbcn events [ns] rbcn top             rbcn nodes

# 시크릿 / 인증서
rbcn secret get <path>   rbcn secret put <path> k=v   rbcn secret ls <path>
rbcn cert ls [--expiring]                              rbcn cert renew <name>

# 백업 / 복구
rbcn backup ls   rbcn backup now <ns>   rbcn restore <name>
rbcn etcd snapshots   rbcn etcd health

# 비용
rbcn cost   rbcn cost report   rbcn cost recommend [ns]

# 카탈로그 / 문서
rbcn svc        rbcn url <svc>        rbcn catalog
rbcn docs       rbcn runbook [topic]
```

---

## 9. Troubleshooting / FAQ

### Q1. `rbcn: command not found`
A. `workspace VM` 위에서만 동작합니다. 본인 노트북에서는 `ssh rbcn@<workspace-vm>` 먼저.

### Q2. `gh auth status` 가 not logged in
A. `gh auth login` 다시 실행. SSO enforcement 가 있으면 `gh auth refresh -h github.com -s admin:org`.

### Q3. `kubectl get nodes` 에서 `Unable to connect to the server`
A. `eval $(rbcn ctx dev)` 안 함. 또는 `~/.kube/config-dev` 가 비어있음 → 관리자에게 요청.

### Q4. `rbcn new` 에서 `gh: Resource not accessible by integration`
A. GitHub PAT 의 scope 부족. `gh auth refresh -s admin:org,repo,workflow`.

### Q5. CI 가 build job 에서 `unknown command: docker buildx`
A. `rbcn-ci-runner-01` VM 에 buildx plugin 자동 설치 단계가 작동했어야 합니다. 만약 fail 이면 [`cicd/e2e-verification-2026-04-19.md`](./cicd/e2e-verification-2026-04-19.md) §3.1 참고.

### Q6. CI build 는 OK 인데 ArgoCD 가 sync 안됨
A. cluster network 이슈 가능. [`postmortems/2026/2026-04-19-appset-controller-api-timeout.md`](./postmortems/2026/2026-04-19-appset-controller-api-timeout.md). 임시 우회: `rbcn sync <app>`.

### Q7. trivy 가 `CRITICAL` 로 자꾸 fail
A. base image 가 outdated. Dockerfile 의 `FROM golang:1.25-alpine` (또는 `node:22-alpine`) 으로 bump. 그래도 안되면 `inputs.severity_fail` override.

### Q8. Harbor push 가 `x509: certificate is valid for *.infra.rblnconnect.ai`
A. Hostname 잘못 사용. 반드시 `harbor.infra.rblnconnect.ai`. (NOT `harbor.rebellions.ai`).

### Q9. `MANIFESTS_PAT` 만료 (90일)
A. `rbcn secret sync-gh` 실행 (Vault 에 새 PAT 미리 넣어야 함). 자동 검증 (placeholder/길이) 통과해야 push 됩니다.

### Q10. Pod 가 ImagePullBackOff
A. Harbor pull secret 누락. namespace 에 `imagePullSecrets` 가 자동 부여되는지 확인 (Kyverno policy).

> 더 많은 문제는 [`runbooks/INDEX.md`](./runbooks/INDEX.md). 그래도 안 되면 `#platform-help` 채널.

---

## 10. 학습 경로 (1주 → 1달 → 3달)

| 시점 | 목표 | 추천 문서 |
|------|------|-----------|
| **Day 1** | rbcn CLI 익숙해지기, 첫 서비스 배포 | 이 문서 §1~§3 |
| **Week 1** | dev/stage/prod 흐름, 시크릿/로그/메트릭 | [`PLATFORM.md`](./PLATFORM.md) §2~§5 |
| **Week 2** | ArgoCD UI, Grafana 대시보드, Kiali 보기 | [`runbooks/INDEX.md`](./runbooks/INDEX.md) |
| **Month 1** | 본인 서비스의 SLO 정의, on-call 대응 | [`PLATFORM.md`](./PLATFORM.md) §7, [`runbooks/oncall.md`](./runbooks/oncall.md) |
| **Month 3** | post-mortem 작성, change-request, DR 훈련 | [`postmortems/TEMPLATE.md`](./postmortems/TEMPLATE.md), [`dr/INDEX.md`](./dr/INDEX.md) |

---

## 11. 다음 문서

- 📘 [`PLATFORM.md`](./PLATFORM.md) — 운영자 1-page SOT (모든 명령/경로/SLO)
- ⚙️ [`cicd/e2e-verification-2026-04-19.md`](./cicd/e2e-verification-2026-04-19.md) — CI/CD 파이프라인 E2E 증거
- 🛡️ [`runbooks/INDEX.md`](./runbooks/INDEX.md) — 모든 운영 runbook
- 🚨 [`postmortems/INDEX.md`](./postmortems/INDEX.md) — 과거 사고 분석
- 🆘 [`dr/INDEX.md`](./dr/INDEX.md) — 재해 복구
- 📑 [`onboarding/cheatsheet.md`](./onboarding/cheatsheet.md) — 1-page 인쇄용 cheat sheet

— Platform team, rbcn
*마지막 업데이트: 2026-04-19*

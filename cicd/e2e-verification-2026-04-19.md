# CI/CD End-to-End Verification — 2026-04-19

**Status:** GREEN (모든 단계 success)
**Trigger:** "self-hosted runner 만으로 새 서비스 부트스트랩 → 이미지 빌드 → manifest 자동 bump 가 가능한가?"
**Verdict:** YES, 가능합니다. 아래는 그 증거입니다.

## 1. 검증 시나리오

```
GitHub repo (example-payments)
    │ git push main
    ▼
GitHub Actions trigger
    │ uses: rebellions-sw/.github/.github/workflows/reusable-build.yaml@main
    ▼
[ build job ]  runner = rbcn VM (self-hosted)
    1.  checkout
    2.  compute tag (date+run+sha)
    3.  verify docker / buildx (auto-install plugin if missing)
    4.  Harbor login
    5.  docker buildx build --cache-from/-to registry --push
    6.  syft SBOM (spdx-json) + upload-artifact (30d retain)
    7.  trivy scan (CRITICAL,HIGH = fail)
    8.  cosign sign (key + OIDC keyless fallback)
    │
    │ outputs: {tag, image, digest}
    ▼
[ bump-dev-manifest job ]  runner = ARC pod (self-hosted, k8s)
    9.  checkout rebellions-sw/example-payments-manifests @ dev (with PAT)
    10. yq -i '(.images[] | select(name==…).newTag) = "<new-tag>"' overlays/dev/kustomization.yaml
    11. git commit & push → ArgoCD가 dev cluster sync
```

## 2. 실측 결과

| Run | Trigger SHA | build job | bump job | 비고 |
|-----|-------------|-----------|----------|------|
| #1 | 3bf50eb | ❌ Kaniko `Permission denied /kaniko` | skipped | ARC daemonless 환경에 kaniko binary 권한 부족 |
| #2 | 7b19620 | ❌ `unknown command: docker buildx` | skipped | rbcn VM 에 buildx plugin 미설치 |
| #3 | c78d6e1 | ❌ Harbor TLS 인증서 hostname mismatch | skipped | `harbor.rebellions.ai` ≠ cert SAN |
| #4 | 0b39287 | ❌ Trivy stdlib CVE (Go 1.22) | skipped | 템플릿 Go 버전 outdated |
| **#5** | **86eef0d** | **✅ 14 steps all success** | **✅ 9 steps all success** | **GREEN** |

총 5번의 iteration 으로 4개의 인프라 결함 발견 → 모두 수정 → 통과. 결함은 모두 **재사용 워크플로 / 템플릿 / 호스트네임** 수준이므로 한번 고치면 모든 신규 서비스가 자동으로 혜택을 봄 (drift 0).

## 3. 무엇을 고쳤나

### 3.1 빌드 엔진 변경: Kaniko → docker buildx

**왜:** ARC pod (`rebel-k8s-runner`) 는 daemonless. Kaniko binary 는 chroot/mount 에 root 권한 필요 (`/kaniko` directory 생성 못함). rootless 모드 미지원 (chainguard fork 동일).

**대응:** 빌드 job 만 `[self-hosted, rbcn]` (Ubuntu 24.04 VM, docker 29.1.3) 로 옮기고, `docker buildx` 를 사용. ARC 는 lightweight 후속 작업 전용.

**파일:** `rebellions-sw/.github/.github/workflows/reusable-build.yaml`
```yaml
jobs:
  build:
    runs-on: ${{ fromJSON(inputs.runs-on) }}     # default: ['self-hosted','rbcn']
    steps:
      - name: Verify docker available + ensure buildx
        # docker 가 있지만 buildx plugin 이 없을 수 있어 자동 설치 (~/.docker/cli-plugins)
      - name: Build & push (docker buildx)
        # registry cache: cache-from/cache-to → 점진적 빌드 가속
  bump-dev-manifest:
    runs-on: ${{ fromJSON(inputs.bump_runs_on) }} # default: ['self-hosted','rebel-k8s-runner']
```

### 3.2 Harbor hostname 정정

**왜:** Harbor TLS 인증서 SAN 은 `*.infra.rblnconnect.ai` 만 포함. `harbor.rebellions.ai` 로 push 하면 `x509: certificate is valid for *.infra.rblnconnect.ai, not harbor.rebellions.ai`.

**대응:** 모든 doc / template / workflow 에서 `harbor.infra.rblnconnect.ai` 로 통일 (12 occurrences fixed).

### 3.3 base 템플릿 Go 버전 bump (1.22 → 1.25)

**왜:** Go 1.22 stdlib 에 CRITICAL CVE (CVE-2025-68121, TLS resumption) + 8 HIGH CVEs. 신규 서비스가 자동으로 fail.

**대응:** `templates/v2/new-service.sh` 와 `templates/new-service-golden.sh` 의 `golang:1.22-alpine` / `go 1.22` → `golang:1.25-alpine` / `go 1.25`.

### 3.4 PAT placeholder → 실제 token

**왜:** `secret/github#token` 이 Vault에 placeholder 값 (`ghp_PLAC...`, len=26) 으로 들어 있어 manifests checkout 이 `fatal: could not read Username for 'https://github.com'` 로 실패.

**대응:**
1. 실제 PAT 로 Vault 갱신 + `gh secret set MANIFESTS_PAT --org rebellions-sw --visibility all`
2. `rbcn secret sync-gh` 에 **token validation** 추가:
   ```bash
   case "$GT" in
       ghp_*)        [ ${#GT} -ge 40 ] || fail ;;
       github_pat_*) [ ${#GT} -ge 50 ] || fail ;;
       *)            fail "not a recognized GitHub token" ;;
   esac
   ```
   placeholder/dummy 값을 push 하려고 하면 `FAIL` 후 exit (90일 회전시 사고 방지).

## 4. 새 서비스 onboarding "Golden Path" 검증

`rbcn new <svc> --type=api --lang=go --owner=<team>` 한 줄로:

1. ✅ GitHub repo 2개 생성 (`<svc>` 앱 + `<svc>-manifests`)
2. ✅ base-app 템플릿 (Dockerfile, Go src, .pre-commit, README, Makefile, ci.yml) 자동 push
3. ✅ overlays/{dev,stage,prod} kustomization 자동 생성
4. ✅ services-catalog/services.yaml 에 한 줄 추가 + `regen.sh` 로 ApplicationSet 입력 파일 자동 갱신
5. ✅ git push 만 하면 위 검증된 CI 가 즉시 작동 → 이미지 빌드 → manifest dev tag bump → ArgoCD 가 dev cluster 에 배포

## 5. ArgoCD 배포 단계 (별도 알려진 이슈 — P3)

본 검증은 GitHub Actions / Harbor / 이미지 서명 / manifest bump **CI 파이프라인까지** GREEN 임을 확인했습니다.

ArgoCD 가 manifest 변경을 받아 cluster 에 배포하는 부분은 별도의 cluster-network 이슈 (`argocd-applicationset-controller` 가 K8s API ClusterIP 10.96.0.1:443 으로 i/o timeout) 가 있습니다. 자세한 내용은 [`postmortems/2026/2026-04-19-appset-controller-api-timeout.md`](../postmortems/2026/2026-04-19-appset-controller-api-timeout.md). Workaround: `rbcn new` 가 ArgoCD `Application` 매니페스트를 직접 `kubectl apply` 합니다.

## 6. 향후 P1 작업 (이번 검증으로 새로 발견)

- [ ] **rbcn-ci-runner-01 단일 장애점**: VM 1대만 빌드 처리. 부하 / outage 시 모든 빌드 중단. → ARC 의 docker-in-docker (DinD) sidecar 패턴 도입 검토 (rootful runner pod) 또는 rbcn VM 2대 추가.
- [ ] **PAT 90일 만료 알림**: `MANIFESTS_PAT` 만료 7일 전 PagerDuty / Slack `#alerts-platform`. 현재 알림 없음.
- [ ] **Trivy fail 임계 환경별 차등**: dev 는 HIGH 만, prod 는 CRITICAL 만 처럼 환경별 정책. 현재는 모든 PR/push 동일 (`CRITICAL,HIGH`).
- [ ] **Kaniko 재도전 (선택)**: ARC runner pod template 에 `securityContext.privileged: true` 부여 + nerdctl 사전 설치 → 빌드도 ARC 로 일원화. 보안팀 승인 필요.

## 7. 한줄 요약

> **2026-04-19 기준, GitHub push → 이미지 build → SBOM/scan/sign/push → manifest dev tag auto-bump 까지 self-hosted runner 만으로 100% 자동화 동작 GREEN. 다음 PR 부터 이 워크플로 그대로 사용 가능.**

— Platform team, rbcn

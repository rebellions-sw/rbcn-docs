# 🔧 Troubleshooting (실전 case-study)

> 대상: 신입 ~ 경험자 모두.
> "이 증상 보면 → 이 명령 → 99% 원인 파악" 의 흐름으로 정리.
> 모든 명령은 `workspace VM` 위에서 (`ssh rbcn@<workspace-vm-ip>`).
>
> **표기 규칙**: 코드블록의 `<...>` 는 placeholder. 그대로 복붙하면 깨집니다.
> 예: `<svc>` → `payments`, `<ns>` → `payments`, `<pod>` → 실제 pod 이름.
> 명령을 길게 따라하기 전에 위에 변수 정의해두면 편합니다:
>
> ```bash
> SVC=payments; NS=payments; POD=$(kubectl get pod -n $NS -l app=$SVC -o name | head -1)
> ```

---

## 0. 1순위: 만능 진단

```bash
SVC=payments              # 본인 서비스 이름

rbcn diag $SVC            # status + events + logs + 최근 deploy + ingress + pvc 한번에
rbcn problems             # 모든 cluster 의 모든 namespace 의 비정상 pod
```

이 두 줄이 80% 의 문제 답을 줍니다.

---

## 1. CI / 빌드 문제

### 1.1 `unknown command: docker buildx`

**증상**: build job 의 "Verify docker available" 에서 `docker: unknown command: docker buildx`

**원인**: `rbcn-ci-runner-01` 에 buildx plugin 미설치. 자동 설치 step 이 작동했어야 하는데 fail.

**조치**:
```bash
# runner 에 ssh (관리자 권한)
ssh rbcn@rbcn-ci-runner-01
mkdir -p ~/.docker/cli-plugins
curl -sSfL https://github.com/docker/buildx/releases/download/v0.17.1/buildx-v0.17.1.linux-amd64 \
  -o ~/.docker/cli-plugins/docker-buildx
chmod +x ~/.docker/cli-plugins/docker-buildx
docker buildx version  # 확인
```

→ 해결되면 [`cicd/e2e-verification-2026-04-19.md`](../cicd/e2e-verification-2026-04-19.md) 의 reusable-build.yaml step 이 next run 부터 자동으로 동일하게 처리.

### 1.2 `x509: certificate is valid for *.infra.rblnconnect.ai, not harbor.rebellions.ai`

**원인**: Harbor hostname 잘못 사용.

**조치**: `harbor.infra.rblnconnect.ai` 로 모든 곳 (Dockerfile, manifests, docs) 통일.

```bash
# 잔존 검색
grep -rln "harbor.rebellions.ai" .

# 일괄 치환 (위에서 나온 파일들 중 안전한 것만; 본인 repo root 에서)
grep -rl "harbor.rebellions.ai" --include="*.yaml" --include="Dockerfile" --include="*.md" . \
  | xargs sed -i 's|harbor.rebellions.ai|harbor.infra.rblnconnect.ai|g'
```

### 1.3 `Trivy CRITICAL` 로 fail

**증상**:
```
Total: 9 (HIGH: 8, CRITICAL: 1)
│ stdlib  │ CVE-2025-68121 │ CRITICAL │ fixed  │ v1.22.12 │ 1.24.13, ...
```

**원인**: base image 가 outdated.

**조치 (가장 흔한 케이스)**:
- Go: `Dockerfile` 의 `FROM golang:1.22-alpine` → `FROM golang:1.25-alpine` 그리고 `go.mod` 의 `go 1.22` → `go 1.25`
- Node: `node:18-alpine` → `node:22-alpine`
- Python: `python:3.11-slim` → `python:3.13-slim`

base image bump 만으로 99% CVE 가 해결됩니다.

### 1.4 `MANIFESTS_PAT` checkout 실패

**증상**: bump-dev-manifest job 의 `Checkout manifests` 에서:
```
fatal: could not read Username for 'https://github.com': terminal prompts disabled
```

**원인**: `MANIFESTS_PAT` org secret 이 placeholder/만료.

**조치**: 자세한 절차는 [`runbooks/secret-rotation.md`](../runbooks/secret-rotation.md) §1.

요약:
```bash
# 1) GitHub > Settings > Developer settings > PAT classic 에서 새 PAT 발급
# 2) Vault 갱신 (NEW_PAT 변수에 paste 후 echo 안 보이게)
read -s -p "Paste new PAT: " NEW_PAT; echo
EXISTING_WEBHOOK=$(vault kv get -field=webhook_secret secret/github)
vault kv put secret/github token="$NEW_PAT" username=rbcn-bot webhook_secret="$EXISTING_WEBHOOK"
unset NEW_PAT
# 3) GitHub org secret sync (validation 자동)
rbcn secret sync-gh
```

→ 다음 build 부터 자동 작동.

### 1.5 CI 가 queued 상태로 안 움직임

**원인**: self-hosted runner 가 모두 busy 거나 offline.

**조치**:
```bash
gh api orgs/rebellions-sw/actions/runners | jq '.runners[] | {name, status, busy, labels:[.labels[].name]}'
# status=offline 인 것 확인 → 해당 호스트 점검 (rbcn-ci-runner-01 이면 ssh 후 systemctl status actions.runner.*)
```

ARC pod 는 자동으로 새로 뜨므로 보통 1분 이내 회복.

---

## 2. ArgoCD 배포 문제

### 2.1 Application 이 sync 안됨

**증상**: `rbcn apps` 에서 sync=`?` 또는 `OutOfSync` 가 오래 유지.

**1차 조치**:
```bash
rbcn sync <app>                  # 강제 sync
```

**2차 진단**:
```bash
kubectl describe application <app> -n argocd | grep -A 20 "Conditions:"
```

흔한 원인:
| Condition | 의미 | 조치 |
|---|---|---|
| `RepoNotFound` | manifests repo 접근 불가 | repo-creds Secret (`github-rebellions-sw-creds`) 의 PAT 갱신 |
| `ComparisonError` | YAML invalid | manifest validate workflow 로그 |
| `OrphanedResource` | 외부에서 수동 변경 | UI 에서 sync prune |
| `controller can't list resources` | controller pod ↔ K8s API 통신 실패 | [post-mortem](../postmortems/2026/2026-04-19-appset-controller-api-timeout.md) |

### 2.2 ApplicationSet 가 application 안 만듦

[`postmortems/2026/2026-04-19-appset-controller-api-timeout.md`](../postmortems/2026/2026-04-19-appset-controller-api-timeout.md) 참고. **임시 우회**: `rbcn new` 가 `kubectl apply -f` 로 직접 Application 을 만들고 있음.

### 2.3 Application 은 Synced 인데 Pod 가 Pending

```bash
kubectl get pods -n <ns>
kubectl describe pod <pending-pod> -n <ns> | tail -20
```

| Event | 의미 | 조치 |
|---|---|---|
| `0/4 nodes available: insufficient cpu/memory` | resource 부족 | `kubectl get nodes -o wide` + `rbcn cost recommend <ns>` |
| `node(s) had taint {...}` | toleration 누락 | deployment.spec.tolerations 추가 |
| `0/4 nodes available: node(s) didn't match Pod's node affinity` | nodeSelector mismatch | label 확인 |
| `pod has unbound immediate PersistentVolumeClaims` | PVC 가 storage class 부족 | `kubectl get sc` + `kubectl get pvc -n <ns>` |

---

## 3. Pod 자체 문제

### 3.1 `CrashLoopBackOff`

```bash
rbcn diag <svc>                                  # 전체 진단
kubectl logs -n <ns> <pod> --previous            # 직전 crash 의 stdout
kubectl describe pod -n <ns> <pod> | grep -A 5 "Last State:"
```

흔한 원인:
| 종료 코드 | 의미 |
|---|---|
| `0` | 정상 종료 (entrypoint 가 즉시 끝남) → Dockerfile CMD 확인 |
| `1` | 일반 에러 → 앱 stdout 확인 |
| `137` | SIGKILL (보통 OOM) → resources.limits.memory 증가 |
| `139` | SIGSEGV (segfault) → 코드 버그 또는 base image mismatch (alpine vs glibc) |
| `143` | SIGTERM (graceful) → `terminationGracePeriodSeconds` 증가 |

### 3.2 `ImagePullBackOff`

```bash
kubectl describe pod -n <ns> <pod> | grep -A 3 "Events:"
# Failed to pull image: rpc error: ... unauthorized
```

원인: namespace 에 Harbor pull secret 미부여.

조치:
```bash
# Kyverno policy 가 자동 부여하는데, 새 ns 에 안 들어왔다면:
kubectl create secret -n <ns> docker-registry harbor-pull \
  --docker-server=harbor.infra.rblnconnect.ai \
  --docker-username="$(vault kv get -field=username secret/harbor/admin)" \
  --docker-password="$(vault kv get -field=password secret/harbor/admin)"
kubectl patch sa default -n <ns> -p '{"imagePullSecrets":[{"name":"harbor-pull"}]}'
```

### 3.3 Liveness/Readiness probe 계속 fail

```bash
kubectl describe pod -n <ns> <pod> | grep -A 1 "Liveness:\|Readiness:"
# 보통 임계 (initialDelaySeconds, periodSeconds, timeoutSeconds, failureThreshold)
```

조치:
- 앱이 천천히 뜬다면 `initialDelaySeconds: 30` 정도로 늘리고
- `/healthz` endpoint 가 진짜 응답하는지 `kubectl exec` 후 `wget -qO- http://localhost:<port>/healthz`

### 3.4 OOMKilled

```bash
kubectl get pods -n <ns> -o json | jq '.items[] | {name:.metadata.name, lastState:.status.containerStatuses[0].lastState}'
# {"reason":"OOMKilled", "exitCode":137 ...}
```

조치:
1. 즉시: `resources.limits.memory` 2배 늘림
2. 근본: `rbcn cost recommend <ns>` → Goldilocks 권장값 적용
3. 메모리 누수 의심 시: `kubectl exec` 후 `pprof` (Go) / `node --inspect` 등

---

## 4. 네트워크 문제

### 4.1 Pod 간 통신 안됨

```bash
# 1) NetworkPolicy 가 막는지
kubectl get networkpolicy -A
kubectl describe networkpolicy -n <ns>

# 2) Istio 가 막는지 (PeerAuthentication, AuthorizationPolicy)
kubectl get peerauthentication,authorizationpolicy -n <ns>

# 3) 실제 연결 시도 (debug pod)
kubectl run -it --rm netshoot --image=nicolaka/netshoot -- bash
> curl -v http://payments.payments.svc.cluster.local:8080/healthz
> nslookup payments.payments.svc.cluster.local
```

### 4.2 Ingress 503 / 502

```bash
# 1) ingress 가 backend 를 찾는가
kubectl describe ingress -n <ns>
# Address: <ip>, Backends: <pod-ip>:8080 ← 비어있으면 service 의 selector 가 pod label 와 mismatch

# 2) ingress-nginx pod 로그
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx -f

# 3) cert-manager 인증서 ready?
kubectl get certificate -n <ns>
# READY=True 가 아니면 → kubectl describe certificate ... 의 events
```

### 4.3 외부 도메인 → ingress IP 해석 안됨

```bash
dig payments.dev.infra.rblnconnect.ai +short
# 응답이 없거나 잘못된 IP → 사내 DNS (PowerDNS) 설정 확인
rbcn url netbox  # IP / DNS 정보
```

---

## 5. 시크릿 / 인증서 문제

### 5.1 ExternalSecret 이 Secret 안 만듦

```bash
kubectl get externalsecret -n <ns>
# STATUS=SecretSyncedError 인 경우
kubectl describe externalsecret <name> -n <ns> | tail -20
```

흔한 원인:
| Reason | 의미 |
|---|---|
| `path not found` | Vault path 오타 → `rbcn secret ls secret/services/` |
| `permission denied` | Vault policy 부족 → 운영자에게 요청 |
| `vault sealed` | Vault unseal 필요 → `rbcn vault` |

### 5.2 cert-manager 인증서가 갱신 안 됨

```bash
rbcn cert ls --expiring                          # 30일 이내 만료
rbcn cert renew <name>                           # 강제 갱신

kubectl describe certificaterequest -n <ns>      # 최근 요청 상태
```

원인 후보:
- ACME challenge 실패 (DNS01: 사내 DNS 가 외부 검증 받기 어려움 → DNS01 webhook 으로 PowerDNS 쓰는지)
- Rate limit (LE 의 시간당 제한)

### 5.3 Vault sealed

```bash
rbcn vault                                       # sealed=true 면 unseal 필요
# 5명의 키 보유자 중 3명 모임 → 각자 unseal key 입력
vault operator unseal
```

자세한 절차: [`runbooks/vault-unseal.md`](../runbooks/vault-unseal.md).

---

## 6. 성능 / 리소스 문제

### 6.1 latency 증가 (P99 ↑)

```bash
rbcn slo <svc>                                   # SLO 대시보드 직접
# Grafana 에서 RED:
#   - Rate: 갑자기 트래픽 늘었나
#   - Errors: 5xx % 가 증가했나
#   - Duration: latency histogram

# 분산 trace
# Grafana > Tempo > Service: <svc> > Trace 클릭
# → 어느 downstream 호출이 느린지 1초 안에 파악
```

### 6.2 노드 리소스 부족

```bash
kubectl top nodes
rbcn top
# 만약 cpu 90%+ 라면:
rbcn cost recommend <ns>                          # rightsizing 권장
# 또는 노드 추가: ansible playbook (관리자)
```

---

## 7. GitOps 동기화 깨짐 (drift)

### 7.1 누군가 cluster 에 직접 kubectl edit 함

```bash
# ArgoCD UI 의 해당 app: "OutOfSync" + diff 표시
# 정책상 git 이 source of truth
rbcn sync <app> --prune                           # git 으로 강제 회귀
# 이후 직접 변경한 사람과 협의 → 변경을 git PR 로
```

> 이를 막기 위해 prod cluster 는 RBAC 으로 일반 사용자의 write 차단 (Kyverno + 감사 로그).

---

## 8. 디버그 도구 모음

```bash
# Pod 안에 bash 가 없는 distroless image 디버깅
kubectl debug -n <ns> <pod> -it --image=nicolaka/netshoot --share-processes --target=app

# 노드 디버깅
kubectl debug node/<node> -it --image=nicolaka/netshoot

# Istio sidecar 의 envoy admin
kubectl exec -it -n <ns> <pod> -c istio-proxy -- pilot-agent request GET clusters

# K9s (TUI)
k9s
```

---

## 9. 어떻게 도움 받기

1. `#platform-help` (Slack): 일반 질문, 비긴급
2. `#alerts-prod` 본인 service 알림 보면서: on-call 에게 직접 mention
3. PagerDuty: 진짜 prod incident
4. Office hours: 매주 화 16:00, 핫이슈 1:1 (zoom 링크는 `#platform-help` pinned)

질문할 때 한번에 첨부하면 빠른 답:
- `rbcn diag <svc>` 의 출력
- 어느 cluster (`dev`/`stage`/`prod`)
- 마지막 정상 동작 시점 + 무엇이 바뀌었나
- (가능하면) 재현 방법

---

## 10. 다음 문서

- [`../ONBOARDING.md`](../ONBOARDING.md) — 신입 통합 가이드
- [`../runbooks/INDEX.md`](../runbooks/INDEX.md) — 모든 운영 runbook
- [`../postmortems/INDEX.md`](../postmortems/INDEX.md) — 과거 사고 분석
- [`cheatsheet.md`](./cheatsheet.md) — 1-page cheat sheet

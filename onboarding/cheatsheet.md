# 📑 RBCN — 1-page Cheat Sheet

> 인쇄해서 모니터 옆에 붙여두세요.
> 모든 명령은 `workspace VM` 위에서 (`ssh rbcn@<workspace-vm>`).
>
> **표기 규칙**: `<...>` 는 본인 값으로 교체해야 하는 placeholder.
> 그대로 복붙하면 shell 이 redirect 로 해석해 깨집니다. 예: `<svc>` → `payments`.

---

## 🚀 신규 서비스 (1 줄)

```bash
rbcn new <svc> --type=api|web|mfe|db|cache --owner=<team> [--lang=go|node|python] [--tier=T1|T2|T3] [--dry-run]
```

| type | 산출물 |
|---|---|
| `api`   | Go/Node/Python HTTP server + manifests + CI |
| `web`   | Next.js 14 SSR + ingress + cert |
| `mfe`   | Module Federation remote (nginx + CORS) |
| `db`    | CloudNative-PG cluster (HA 3-node) |
| `cache` | Redis HA (1 master + 2 replica + 3 sentinel) |

---

## 🌐 환경 / 컨텍스트

```bash
eval $(rbcn ctx dev|stage|prod)   # KUBECONFIG 환경변수 설정
rbcn whoami                       # 현재 user/cluster/namespace
rbcn ns <namespace>               # namespace 변경
rbcn nodes                        # 노드 상태
rbcn status                       # 모든 cluster + 핵심 서비스 한 화면
rbcn problems                     # CrashLoop / Pending / Failed 모두
```

---

## 🛠️ 워크로드

```bash
rbcn pods [ns]                    # pod 목록
rbcn logs <pod> [-f]              # 로그 (자동 추론 OK: rbcn logs <svc-prefix>)
rbcn exec <pod>                   # sh exec
rbcn pf <svc> <port|local:remote> # 예: rbcn pf payments 8080  →  localhost:8080 ↔ svc:8080
                                  #     rbcn pf payments 9090:8080 → localhost:9090 ↔ svc:8080
rbcn restart <deploy>             # rollout restart
rbcn events [ns]                  # warning events
rbcn top                          # CPU/Mem
rbcn diag <svc>                   # 종합 진단 (status+events+logs)
```

---

## 🚢 배포

```bash
rbcn promote <svc> dev   stage    # dev → stage 이미지 promote (PR 자동)
rbcn promote <svc> stage prod     # stage → prod
rbcn rollback <svc>               # Argo Rollouts 직전 stable
rbcn sync <app> [--prune]         # ArgoCD 강제 sync
rbcn apps                         # ArgoCD application 목록
rbcn appset                       # ApplicationSet 상태
```

---

## 🔐 시크릿 / 인증서

```bash
rbcn secret get <path>            # Vault read
rbcn secret put <path> k=v        # Vault write
rbcn secret ls <path>             # 하위 목록
rbcn secret sync-gh               # Vault → GH org secrets 5개 sync (검증 자동)

rbcn cert ls [--expiring]         # 인증서 + 만료
rbcn cert renew <name>            # 강제 갱신
rbcn vault                        # Vault sealed?
```

---

## 💾 백업 / 복구

```bash
rbcn backup ls [<svc>]            # Velero + CNPG snapshot 목록
rbcn backup now <ns>              # 즉시 백업
rbcn restore <name> [--to TIME]   # 복구 (PITR 가능)
rbcn etcd snapshots               # etcd 스냅샷
rbcn etcd health                  # etcd 클러스터 상태
```

---

## 💰 비용 / SLO

```bash
rbcn cost                         # 현재 (OpenCost)
rbcn cost report                  # 월간 보고서
rbcn cost recommend [ns]          # Goldilocks 권장 resources
rbcn slo <svc>                    # SLO 대시보드 직접 링크
```

---

## 🌐 Web UI (모두 SSO)

```bash
rbcn url <svc>                    # 모든 서비스 URL 자동 추론
rbcn url grafana                  # https://grafana.<env>.infra.rblnconnect.ai
rbcn url argocd                   # https://argocd.infra.rblnconnect.ai
rbcn url harbor                   # https://harbor.infra.rblnconnect.ai
rbcn url vault                    # https://vault.infra.rblnconnect.ai
rbcn url keycloak                 # https://keycloak.rebellions.ai
rbcn url kiali                    # https://kiali.<env>.infra.rblnconnect.ai
```

---

## 🏗️ 로컬 개발 (선택)

```bash
rbcn kind up                      # local kind cluster + ingress + cert-manager
rbcn dev <svc>                    # skaffold dev (저장 시 auto rebuild + redeploy)
rbcn dev all                      # tilt up (multi-svc)
```

---

## 🔍 GitHub Actions

```bash
gh run list -R rebellions-sw/<svc> -L 5
gh run watch -R rebellions-sw/<svc>
gh run rerun <run-id> -R rebellions-sw/<svc>
gh secret set <NAME> --org rebellions-sw --visibility all   # 또는 rbcn secret sync-gh
```

---

## 🗂️ 핵심 경로 (외워두면 좋음)

| 항목 | 경로 |
|---|---|
| 신입 가이드 | `/opt/rbcn-docs/ONBOARDING.md` |
| 운영자 SOT | `/opt/rbcn-docs/PLATFORM.md` |
| 서비스 카탈로그 | `/opt/rbcn-docs/services-catalog/services.yaml` |
| Reusable workflows | `https://github.com/rebellions-sw/.github/.github/workflows/` |
| ApplicationSet | `/opt/rbcn-docs/applicationsets/services-appset.yaml` |
| Runbooks | `/opt/rbcn-docs/runbooks/INDEX.md` |
| Postmortems | `/opt/rbcn-docs/postmortems/INDEX.md` |
| Troubleshooting | `/opt/rbcn-docs/onboarding/troubleshooting.md` |

---

## 🆘 막혔을 때

1. `rbcn diag <svc>` → 80% 자동 진단
2. `rbcn problems`  → 모든 비정상 pod 한 화면
3. [`onboarding/troubleshooting.md`](./troubleshooting.md) → 증상별 case-study
4. Slack `#platform-help` (질문할 때 위 1, 2 출력 첨부)
5. 진짜 prod incident: PagerDuty

---

## 📋 첫 30분 체크리스트 (Day-0)

```
[ ] SSH 접근 받음 (workspace VM)
[ ] gh auth login OK (gh auth status 확인)
[ ] ~/.kube/config-{dev,stage,prod} 존재
[ ] eval $(rbcn ctx dev) → kubectl get nodes 노드 보임
[ ] rbcn status → 핵심 서비스 모두 OK
[ ] rbcn url grafana → 브라우저 SSO 로그인 OK
[ ] rbcn new my-test --type=api --owner=<me> --dry-run 으로 무엇이 만들어지는지 확인
```

체크리스트 모두 ✓ 면 → [`api-service.md`](./api-service.md) 로 첫 PR 시작.

— 마지막 업데이트: 2026-04-19

# Post-mortem: ApplicationSet controller cannot reach API server

| | |
|---|---|
| Severity | P3 |
| Category | network / k8s |
| Reported | 2026-04-19T14:30Z |
| Detected | 2026-04-19T14:30Z (during ApplicationSet rollout) |
| Mitigated | 2026-04-19T14:35Z (workaround documented; root cause pending platform team) |
| Owner | platform |
| Service impact | services-catalog ApplicationSet does not reconcile (no auto-Application creation) |

## TL;DR

`argocd-applicationset-controller` pod 가 재시작되면 새 pod 가 `https://10.96.0.1:443` (kubernetes ClusterIP) 에 도달하지 못하고
`dial tcp 10.96.0.1:443: i/o timeout` 으로 informer 가 시작 실패. 모든 워커 노드에서 재현. 동일 노드에서 9일째 살아있는 다른 pod 는 cache hit 으로 정상.

## Symptoms

```text
W reflector.go:561] failed to list *v1.ConfigMap: Get "https://10.96.0.1:443/api/v1/namespaces/argocd/configmaps?labelSelector=…": dial tcp 10.96.0.1:443: i/o timeout
```

- AppSet `services` `.status` 가 빈 객체 (`{}`) → reconcile 1회도 안 됨
- 새로 추가한 services-catalog file 로 새 Application 생성 안 됨
- 옛 controller pod 는 `Running` 이지만 logs 가 reconcile/event 없음 (sleep)

## Impact

- 서비스 등록 시 ArgoCD Application 자동 생성 안 됨 → **수동 `kubectl apply -f application.yaml` 필요**
- 영향 범위: `services-catalog` 사용 신규 서비스만. 기존 5개 demo Application 은 그대로 동작 (옛 controller 가 만들었거나 수동).

## Workaround (현재)

1. 새 service 등록 시 ApplicationSet 이 아닌 직접 `kubectl apply -f` 로 Application 생성:
   ```bash
   # 카탈로그 entry (services/<svc>-<env>.yaml) 의 fields 로 Application yaml 수동 생성
   rbcn appset render <svc>     # ← 새 helper command 권장
   kubectl apply -f -
   ```
2. 또는 `rbcn new` script 가 마지막에 Application 자동 생성 단계 추가 (이번 PR 에서 적용).

## Root Cause Analysis (가설)

| Layer | 의심도 | 근거 |
|-------|--------|------|
| Calico 라우팅 (kube-svc IP propagate) | **HIGH** | 새 pod 만 fail, 모든 node 재현 |
| kube-proxy iptables/ipvs | MEDIUM | 옛 pod 는 cache 로 동작 → 룩업 자체는 OK 가능성 |
| NetworkPolicy egress | LOW | applicationset NP 가 `policyTypes=[Ingress]` 만, egress allow 자동 |
| API server overload | LOW | 다른 controller (application-controller) 는 정상 |

## Action Items

| # | Action | Owner | Due |
|---|--------|-------|-----|
| 1 | Calico 노드 재시작 / `calicoctl node status` 로 BGP/route 상태 확인 | platform | this week |
| 2 | `kube-proxy` ipvsadm 또는 iptables-save 로 10.96.0.1 backend 수 검증 | platform | this week |
| 3 | `rbcn new` 가 ApplicationSet 의존을 제거하고 직접 Application 생성 후 commit (workaround → 영구 fallback) | platform | DONE in v2 |
| 4 | `rbcn appset render <svc>` helper 추가 (수동 적용 편의) | platform | next sprint |

## Related

- ApplicationSet manifest: `/opt/rbcn-docs/applicationsets/services-appset.yaml`
- Service catalog regen: `/opt/rbcn-docs/services-catalog/regen.sh`
- 신규 서비스 부트스트랩: `templates/v2/new-service.sh`

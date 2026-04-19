# demo-api

> 자세한 운영은 **[Platform SOT](../PLATFORM.md)** 참조.

| 항목 | 값 |
|---|---|
| Type | REST API (Go) |
| Owner | platform |
| Tier | 2 (Important) |
| Source | github.com/rebellions-sw/rbcn-demo-api-manifests |
| Endpoint | https://dev.infra.rblnconnect.ai/api |

## Quick ops

```bash
rbcn diag demo-api                    # 상태 + 로그 + events
rbcn logs demo-api-...                # 로그 tail
rbcn restart deploy/demo-api          # rollout 재시작
```

## Runbook

- [K8s Control Plane](../runbooks/k8s-cp.md)
- [Platform SOT](../PLATFORM.md)

## Vault path

`secret/services/demo-api`

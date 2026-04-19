# demo-db-api

> 자세한 운영은 **[Platform SOT](../PLATFORM.md)** 참조.

| 항목 | 값 |
|---|---|
| Type | DB Adapter (Go) |
| Owner | platform |
| Tier | 2 (Important) |
| Source | github.com/rebellions-sw/rbcn-demo-db-api-manifests |
| Endpoint | demo-db-api.demo.svc.cluster.local:8080 (internal) |

## Quick ops

```bash
rbcn diag demo-db-api                    # 상태 + 로그 + events
rbcn logs demo-db-api-...                # 로그 tail
rbcn restart deploy/demo-db-api          # rollout 재시작
```

## Runbook

- [K8s Control Plane](../runbooks/k8s-cp.md)
- [Platform SOT](../PLATFORM.md)

## Vault path

`secret/services/demo-db-api`

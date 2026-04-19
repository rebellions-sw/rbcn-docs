# demo-postgres

> 자세한 운영은 **[Platform SOT](../PLATFORM.md)** 참조.

| 항목 | 값 |
|---|---|
| Type | Database (PostgreSQL 16) |
| Owner | platform |
| Tier | 1 (Critical) |
| Source | github.com/rebellions-sw/rbcn-demo-postgres-manifests |
| Endpoint | demo-postgres.demo-db.svc.cluster.local:5432 (internal, dev only) |

## Quick ops

```bash
rbcn diag demo-postgres                    # 상태 + 로그 + events
rbcn logs demo-postgres-...                # 로그 tail
rbcn restart deploy/demo-postgres          # rollout 재시작
```

## Runbook

- [DR: Postgres PITR](../dr/dr-runbook/05-pg-pitr.md)
- [Platform SOT](../PLATFORM.md)

## Vault path

`secret/services/demo-postgres`

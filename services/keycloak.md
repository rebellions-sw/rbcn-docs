# keycloak

> 자세한 운영은 **[Platform SOT](../PLATFORM.md)** 참조.

| 항목 | 값 |
|---|---|
| Type | OIDC Provider |
| Owner | platform |
| Tier | 1 (Critical) |
| Source | Helm chart (managed via Argo CD) |
| Endpoint | https://keycloak.infra.rblnconnect.ai |

## Quick ops

```bash
rbcn diag keycloak                    # 상태 + 로그 + events
rbcn logs keycloak-...                # 로그 tail
rbcn restart deploy/keycloak          # rollout 재시작
```

## Runbook

- [Keycloak runbook](../runbooks/keycloak.md)
- [Platform SOT](../PLATFORM.md)

## Vault path

`secret/services/keycloak`

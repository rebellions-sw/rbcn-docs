# vault

> 자세한 운영은 **[Platform SOT](../PLATFORM.md)** 참조.

| 항목 | 값 |
|---|---|
| Type | Secrets Manager |
| Owner | platform |
| Tier | 1 (Critical) |
| Source | Helm chart (managed via Argo CD) |
| Endpoint | https://vault.infra.rblnconnect.ai |

## Quick ops

```bash
rbcn diag vault                    # 상태 + 로그 + events
rbcn logs vault-...                # 로그 tail
rbcn restart deploy/vault          # rollout 재시작
```

## Runbook

- [Vault runbook](../runbooks/vault.md)
- [Platform SOT](../PLATFORM.md)

## Vault path

`secret/services/vault`

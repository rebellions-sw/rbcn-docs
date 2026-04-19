# harbor

> 자세한 운영은 **[Platform SOT](../PLATFORM.md)** 참조.

| 항목 | 값 |
|---|---|
| Type | Image Registry |
| Owner | platform |
| Tier | 2 (Important) |
| Source | Helm chart (managed via Argo CD) |
| Endpoint | https://harbor.infra.rblnconnect.ai |

## Quick ops

```bash
rbcn diag harbor                    # 상태 + 로그 + events
rbcn logs harbor-...                # 로그 tail
rbcn restart deploy/harbor          # rollout 재시작
```

## Runbook

- [K8s Control Plane](../runbooks/k8s-cp.md)
- [Platform SOT](../PLATFORM.md)

## Vault path

`secret/services/harbor`

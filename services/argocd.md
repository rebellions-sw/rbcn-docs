# argocd

> 자세한 운영은 **[Platform SOT](../PLATFORM.md)** 참조.

| 항목 | 값 |
|---|---|
| Type | GitOps Controller |
| Owner | platform |
| Tier | 1 (Critical) |
| Source | Helm chart (managed via Argo CD) |
| Endpoint | https://argocd.dev.infra.rblnconnect.ai |

## Quick ops

```bash
rbcn diag argocd                    # 상태 + 로그 + events
rbcn logs argocd-...                # 로그 tail
rbcn restart deploy/argocd          # rollout 재시작
```

## Runbook

- [K8s Control Plane](../runbooks/k8s-cp.md)
- [Platform SOT](../PLATFORM.md)

## Vault path

`secret/services/argocd`

# RBCN Infra Service Catalog

> 새 서비스 부트스트랩: `rbcn new <name> [go|node|python] --owner=<team>`
> 단일 진입점: [Platform SOT](../PLATFORM.md)

| Service | Type | Owner | Slack | Tier | Repo | Status |
|---------|------|-------|-------|------|------|--------|
| [demo-nextjs](./demo-nextjs.md) | UI (Next.js) | platform | #platform | 2 | github.com/rebellions-sw/rbcn-demo-nextjs-manifests | ✅ |
| [demo-api](./demo-api.md) | REST API (Go) | platform | #platform | 2 | github.com/rebellions-sw/rbcn-demo-api-manifests | ✅ |
| [demo-db-api](./demo-db-api.md) | DB Adapter (Go) | platform | #platform | 2 | github.com/rebellions-sw/rbcn-demo-db-api-manifests | ✅ |
| [demo-postgres](./demo-postgres.md) | Database (PG16) | platform | #db | 1 | (in cluster) | ✅ |
| [keycloak](./keycloak.md) | OIDC Provider | platform | #identity | 1 | (Helm) | ✅ |
| [vault](./vault.md) | Secrets | security | #security | 1 | (Helm) | ✅ |
| [harbor](./harbor.md) | Image Registry | platform | #platform | 2 | (Helm) | ✅ |
| [argocd](./argocd.md) | GitOps | platform | #gitops | 1 | (Helm) | ✅ |
| [ml-inference](./ml-inference.md) | ML serving | ml | #ml | 3 | TBD | 🚧 |

## Tier 정의
- **Tier 1**: Critical — downtime 시 전체 인프라 영향 (RTO < 5min)
- **Tier 2**: Important — 단일 cluster 영향 (RTO < 30min)
- **Tier 3**: Standard — 단일 service 영향 (RTO < 4h)

## Status 의미
- ✅ Production ready
- ⚠ Beta (운영 가능, 작은 issue)
- 🚧 Alpha (테스트 중)
- 📕 Deprecated

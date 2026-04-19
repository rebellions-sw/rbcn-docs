# RBCN Infra Service Catalog

| Service | Type | Owner | Slack | Tier | Repo | Status |
|---------|------|-------|-------|------|------|--------|
| [demo-nextjs](./demo-nextjs.md) | UI (Next.js) | platform | #platform | 2 | github.com/rbcn/demo-nextjs | ✅ |
| [demo-api](./demo-api.md) | REST API (Go) | platform | #platform | 2 | github.com/rbcn/demo-api | ✅ |
| [demo-db-api](./demo-db-api.md) | DB Adapter (Go) | platform | #platform | 2 | github.com/rbcn/demo-db-api | ✅ |
| [demo-postgres](./demo-postgres.md) | Database (PG16) | platform | #db | 1 | (operator) | ✅ |
| [keycloak](./keycloak.md) | OIDC Provider | platform | #identity | 1 | https://keycloak.org | ✅ |
| [vault](./vault.md) | Secrets | security | #security | 1 | https://vaultproject.io | ✅ |
| [harbor](./harbor.md) | Image Registry | platform | #platform | 2 | https://goharbor.io | ✅ |
| [argocd](./argocd.md) | GitOps | platform | #gitops | 1 | https://argo-cd.readthedocs.io | ✅ |

## Tier 정의
- **Tier 1**: Critical — downtime 시 전체 인프라 영향 (RTO < 5min)
- **Tier 2**: Important — 단일 cluster 영향 (RTO < 30min)
- **Tier 3**: Standard — 단일 service 영향 (RTO < 4h)

## Status 의미
- ✅ Production ready
- ⚠ Beta (운영 가능, 작은 issue)
- 🚧 Alpha (테스트 중)
- 📕 Deprecated

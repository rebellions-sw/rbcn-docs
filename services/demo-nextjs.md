# demo-nextjs

**Type**: UI (Next.js 14)
**Owner**: platform team (@your-handle)
**Slack**: #platform
**Tier**: 2
**Repo**: https://github.com/rbcn/demo-nextjs
**Image**: harbor.infra.rblnconnect.ai/library/demo-nextjs

## Endpoints
- dev:   https://dev.infra.rblnconnect.ai
- stage: https://stage.infra.rblnconnect.ai
- prod:  https://infra.rblnconnect.ai

## Deployment
- Argo Rollouts (canary 25→50→75→100)
- HPA: min=2 max=10, CPU 60%
- PDB: minAvailable=1 (prod minAvailable=2)
- Resources: 100m/128Mi req, 500m/256Mi limit

## Observability
- **Grafana Dashboard**: [demo-nextjs](https://grafana.dev.infra.rblnconnect.ai/d/demo-nextjs)
- **Prometheus rules**: SLO error budget 99.9% / latency p99 < 1s
- **Logs**: Loki — `{namespace="demo", app="demo-nextjs"}`
- **Traces**: Tempo — Service `demo-nextjs`
- **Service Mesh**: Kiali — sidecar 주입됨

## Dependencies
- demo-api (HTTP REST)
- Keycloak (OIDC auth)

## Runbooks
- [Deploy 절차](../runbooks/RUN-04.md)
- [Rollback](../runbooks/RUN-04.md#rollback)
- [Scale up/down](../runbooks/RUN-13.md)

## Related Incidents
- (현재까지 0건)

## On-call
- Primary:   @platform-oncall
- Secondary: @sre-team

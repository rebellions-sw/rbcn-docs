# ml-inference

**Type**: TBD
**Owner**: ml team
**Slack**: #ml
**Tier**: 3
**Repo**: TBD
**Image**: harbor.infra.rblnconnect.ai/library/ml-inference

## Endpoints
- dev:   TBD

## Deployment
- 표준: Argo Rollouts canary
- HPA: min=2 max=5

## Observability
- **Grafana**: 자동 생성 (kube-prometheus-stack)
- **Logs**: Loki — `{namespace="<ns>", app="ml-inference"}`
- **Traces**: Tempo

## Dependencies
TBD

## Runbooks
TBD

## On-call
- Primary: @ml-oncall

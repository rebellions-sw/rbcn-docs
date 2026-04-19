# <service-name>

> **Owner**: @rebellions-sw/<team>
> **Tier**: T0 / T1 / T2
> **Catalog**: [services/INDEX.md](https://github.com/rebellions-sw/rbcn-docs/blob/main/services/INDEX.md#<service-name>)
> **Manifests**: https://github.com/rebellions-sw/<service-name>-manifests

## What

<!-- 1-2 문장 설명 -->

## Run locally

```bash
make dev          # docker run, hot reload
# or:
skaffold dev      # k8s 로 (kind 클러스터 권장)
```

## Build

```bash
make build        # docker build
make push         # tag + push to harbor
```

## Deploy

```bash
# 자동: PR merge → CI → dev 자동 배포
# stage/prod: gh workflow run promote.yml -f from=dev -f to=stage  (manifests repo)
```

## Endpoints

- dev:   https://<svc>.dev.infra.rblnconnect.ai
- stage: https://<svc>.stage.infra.rblnconnect.ai
- prod:  https://<svc>.infra.rblnconnect.ai

## Operations

- Status:    `rbcn diag <svc>`
- Logs:      `rbcn logs <svc>`
- Rollback:  `rbcn rollback <svc>`
- Promote:   `rbcn promote <svc> dev stage`
- SLO:       `rbcn slo <svc>`

## Architecture

```
<draw.io / mermaid 또는 텍스트>
```

## Dependencies

- DB:   ...
- Cache: ...
- 외부 API: ...

## Runbooks

- Incident: `rbcn runbook <svc>`
- DR:       see `dr/dr-runbook/`

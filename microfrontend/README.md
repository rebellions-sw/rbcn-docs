# Micro Frontend Standard

> **목표**: 새 micro frontend (MFE) 추가가 새 backend API 추가만큼 쉬워야 함.

## 패턴 선택

Rebellions 표준은 **Module Federation (Next.js + @module-federation/nextjs-mf)**.

| 옵션 | 장점 | 단점 | 우리 선택 |
|------|------|------|---------|
| **Module Federation (MF)** | 빌드 타임 + 런타임 동적 import, 강한 type | webpack 설정 | YES (Next host + remote) |
| Single-SPA              | framework 자유 | 설정 복잡 | NO (over-kill) |
| Iframe                   | 완전 격리 | UX 저하, SSO 어려움 | NO |
| import-maps              | 표준 | 브라우저 호환 | NO |

## 아키텍처

```
                ┌──────────────────────────────────┐
                │ Host: demo-nextjs (web)           │
                │   /                                │
                │   /apps/*  → 동적 remote loader   │
                └──────────────────────────────────┘
                         │ runtime fetch
                         ↓
              ┌────────────────────────────────────┐
              │  Remote: rbcn-mfe-billing  (mfe)   │
              │  Remote: rbcn-mfe-analytics (mfe)  │
              │  Remote: rbcn-mfe-...               │
              └────────────────────────────────────┘
```

각 remote 는:
- 자체 repo (`rbcn-mfe-<name>`) + `rbcn-mfe-<name>-manifests`
- 자체 Harbor image, 자체 Ingress (`/apps/<name>` 경로)
- Host 의 `next.config.js` 에 remote URL 등록 (env 별)

## Ingress 규약

| 환경 | Host URL pattern | Remote URL pattern |
|------|------------------|---------------------|
| dev   | `app.dev.infra.rblnconnect.ai/apps/<mfe>`   | `mfe-<mfe>.dev.infra.rblnconnect.ai`   |
| stage | `app.stage.infra.rblnconnect.ai/apps/<mfe>` | `mfe-<mfe>.stage.infra.rblnconnect.ai` |
| prod  | `app.infra.rblnconnect.ai/apps/<mfe>`       | `mfe-<mfe>.infra.rblnconnect.ai`       |

> Ingress NGINX 의 `nginx.ingress.kubernetes.io/rewrite-target: /` + remote chunk 의 `publicPath: 'auto'`.

## 새 MFE 만들기

```bash
rbcn new my-billing --type=mfe --owner=billing-team
```

생성물 (golden path v2 자동):
1. `~/svc/my-billing/` (Next.js + MF 설정)
2. `~/svc/my-billing-manifests/` (deployment, service, ingress, cert, sm, pr)
3. `services-catalog` 에 1줄 등록 → ApplicationSet 이 onboard
4. CI: reusable-build.yaml 호출

## Host 등록

신규 remote 가 만들어지면 host (`demo-nextjs`) 의 `next.config.js` 에 추가:

```js
// next.config.js (host)
module.exports = {
  webpack(config, options) {
    if (!options.isServer) {
      config.plugins.push(new (require('@module-federation/nextjs-mf').NextFederationPlugin)({
        name: 'host',
        remotes: {
          billing:   `billing@${process.env.MFE_BILLING_URL}/_next/static/chunks/remoteEntry.js`,
          analytics: `analytics@${process.env.MFE_ANALYTICS_URL}/_next/static/chunks/remoteEntry.js`,
        },
        shared: { react: { singleton: true }, 'react-dom': { singleton: true } },
      }));
    }
    return config;
  },
};
```

env 는 ConfigMap 으로 환경별 주입:

```yaml
# overlays/dev/configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata: { name: host-mfe-urls }
data:
  MFE_BILLING_URL:   https://mfe-billing.dev.infra.rblnconnect.ai
  MFE_ANALYTICS_URL: https://mfe-analytics.dev.infra.rblnconnect.ai
```

## Type Safety

각 remote 는 `@types/<remote>` 패키지를 별도 build → host 가 type 으로 사용:

```bash
# remote 의 CI 에서 (reusable-build.yaml 의 옵션)
npm publish --registry https://harbor.infra.rblnconnect.ai/repository/npm-internal
```

## 보안

- 각 remote 는 독립 ServiceAccount + NetworkPolicy
- CSP header: `script-src 'self' https://mfe-*.infra.rblnconnect.ai`
- Cosign 서명 검증 (Kyverno) 으로 신뢰된 remote 만 배포 가능

## 관측

- 각 MFE 자체 ServiceMonitor + PrometheusRule (golden path 자동)
- Host 에 sentry/RUM 추가 → MFE 별 error rate
- `rbcn slo mfe-billing` 로 SLO Grafana 링크

## 비교: 단일 monolith vs MFE

| 영역 | Monolith Next.js | MFE (이 표준) |
|------|------------------|---------------|
| 팀 분리 | 어려움 | 강함 (repo 분리, 배포 분리) |
| 배포 빈도 | 통합 | 독립 |
| Bundle 크기 | 단일 거대 | shared chunks |
| 운영 복잡도 | 낮음 | 중간 (host config 동기화) |
| 장애 격리 | 낮음 | 높음 (remote 죽어도 host 살아있음) |

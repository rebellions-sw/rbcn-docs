# 🧩 Micro-Frontend (MFE) 만들기 (Step-by-Step)

> 대상: 신입 프론트엔드 개발자, 이미 host(=portal) web 서비스가 있는 상황
> 소요시간: **40분** (host 까지 함께 수정)
> 사전: [`web-service.md`](./web-service.md) 완료, host web (`portal` 등) 이 dev 에 떠있음
> 결과물: portal 의 특정 영역에서 동적으로 로드되는 remote 모듈

---

## 0. 무엇이 MFE 인가?

**Module Federation** (Webpack 5 native): 빌드 시점에 다른 팀의 코드를 묶지 않고, **런타임에 동적으로 가져와 렌더** 합니다.

```
[host=portal]   웹페이지 로딩
    │
    │ runtime fetch ──► [remote=search-widget]   /assets/remoteEntry.js
    ▼
사용자 화면에 host 와 remote 가 함께 렌더됨
```

장점:
- 팀별 독립 배포 (search 팀이 portal 배포 없이 자기 코드만 release)
- 런타임 격리 (remote 가 죽어도 host 살아있음)
- 버전 협상 (shared deps: react/react-dom)

단점:
- 런타임 의존 (remote 가 다운되면 그 부분만 깨짐)
- React 버전 동기화 필요

---

## 1. 시나리오

`search-widget` 라는 검색 영역을 portal 에 붙입니다.

| 항목 | 값 |
|---|---|
| Remote 서비스명 | `search-widget` |
| Host 서비스명 | `portal` (이미 있음) |
| 팀 | `search` |
| 노출 컴포넌트 | `SearchBar` (props: `placeholder`, `onSelect`) |

---

## 2. Remote 부트스트랩 (30초)

```bash
rbcn new search-widget --type=mfe --owner=search
```

`--type=mfe` 만의 차이:
- `webpack.config.js` 에 `ModuleFederationPlugin` 자동 설정
- `src/exposes/SearchBar.tsx` 자동 생성 (예시 컴포넌트)
- `Dockerfile` 이 정적 파일 빌드 후 **nginx alpine** 으로 serving (`remoteEntry.js` + assets)
- `base/ingress.yaml` hostname: `mfe-search-widget.<env>.infra.rblnconnect.ai`
- CORS / 캐시 헤더 미리 설정 (`Access-Control-Allow-Origin: https://portal.<env>.infra.rblnconnect.ai`)

---

## 3. Remote 컴포넌트 작성 (10분)

```bash
cd ~/svc/search-widget
cat src/exposes/SearchBar.tsx                    # 자동 생성된 stub 확인
```

수정:

```tsx
// src/exposes/SearchBar.tsx
import React, { useState } from 'react';

type Props = {
  placeholder?: string;
  onSelect: (query: string) => void;
};

export default function SearchBar({ placeholder = '검색…', onSelect }: Props) {
  const [q, setQ] = useState('');
  return (
    <div style={{display:'flex',gap:8}}>
      <input
        value={q}
        onChange={e => setQ(e.target.value)}
        placeholder={placeholder}
        style={{flex:1, padding:8}}
      />
      <button onClick={() => onSelect(q)}>찾기</button>
    </div>
  );
}
```

`webpack.config.js` 의 expose 확인 (자동 생성됨):

```js
new ModuleFederationPlugin({
  name: 'search_widget',
  filename: 'remoteEntry.js',
  exposes: {
    './SearchBar': './src/exposes/SearchBar.tsx',
  },
  shared: {
    react:       { singleton: true, requiredVersion: '^18.0.0' },
    'react-dom': { singleton: true, requiredVersion: '^18.0.0' },
  },
}),
```

```bash
git add -A
git commit -m "feat: implement SearchBar remote"
git push origin main
```

CI 가 GREEN 이 되면 dev 에 자동 배포 → `https://mfe-search-widget.dev.infra.rblnconnect.ai/remoteEntry.js` 로 접근 가능.

```bash
# 빌드된 remoteEntry.js 확인
curl -I https://mfe-search-widget.dev.infra.rblnconnect.ai/remoteEntry.js
# HTTP/2 200
# content-type: application/javascript
# access-control-allow-origin: https://portal.dev.infra.rblnconnect.ai
```

---

## 4. Host (portal) 에서 사용 (15분)

`portal` repo 로 이동:

```bash
cd ~/svc/portal
```

### 4.1 next.config.js 에 ModuleFederation 등록

```js
// next.config.js
const NextFederationPlugin = require('@module-federation/nextjs-mf');

module.exports = {
  output: 'standalone',
  webpack(config, { isServer }) {
    config.plugins.push(
      new NextFederationPlugin({
        name: 'portal',
        remotes: {
          search_widget: `search_widget@${process.env.NEXT_PUBLIC_MFE_SEARCH_URL}/remoteEntry.js`,
        },
        shared: {
          react:       { singleton: true, requiredVersion: '^18.0.0' },
          'react-dom': { singleton: true, requiredVersion: '^18.0.0' },
        },
      }),
    );
    return config;
  },
};
```

### 4.2 환경변수 (env 별로 다름)

manifests repo 의 overlays 에서:

```yaml
# overlays/dev/configmap-patch.yaml
apiVersion: v1
kind: ConfigMap
metadata: { name: portal }
data:
  NEXT_PUBLIC_MFE_SEARCH_URL: "https://mfe-search-widget.dev.infra.rblnconnect.ai"
# overlays/stage:  ...stage.infra...
# overlays/prod:   ...infra...  (env subdomain 없음)
```

### 4.3 React 컴포넌트로 사용

```tsx
// app/search/page.tsx
'use client';
import dynamic from 'next/dynamic';

const SearchBar = dynamic(
  () => import('search_widget/SearchBar'),  // ← remote module path
  { ssr: false, loading: () => <div>검색 로딩 중…</div> }
);

export default function Page() {
  return (
    <main style={{padding:24}}>
      <h1>검색</h1>
      <SearchBar
        placeholder="결제 ID 입력"
        onSelect={q => alert(`검색: ${q}`)}
      />
    </main>
  );
}
```

```bash
git add next.config.js app/search/page.tsx
git commit -m "feat: integrate search-widget MFE"
git push origin main
```

dev 자동 배포 후 `https://portal.dev.infra.rblnconnect.ai/search` 에서 SearchBar 가 동적으로 로드됩니다.

---

## 5. 관측 / 디버깅

### 5.1 remote 가 로드 안 됨

브라우저 개발자도구 Console:

```
ChunkLoadError: Loading chunk search_widget failed
```

원인 후보:
| 원인 | 확인 |
|---|---|
| remote 서비스 down | `kubectl get pods -n search-widget` |
| CORS 거부 | Network 탭에서 `OPTIONS /remoteEntry.js` 확인 → `Access-Control-Allow-Origin` |
| URL mismatch | host 의 `NEXT_PUBLIC_MFE_SEARCH_URL` env 값 확인 |
| React 버전 불일치 | host/remote 의 `react` 버전을 `^18.0.0` 로 통일 |

### 5.2 distributed tracing

Istio 가 자동 propagate 하는 trace header (`x-request-id`, `traceparent`) 가 host → remote → backend API 까지 한 trace 로 보입니다.

```bash
rbcn url grafana
# Tempo > Search > Service: portal → Trace 클릭 → search-widget 도 같은 trace 안에 있음
```

---

## 6. Versioning / Rollout 전략

remote 의 변경이 host 를 깨뜨릴 수 있어 **breaking change** 와 **non-breaking** 을 구분:

| 변경 유형 | 예시 | 정책 |
|---|---|---|
| Non-breaking | prop 추가 (optional), 스타일 | 즉시 release |
| Breaking | prop 이름 변경, 컴포넌트 삭제 | semver major + 모든 host 팀에 1 sprint 사전 공지 |

릴리스 안전망:
1. Argo Rollouts canary 5% → 25% → 100% (분당 5분 간격)
2. 자동 rollback 트리거: 5xx rate ≥ 1% 또는 P99 ≥ 1000ms

→ 자동 설정됨. 필요시 `overlays/<env>/rollout-patch.yaml` 에서 임계값 조정.

---

## 7. 자동 생성된 파일 핵심

```
search-widget/
├── webpack.config.js               (ModuleFederationPlugin)
├── src/
│   ├── exposes/
│   │   └── SearchBar.tsx          (예제 expose)
│   └── bootstrap.tsx              (host 단독 실행 시 진입점)
├── nginx.conf                     (CORS, cache headers, gzip)
├── Dockerfile                     (multi-stage: build + nginx:alpine)
├── package.json
└── tsconfig.json
```

manifests:

```
search-widget-manifests/
├── base/
│   ├── deployment.yaml            (nginx, port 80)
│   ├── ingress.yaml               (mfe-search-widget.<env>.infra.rblnconnect.ai)
│   ├── certificate.yaml
│   ├── configmap-nginx.yaml       (CORS allowlist)
│   └── ...
└── overlays/{dev,stage,prod}/
```

---

## 8. 다음 가이드

- [`web-service.md`](./web-service.md) — host (Next.js) web 만들기
- [`../microfrontend/README.md`](../microfrontend/README.md) — Module Federation 심화
- [`cheatsheet.md`](./cheatsheet.md) — 1-page cheat sheet

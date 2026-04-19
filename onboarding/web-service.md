# 🌐 Web 서비스 만들기 (Next.js, Step-by-Step)

> 대상: 신입 프론트엔드 개발자.
> 소요시간: **35분** (TS/Next 빌드 시간 포함)
> 사전: [`ONBOARDING.md`](../ONBOARDING.md) §1 (Day-0 환경 준비) 완료
> 결과물: `https://portal.dev.infra.rblnconnect.ai` 로 접근 가능한 SSR Next.js 앱

---

## 0. 시나리오

`portal` 이라는 사용자 포털을 Next.js 14 (App Router) 로 만든다고 가정합니다.

| 항목 | 값 |
|---|---|
| 서비스명 | `portal` |
| 언어 | `node` (Next.js 14, TypeScript) |
| 팀 | `frontend` |
| 티어 | `T1` |
| 환경 | `dev`, `stage`, `prod` |

---

## 1. 부트스트랩 (30초)

```bash
rbcn new portal --type=web --lang=node --owner=frontend --tier=T1
```

`--type=web` 일 때 [`api-service.md`](./api-service.md) 와 다른 점:
- `index.ts` 대신 **Next.js 14 skeleton** (`app/`, `pages/`, `next.config.js`)
- `Dockerfile` 이 `node:22-alpine` build 후 `node:22-slim` runtime + `next start`
- `base/deployment.yaml` 의 port 가 `3000` (Next.js 기본)
- `base/ingress.yaml` 이 hostname `portal.<env>.infra.rblnconnect.ai`
- `base/configmap.yaml` 에 `NEXT_PUBLIC_API_URL` 등 환경변수 자동

---

## 2. 자동 생성된 Next.js 코드 보기

```bash
cd ~/svc/portal
tree -L 2 app                                    # App Router 구조

# 핵심 파일들
cat package.json | jq '.scripts'                 # dev / build / start / lint
cat next.config.js                               # standalone output (Docker 친화)
cat app/page.tsx                                 # "/" 페이지
cat app/api/healthz/route.ts                     # /api/healthz (probe 용)
```

자동 생성된 `Dockerfile` (Next.js standalone output 활용):

```dockerfile
FROM node:22-alpine AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci

FROM node:22-alpine AS build
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
RUN npm run build

FROM node:22-slim
WORKDIR /app
COPY --from=build /app/.next/standalone ./
COPY --from=build /app/.next/static ./.next/static
COPY --from=build /app/public ./public
USER node
EXPOSE 3000
ENV PORT=3000
CMD ["node", "server.js"]
```

---

## 3. 첫 페이지 수정 + push (5분)

```bash
cd ~/svc/portal

# app/page.tsx 수정
cat > app/page.tsx <<'EOF'
export default function Page() {
  return (
    <main style={{padding:24,fontFamily:'sans-serif'}}>
      <h1>Hello, Portal 👋</h1>
      <p>Build: {process.env.BUILD_TAG ?? 'dev'}</p>
    </main>
  );
}
EOF

git add app/page.tsx
git commit -m "feat: add hello hero"
git push origin main
```

---

## 4. CI 동작 확인 (5~6분, Next.js 빌드 시간 포함)

```bash
gh run watch -R rebellions-sw/portal
```

build job 의 핵심 단계 (api 와 동일하지만 Dockerfile build 가 길어짐):

| 단계 | 평균 시간 |
|---|---|
| docker buildx build (npm ci + next build, no cache) | 90~150s |
| docker buildx build (cache hit) | 20~40s |
| trivy scan (node:22 base) | 10s |
| cosign sign | 5s |

> 첫 빌드는 cold cache 라 느립니다. 두 번째부터 buildx registry cache 가 작동.

---

## 5. dev 클러스터 확인 (3분)

```bash
rbcn apps | grep portal                          # portal-dev / portal-stage / portal-prod
eval $(rbcn ctx dev)
kubectl get pods -n portal -w                    # Running 1/1
```

브라우저에서 직접:

```
https://portal.dev.infra.rblnconnect.ai
```

> SSL 인증서는 cert-manager + Let's Encrypt 가 자동 (수십 초 소요).

또는 port-forward:

```bash
rbcn pf portal 3000
open http://localhost:3000
```

---

## 6. Backend API 호출 추가 (10분)

`payments` API 를 호출하는 SSR 페이지 만들기:

```bash
cat > app/charges/page.tsx <<'EOF'
async function getCharges() {
  // K8s ClusterDNS: <svc>.<ns>.svc.cluster.local
  const res = await fetch('http://payments.payments.svc.cluster.local:8080/charge', {
    cache: 'no-store',
  });
  return res.json();
}

export default async function Charges() {
  const data = await getCharges();
  return (
    <main style={{padding:24}}>
      <h1>Charges</h1>
      <pre>{JSON.stringify(data, null, 2)}</pre>
    </main>
  );
}
EOF

git add app/charges/page.tsx
git commit -m "feat: add /charges SSR page calling payments API"
git push origin main
```

dev 에 자동 배포 후:

```
https://portal.dev.infra.rblnconnect.ai/charges
```

> 클러스터 간 서비스 호출은 **항상 ClusterDNS 사용** (`<svc>.<ns>.svc.cluster.local`). 외부 도메인 (`https://payments.dev.infra.rblnconnect.ai`) 으로 호출하면 latency↑ + Istio mTLS 안 됨.

---

## 7. 환경변수 / 시크릿

### 7.1 public 환경변수 (`NEXT_PUBLIC_*`)

manifests repo 의 `base/configmap.yaml` 수정:

```yaml
apiVersion: v1
kind: ConfigMap
metadata: { name: portal }
data:
  NEXT_PUBLIC_API_URL: "https://payments.dev.infra.rblnconnect.ai"
  NEXT_PUBLIC_FEATURE_FLAG_X: "true"
```

### 7.2 server-only 시크릿

```bash
rbcn secret put secret/services/portal \
    SESSION_SECRET=$(openssl rand -hex 32) \
    OAUTH_CLIENT_SECRET='xxxx'
```

ESO 가 자동으로 `Secret/portal` 생성 → Pod 의 `envFrom.secretRef.name=portal` 로 자동 주입.

> **주의**: `NEXT_PUBLIC_*` 가 붙은 변수는 클라이언트 번들에 포함되어 노출됩니다. 절대 시크릿을 거기에 넣지 마세요.

---

## 8. 정적 자산 + CDN

`public/` 폴더의 모든 파일은 빌드 시 `.next/static` 으로 복사 → ingress-nginx 가 캐시 (HTTP cache headers).

대용량 자산 (이미지/비디오) 은 별도 MinIO 버킷 사용:

```bash
rbcn url minio                                   # MinIO console
# bucket: portal-static
# 업로드 후 URL: https://minio.infra.rblnconnect.ai/portal-static/<file>
```

---

## 9. Lighthouse / 성능 측정

```bash
# Lighthouse CI 가 PR 마다 자동 (deps 에 포함)
gh pr view --web                                 # PR 의 Lighthouse comment 확인
```

기본 임계값:
- Performance ≥ 80
- Accessibility ≥ 95
- SEO ≥ 95
- BestPractices ≥ 90

PR 머지 차단 임계값은 [`org-templates/base-app/lighthouserc.json`](../org-templates/base-app/) 참고.

---

## 10. 로컬 개발 (선택, fastest loop)

```bash
cd ~/svc/portal
npm install
npm run dev                                      # http://localhost:3000 (HMR)
```

또는 kind + skaffold:

```bash
rbcn kind up
rbcn dev portal                                  # skaffold dev = 저장 시 auto rebuild + redeploy
```

---

## 11. 다음 가이드

- [`mfe-service.md`](./mfe-service.md) — 이 portal 에 micro-frontend remote 붙이기
- [`api-service.md`](./api-service.md) — 백엔드 API
- [`cheatsheet.md`](./cheatsheet.md) — 1-page cheat sheet
- [`../microfrontend/README.md`](../microfrontend/README.md) — Module Federation 자세히

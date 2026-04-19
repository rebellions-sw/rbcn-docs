# Local Development Loop

> **목표**: 코드 → 빌드 → k8s 배포 → 결과 확인을 **5초 이내** + Harbor push 없이.

## 옵션 비교

| 옵션 | 속도 | 클러스터 필요 | 장점 |
|------|------|---------------|------|
| **Docker Compose**     | < 3s | 없음 | 가장 단순 |
| **Skaffold + kind**    | < 5s | local kind | 운영과 동일 manifests, hot reload |
| **Tilt + kind**        | < 5s | local kind | 멀티 서비스 + UI |
| **devspace + kind**    | < 5s | local kind | 더 강한 dev container |
| **dev cluster (원격)** | 10-20s | dev k3s | 네트워크/RBAC 실제 |

> 권장: **Skaffold + kind** (1 서비스 개발 시) / **Tilt + kind** (2개 이상 서비스 동시)

## 0. kind 클러스터 만들기 (1회)

```bash
# kind 설치
[ -x /usr/local/bin/kind ] || (curl -Lo /usr/local/bin/kind https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64 && chmod +x /usr/local/bin/kind)

# 클러스터 (ingress + registry mirror)
cat > /tmp/kind.yaml <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
    kubeadmConfigPatches:
      - |
        kind: InitConfiguration
        nodeRegistration:
          kubeletExtraArgs:
            node-labels: "ingress-ready=true"
    extraPortMappings:
      - { containerPort: 80,  hostPort: 80,  protocol: TCP }
      - { containerPort: 443, hostPort: 443, protocol: TCP }
containerdConfigPatches:
  - |
    [plugins."io.containerd.grpc.v1.cri".registry.mirrors."harbor.infra.rblnconnect.ai"]
      endpoint = ["http://harbor.infra.rblnconnect.ai"]
EOF
kind create cluster --config /tmp/kind.yaml --name rbcn-dev

# Ingress NGINX
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

# (옵션) cert-manager + ESO
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/latest/download/cert-manager.yaml
helm repo add external-secrets https://charts.external-secrets.io
helm install -n external-secrets --create-namespace eso external-secrets/external-secrets
```

## 1. Skaffold (단일 서비스 dev loop)

`golden-path v2` 가 이미 `skaffold.yaml` 을 생성합니다.

```bash
cd ~/svc/my-service
skaffold dev
# code 수정 → 자동 build → kind 자동 deploy → port-forward
# 종료: Ctrl+C
```

상세 옵션:

```bash
skaffold dev --port-forward          # 자동 PF
skaffold dev --tail                  # log tail
skaffold dev --profile=debug         # delve 포트 추가
skaffold render                      # manifest 만 출력
skaffold run                         # 한번만 빌드+배포
```

## 2. Tilt (멀티 서비스 dev loop)

여러 서비스를 동시에 개발할 때:

```python
# Tiltfile (workspace root, ~/dev/Tiltfile)
load('ext://restart_process', 'docker_build_with_restart')

# 1. 의존 서비스: kind 에 deploy (live)
k8s_yaml(kustomize('~/svc/demo-postgres-manifests/overlays/dev'))
k8s_yaml(kustomize('~/svc/demo-db-api-manifests/overlays/dev'))

# 2. 작업 중인 서비스: hot reload
docker_build_with_restart(
    'harbor.infra.rblnconnect.ai/library/my-service',
    '~/svc/my-service',
    entrypoint='./app',
    live_update=[
        sync('~/svc/my-service/main.go', '/src/main.go'),
        run('cd /src && go build -o /app .'),
    ],
)
k8s_yaml(kustomize('~/svc/my-service-manifests/overlays/dev'))

# 3. Port forwards
k8s_resource('my-service',     port_forwards=8080)
k8s_resource('demo-db-api',    port_forwards=8081)
```

```bash
cd ~/dev
tilt up
# 브라우저 → http://localhost:10350  (Tilt UI)
```

## 3. Docker Compose (가장 단순)

DB + Service 1개만 빠르게 띄울 때:

```bash
cd ~/svc/my-service
cat > compose.yaml <<EOF
services:
  app:
    build: .
    ports: ["8080:8080"]
    environment:
      DB_HOST: db
      DB_PASS: dev
    depends_on: [db]
  db:
    image: postgres:16
    environment:
      POSTGRES_PASSWORD: dev
      POSTGRES_DB: app
    ports: ["5432:5432"]
EOF
docker compose up
```

## 4. 원격 dev cluster (운영급 검증)

```bash
# 코드를 dev 클러스터에서 직접 돌리기
KUBECONFIG=~/.kube/config-dev skaffold dev --default-repo=harbor.infra.rblnconnect.ai/library
```

## 디버깅

| 도구 | 용도 |
|------|------|
| `kubectl debug -it <pod> --image=busybox`           | 임시 sidecar 진단 |
| `kubectl port-forward svc/<svc> 8080:80`            | local → cluster |
| `stern <pod-prefix>`                                 | 멀티 pod log tail |
| `k9s`                                               | TUI 클러스터 탐색 |
| `kubectl-dlv` / vscode `ms-kubernetes-tools`        | breakpoint debug |
| `dlv` (Go) / `node --inspect` / `pdb` (Python)      | 언어별 debugger |

## CI 와 동등성 보장

로컬 빌드 = CI 빌드 보장:

```bash
# Local
docker buildx build --platform linux/amd64 -t local-test .

# CI (reusable-build.yaml) 와 동일한 base image, sbom, trivy 흐름
make build sbom scan
```

# 🔥 Cache (Redis HA) 만들기 (Step-by-Step)

> 대상: 신입 백엔드 개발자, 본인 서비스 전용 Redis 가 필요할 때
> 소요시간: **10분**
> 결과물: HA Redis (Sentinel 3-노드) + 자동 자격증명 + 메트릭

---

## 0. 무엇이 자동인가

- Helm chart [`bitnami/redis`](https://artifacthub.io/packages/helm/bitnami/redis) 가 사전 검증된 values 로 설치
- HA: 1 master + 2 replica + 3 Sentinel
- TLS 활성화 (Istio mTLS)
- Password 자동 생성 → K8s Secret + Vault sync
- redis_exporter sidecar (Prometheus)
- PVC 로 영속성 (replica 도 영속, master 가 OOM 되면 Sentinel 이 promote)

---

## 1. 한 줄 명령

```bash
rbcn cache create payments-cache --ns=payments
```

뒤에서 실행되는 것:
```
helm upgrade --install payments-cache bitnami/redis \
  -n payments --create-namespace \
  -f /opt/rbcn-docs/operators/redis/values.yaml \
  --set fullnameOverride=payments-cache \
  --set auth.password=$(openssl rand -hex 32)
```

(자세한 내부 동작은 [`operators/redis/install.sh`](../operators/redis/install.sh) 참고)

---

## 2. 진행 확인

```bash
eval $(rbcn ctx dev)
kubectl get pods -n payments -l app.kubernetes.io/instance=payments-cache
# payments-cache-master-0    2/2  Running
# payments-cache-replicas-0  2/2  Running
# payments-cache-replicas-1  2/2  Running
# payments-cache-sentinel-0  2/2  Running
# payments-cache-sentinel-1  2/2  Running
# payments-cache-sentinel-2  2/2  Running
```

---

## 3. 자격증명

```bash
# K8s Secret
kubectl get secret payments-cache -n payments -o jsonpath='{.data.redis-password}' | base64 -d

# Vault
rbcn secret get secret/services/payments/cache
```

엔드포인트:

| 용도 | 호스트 |
|---|---|
| read-write (master) | `payments-cache-master.payments.svc.cluster.local:6379` |
| read-only (replicas, LB) | `payments-cache-replicas.payments.svc.cluster.local:6379` |
| Sentinel | `payments-cache.payments.svc.cluster.local:26379` |

---

## 4. 앱에서 사용 (예: Go)

```go
import "github.com/redis/go-redis/v9"

rdb := redis.NewFailoverClient(&redis.FailoverOptions{
    MasterName:    "mymaster",
    SentinelAddrs: []string{"payments-cache.payments.svc.cluster.local:26379"},
    Password:      os.Getenv("REDIS_PASSWORD"),
})
```

ExternalSecret 으로 자동 주입:

```yaml
# manifests repo: base/externalsecret.yaml (이미 자동 생성)
data:
  - secretKey: REDIS_PASSWORD
    remoteRef: { key: services/payments/cache, property: redis-password }
```

---

## 5. redis-cli 디버깅

```bash
kubectl exec -it -n payments payments-cache-master-0 -- \
  redis-cli -a "$(kubectl get secret payments-cache -n payments -o jsonpath='{.data.redis-password}' | base64 -d)"
# > INFO replication
# > KEYS *
```

---

## 6. 메트릭

```bash
rbcn url grafana
# Dashboards > "Redis Overview" → instance=payments-cache
# - hit/miss ratio, ops/s, memory, replication lag, evictions
```

알림 자동 적용:
- master down (Sentinel failover trigger)
- replica lag > 10s
- memory > 90%
- evicted_keys > 0 (eviction 발생 시)

---

## 7. 용량 / 정책 변경

```bash
# 메모리 한도 변경 (예: 4Gi → 8Gi)
helm upgrade payments-cache bitnami/redis -n payments --reuse-values \
  --set master.resources.limits.memory=8Gi \
  --set replicas.resources.limits.memory=8Gi
```

eviction policy 변경:

```bash
helm upgrade payments-cache bitnami/redis -n payments --reuse-values \
  --set master.configuration='maxmemory-policy allkeys-lru'
```

---

## 8. cleanup

```bash
helm uninstall payments-cache -n payments
kubectl delete pvc -n payments -l app.kubernetes.io/instance=payments-cache  # PVC 명시 삭제
```

---

## 9. 다음 가이드

- [`api-service.md`](./api-service.md) — Redis 와 연결되는 API
- [`db-service.md`](./db-service.md) — Postgres
- [`../operators/redis/`](../operators/redis/) — Redis 운영자 docs

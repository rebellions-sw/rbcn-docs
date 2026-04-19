# Redis Cache (Self-Service)

## 새 cache 만들기

```bash
# 방법 1: rbcn
rbcn cache create my-svc-cache --ns=my-svc

# 방법 2: 스크립트
bash /opt/rbcn-docs/operators/redis/install.sh dev my-svc my-svc-cache
```

## 연결

```
HOST:    my-svc-cache-master.my-svc.svc:6379  (write)
         my-svc-cache-replicas.my-svc.svc:6379 (read-only)
PASS:    kubectl -n my-svc get secret my-svc-cache -o jsonpath='{.data.redis-password}' | base64 -d
```

ExternalSecret:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata: { name: my-svc-cache, namespace: my-svc }
spec:
  refreshInterval: 1h
  secretStoreRef: { name: vault, kind: ClusterSecretStore }
  target: { name: my-svc-cache-creds }
  data:
    - secretKey: REDIS_HOST
      remoteRef: { key: services/my-svc/cache, property: host }
    - secretKey: REDIS_PASS
      remoteRef: { key: services/my-svc/cache, property: password }
```

## 비교

| 옵션 | HA | Persistence | 모니터링 |
|------|----|----|----|
| **Bitnami helm (이 표준)** | 1 master + 2 replica | YES | ServiceMonitor 자동 |
| Redis Operator (Spotahome/OT) | 자동 failover | YES | ServiceMonitor |
| Valkey (apache fork) | YES | YES | YES |

> 운영은 Bitnami 표준 권장, OSS 라이선스 우려 시 Valkey.

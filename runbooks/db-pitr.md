# CloudNative-PG 시점 복구 (PITR) Runbook

> 운영 DB 를 N분/시간 전 시점으로 되돌려야 할 때.

---

## 0. 무엇이 가능한가

CNPG + MinIO WAL archive 덕분에 다음이 자동:

- **WAL archive** 매 5분 → 최대 RPO 5분
- 보존 기간 30일 (수정: `cluster.spec.backup.retentionPolicy`)
- **새 cluster 로 복원** 후 swap (운영 영향 최소화)

---

## 1. 시나리오

`payments-db` 를 30분 전 (`2026-04-19T14:30:00Z`) 시점으로 되돌립니다.

---

## 2. 사전 점검 (5분)

```bash
# WAL archive 가 정상 동작중?
kubectl exec -n payments payments-db-1 -c postgres -- \
    psql -U postgres -c "SELECT * FROM pg_stat_archiver;"
# archived_count 가 꾸준히 증가하면 OK

# 백업 목록
kubectl get backup -n payments
# 가장 최신의 completed 백업 확인 (복구 시작점)

# MinIO bucket 에 WAL 파일 있나
mc ls cnpg-wal/payments-db/wals/ | tail -10
```

---

## 3. 복구 cluster 생성

```yaml
# /tmp/payments-db-restored.yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: payments-db-restored
  namespace: payments
spec:
  instances: 3
  storage: { size: 50Gi, storageClass: ceph-rbd }
  bootstrap:
    recovery:
      source: payments-db
      recoveryTarget:
        targetTime: "2026-04-19T14:30:00.000+00:00"
  externalClusters:
    - name: payments-db
      barmanObjectStore:
        destinationPath: s3://cnpg-wal/payments-db
        endpointURL: https://minio.infra.rblnconnect.ai
        s3Credentials:
          accessKeyId:     { name: minio-creds, key: AWS_ACCESS_KEY_ID }
          secretAccessKey: { name: minio-creds, key: AWS_SECRET_ACCESS_KEY }
        wal:
          compression: gzip
```

```bash
kubectl apply -f /tmp/payments-db-restored.yaml
kubectl get cluster -n payments -w
# Phase: "Setting up primary" → "Cluster in healthy state" (10~20분 소요)
```

---

## 4. 데이터 검증

```bash
PGPASSWORD=$(kubectl get secret payments-db-restored-app -n payments -o jsonpath='{.data.password}' | base64 -d)
kubectl exec -n payments payments-db-restored-1 -- \
    psql -U app -d app -c "SELECT count(*) FROM transactions WHERE created_at < '2026-04-19T14:30:00Z';"

# 비교: 원본 DB 와 같은 query
kubectl exec -n payments payments-db-1 -- \
    psql -U app -d app -c "SELECT count(*) FROM transactions WHERE created_at < '2026-04-19T14:30:00Z';"
```

기대값과 다르면 다른 시점으로 다시 복구 시도.

---

## 5. Swap (서비스 영향 최소화)

```bash
# 1) 앱이 보는 endpoint 를 새 cluster 로 변경
kubectl patch service payments-db-rw -n payments -p '{"spec":{"selector":{"cnpg.io/cluster":"payments-db-restored"}}}'
kubectl patch service payments-db-ro -n payments -p '{"spec":{"selector":{"cnpg.io/cluster":"payments-db-restored"}}}'

# 2) 앱은 connection pool refresh 하면 자동 새 DB 보게 됨
kubectl rollout restart deploy/payments -n payments

# 3) 옛 cluster 를 잠시 보존 (30일) 후 삭제
kubectl annotate cluster payments-db -n payments retain-after-swap="$(date -u +%Y-%m-%d)"
```

---

## 6. Rollback

새 DB 도 이상하다면:

```bash
# 옛 service selector 로 복귀
kubectl patch service payments-db-rw -n payments -p '{"spec":{"selector":{"cnpg.io/cluster":"payments-db"}}}'
kubectl patch service payments-db-ro -n payments -p '{"spec":{"selector":{"cnpg.io/cluster":"payments-db"}}}'
kubectl rollout restart deploy/payments -n payments
```

---

## 7. Cleanup

복구가 성공적이고 30일이 지났으면:

```bash
kubectl delete cluster payments-db -n payments
# → 옛 PVC 도 자동 삭제되니 신중히
```

---

## 8. rbcn 단축 명령

```bash
rbcn restore payments-db --to '2026-04-19T14:30:00Z'
# → 위 §3~§4 자동 + §5 swap 은 user confirm 필요
```

---

## 9. 더 자세히

- [`onboarding/db-service.md`](../onboarding/db-service.md) — DB 만들기
- [`operators/cloudnative-pg/`](../operators/cloudnative-pg/) — CNPG 운영자 docs
- [CloudNative-PG PITR docs](https://cloudnative-pg.io/documentation/current/recovery/)

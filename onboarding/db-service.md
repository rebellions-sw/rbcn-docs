# 🗄️ Database (Postgres) 만들기 (Step-by-Step)

> 대상: 신입 백엔드 개발자, 본인 서비스 전용 DB 가 필요할 때
> 소요시간: **15분** (CNPG provisioning 시간 포함)
> 사전: [`ONBOARDING.md`](../ONBOARDING.md) §1 완료
> 결과물: HA Postgres 3-instance 클러스터 + 자동 백업 + Vault 자동 자격증명 + Prometheus 메트릭

---

## 0. 무엇이 자동으로 되어 있는가

**CloudNative-PG (CNPG) Operator** 가 dev/stage/prod 모든 클러스터에 설치되어 있고, 다음을 자동으로 처리:

- HA: 1 primary + 2 replicas (synchronous streaming replication)
- 백업: WAL → MinIO 매 5분, full backup 매일 02:00 UTC
- 시점 복구 (PITR): 최대 30 일
- 자격증명: 자동 생성된 user/password 가 K8s `Secret` + Vault 에 저장
- 메트릭: Prometheus exporter sidecar (자동)
- 인증서: cert-manager 자동 (TLS 클라이언트 연결)
- TLS, mTLS Istio: 자동
- Pod anti-affinity: 같은 노드에 primary/replica 함께 안 뜸

---

## 1. 한 줄 명령

```bash
rbcn db create payments-db --ns=payments --instances=3
```

이 명령은:

1. 네임스페이스 `payments` 가 없으면 생성
2. CNPG `Cluster` CR 1개 생성 (`payments-db`)
3. CNPG operator 가 ~3분 안에 primary + 2 replicas pod 띄움
4. K8s `Secret/payments-db-app` 자동 생성 (user/password/host/port)
5. Vault `secret/services/payments/db` 에 동일 자격증명 자동 sync (External Secrets Operator)

---

## 2. 진행 확인

```bash
eval $(rbcn ctx dev)
kubectl get cluster -n payments                  # CNPG Cluster CR
# NAME           AGE   INSTANCES   READY   STATUS                     PRIMARY
# payments-db    2m    3           3       Cluster in healthy state   payments-db-1

kubectl get pods -n payments -l cnpg.io/cluster=payments-db
# payments-db-1   1/1  Running  (primary)
# payments-db-2   1/1  Running  (replica, sync)
# payments-db-3   1/1  Running  (replica, sync)
```

---

## 3. 자격증명 가져오기

```bash
# 방법 1: K8s Secret (cluster 안에서 사용)
kubectl get secret payments-db-app -n payments -o jsonpath='{.data}' | jq 'map_values(@base64d)'
# {
#   "username": "app",
#   "password": "auto-generated-32-char",
#   "dbname":   "app",
#   "host":     "payments-db-rw.payments.svc.cluster.local",
#   "port":     "5432",
#   "uri":      "postgresql://app:...@payments-db-rw.payments.svc.cluster.local:5432/app"
# }

# 방법 2: Vault (운영자가 ad-hoc 으로 사용)
rbcn secret get secret/services/payments/db
```

> **`*-rw`** = read-write endpoint (primary). **`*-ro`** = read-only endpoint (replicas, load-balanced).

---

## 4. 앱에서 연결하기

### 4.1 자동 주입 (권장)

manifests repo 의 `base/deployment.yaml` 에서:

```yaml
spec:
  template:
    spec:
      containers:
        - name: app
          envFrom:
            - secretRef: { name: payments-db-app }   # ← CNPG 가 만든 secret
```

→ Pod 안에서 `process.env.URI` 또는 `os.Getenv("URI")` 로 사용.

### 4.2 ExternalSecret 으로 통합 (다른 시크릿과 함께)

```yaml
# manifests repo: base/externalsecret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata: { name: payments }
spec:
  refreshInterval: 30s
  secretStoreRef: { name: vault-backend, kind: ClusterSecretStore }
  target: { name: payments }
  data:
    - secretKey: DB_URL
      remoteRef: { key: services/payments/db, property: uri }
    - secretKey: STRIPE_KEY
      remoteRef: { key: services/payments, property: STRIPE_KEY }
```

---

## 5. psql 로 직접 접속 (디버깅)

```bash
# 운영자/개발자 ad-hoc
kubectl exec -it -n payments payments-db-1 -- psql -U postgres
```

또는 본인 노트북에서 (port-forward):

```bash
kubectl port-forward -n payments svc/payments-db-rw 5432:5432
# (다른 터미널)
PGPASSWORD=$(kubectl get secret payments-db-app -n payments -o jsonpath='{.data.password}' | base64 -d) \
  psql -h localhost -U app -d app
```

---

## 6. 마이그레이션 / 스키마 관리

DB 자체는 우리가 관리하고, **스키마는 앱 repo 에서** 관리합니다.

권장 도구 (택 1):
- Go: [`golang-migrate/migrate`](https://github.com/golang-migrate/migrate) → `migrations/0001_init.up.sql`
- Node: [`Prisma`](https://www.prisma.io/) → `prisma/migrations/`
- Python: [`Alembic`](https://alembic.sqlalchemy.org/)

CI 에서 자동 마이그레이션 (예시):

```yaml
# .github/workflows/migrate.yml (앱 repo)
name: db-migrate
on: { workflow_dispatch: }
jobs:
  migrate:
    uses: rebellions-sw/.github/.github/workflows/reusable-db-migrate.yaml@main
    with:
      service: payments
      env: dev
    secrets: inherit
```

> reusable-db-migrate 는 K8s `Job` 을 띄워 `migrate up` 을 실행 (한번만 실행, 동시 충돌 lock).

---

## 7. 백업 / 복구

### 7.1 백업 보기

```bash
kubectl get backup -n payments
# NAME                       AGE   CLUSTER       PHASE       ERROR
# payments-db-20260419-base  9h    payments-db   completed
# payments-db-20260420-base  1h    payments-db   completed

rbcn backup ls payments                          # rbcn wrapper (CNPG + Velero 통합)
```

### 7.2 복구 (시점 복구 PITR)

```bash
# 예: 30분 전으로 되돌리기 (새 클러스터로 복구 → swap)
rbcn restore payments-db --to '2026-04-19T14:30:00Z'
# 자동으로 새 cluster 'payments-db-restored' 생성 후 검증 → swap 여부는 사용자 confirm
```

자세한 절차: [`runbooks/db-pitr.md`](../runbooks/db-pitr.md).

### 7.3 즉시 백업 (수동)

```bash
rbcn backup now payments                          # Velero + CNPG full backup
```

---

## 8. 메트릭 / SLO

자동으로 Prometheus scrape:

```bash
rbcn url grafana
# Dashboards > "PostgreSQL CNPG"
# - Connections, TPS, lag, replication slot, WAL size
```

알림 규칙 (자동 적용):
- replica lag > 30s
- connection pool > 80%
- WAL archive 실패
- backup 실패

---

## 9. 자주 하는 작업

### 9.1 instance 수 변경

```bash
kubectl edit cluster payments-db -n payments
# spec.instances: 3 → 5
```

CNPG 가 1 by 1 으로 추가/제거.

### 9.2 storage 확장

```bash
kubectl patch cluster payments-db -n payments --type merge \
  -p '{"spec":{"storage":{"size":"50Gi"}}}'
```

CSI 가 PVC online resize.

### 9.3 user 추가 (read-only analyst)

```bash
kubectl exec -it -n payments payments-db-1 -- psql -U postgres -c \
  "CREATE USER analyst WITH PASSWORD 'xxxx'; GRANT pg_read_all_data TO analyst;"
```

> Production 에서는 password 를 Vault 로 넣고 ESO 로 sync 권장.

---

## 10. 비용 / cleanup

dev 클러스터에서 더 이상 안 쓰면 즉시 제거:

```bash
kubectl delete cluster payments-db -n payments
# WAL/backup 은 MinIO 에 보존 (수동 cleanup: rbcn backup prune payments-db --older-than=30d)
```

---

## 11. 다음 가이드

- [`api-service.md`](./api-service.md) — DB 와 연결되는 API
- [`cache-service.md`](./cache-service.md) — Redis HA
- [`../runbooks/db-pitr.md`](../runbooks/db-pitr.md) — 시점 복구
- [`../operators/cloudnative-pg/`](../operators/cloudnative-pg/) — CNPG 운영자 docs

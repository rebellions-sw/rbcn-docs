# DR Runbook 05 — Postgres PITR (Point-in-Time Recovery)

**Tier**: T1 (Important)
**RTO**: 1시간
**RPO**: 5분 (WAL streaming)
**Owner**: demo-team / Platform team

---

## 시나리오

Postgres 에 잘못된 DELETE/UPDATE/DROP 가 적용되어 특정 시점 (예: 30분 전) 으로 되돌려야 함.

---

## 사전 확인

```bash
KUBECONFIG=~/.kube/config-dev kubectl -n demo-db get pod -l app=demo-postgres
KUBECONFIG=~/.kube/config-dev kubectl -n demo-db exec demo-postgres-0 -- pg_basebackup --version
```

---

## 복구 절차 (간이)

> ⚠️ **데이터 손실 가능**: 복구 시점 이후 모든 변경이 사라집니다. **운영진과 합의 필수**.

### Step 1. App stop (write 차단)

```bash
KUBECONFIG=~/.kube/config-dev kubectl -n demo scale deploy/demo-db-api --replicas=0
KUBECONFIG=~/.kube/config-dev kubectl -n demo scale deploy/demo-api --replicas=0
```

### Step 2. Postgres backup 확인

```bash
KUBECONFIG=~/.kube/config-dev kubectl -n demo-db exec demo-postgres-0 -- ls -lh /backup/wal/ | tail -10
```

### Step 3. Restore (간이 — 1시간 전으로)

```bash
TARGET="2026-04-19 11:30:00 UTC"
KUBECONFIG=~/.kube/config-dev kubectl -n demo-db exec demo-postgres-0 -- bash -c "
    pg_ctl stop -D /var/lib/postgresql/data
    rm -rf /var/lib/postgresql/data/*
    pg_basebackup -D /var/lib/postgresql/data -h backup-archive -U replicator
    cat > /var/lib/postgresql/data/recovery.signal <<EOF
recovery_target_time = '$TARGET'
recovery_target_action = 'promote'
EOF
    pg_ctl start -D /var/lib/postgresql/data
"
```

### Step 4. App restart + 검증

```bash
KUBECONFIG=~/.kube/config-dev kubectl -n demo scale deploy/demo-db-api --replicas=2
KUBECONFIG=~/.kube/config-dev kubectl -n demo scale deploy/demo-api --replicas=2
sleep 30
rbcn diag demo-db-api
```

### Step 5. 데이터 검증

```bash
KUBECONFIG=~/.kube/config-dev kubectl -n demo-db exec demo-postgres-0 -- psql -U demo -c 'SELECT count(*) FROM users; SELECT max(created_at) FROM events;'
```

---

## 사전 예방

- Velero 의 PVC snapshot (daily) 으로 fallback 가능 (단, RPO 24h)
- Postgres operator 를 도입하면 PITR 자동화 가능 (CloudNativePG, Zalando 등)
- 백업/복구 주기적 drill 권장 (분기)

---

## 참고

- PostgreSQL 공식: https://www.postgresql.org/docs/current/continuous-archiving.html
- demo-postgres 매니페스트: `github.com/rebellions-sw/rbcn-demo-db-api-manifests`
- Velero PVC snapshot: `dr-runbook/03-velero-full-restore.md` (전체 복원)

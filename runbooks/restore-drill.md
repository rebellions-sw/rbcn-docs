# Backup Restore Drill — 분기별 검증

> "백업이 있다 ≠ 복구가 된다." 분기 1회 모든 종류의 백업이 진짜 restore 되는지 측정.

---

## 1. 일정

| 주기 | 분기 1회, GameDay 와 같은 화요일 |
| 시간 | 16:00~18:00 KST (GameDay 이후) |
| 환경 | dev 클러스터 (별도 namespace 'restore-drill') |

---

## 2. 검증 대상 (4종)

| # | 백업 종류 | 도구 | 시나리오 |
|---|----------|------|---------|
| 1 | etcd snapshot | etcdctl | snapshot → 새 etcd 인스턴스 → 데이터 동일 확인 |
| 2 | Velero (namespace) | velero CLI | prod 의 demo-api ns → restore-drill ns 로 복구 |
| 3 | CNPG WAL (PITR) | CNPG | demo-db 를 30분 전 시점으로 복구 |
| 4 | MinIO bucket | mc mirror | minio-1 → minio-restore-drill 로 mirror 검증 |

---

## 3. 절차

### 3.1 etcd snapshot

```bash
# 1) 가장 최신 snapshot
ssh rbcn@<dev-cp-1> "ls -lh /var/backups/etcd/ | tail -3"

# 2) 임시 디렉토리에서 etcdctl snapshot status
ssh rbcn@<dev-cp-1> "ETCDCTL_API=3 etcdctl --write-out=table snapshot status /var/backups/etcd/snapshot-LATEST.db"
# → 응답에 hash, total-key 표시되면 정상

# 3) 신규 etcd binary 로 restore (실제 cluster 영향 0)
mkdir /tmp/etcd-drill
ssh rbcn@<dev-cp-1> "ETCDCTL_API=3 etcdctl snapshot restore /var/backups/etcd/snapshot-LATEST.db --data-dir=/tmp/etcd-drill"
# → /tmp/etcd-drill/member 폴더 생성되면 OK
```

### 3.2 Velero namespace restore

```bash
# 1) 최근 backup 1개 골라
BACKUP=$(kubectl get backup -n velero --no-headers | sort -k4 -r | head -1 | awk '{print $1}')
echo "Backup: $BACKUP"

# 2) namespace mapping 으로 restore
velero restore create drill-${BACKUP} \
    --from-backup=$BACKUP \
    --namespace-mappings demo-api:restore-drill-demo-api

# 3) 진행 watch
velero restore describe drill-${BACKUP} -w

# 4) namespace 안 resource 비교
kubectl get all -n restore-drill-demo-api
# expected: 원본과 동일한 deployment / service 수

# 5) cleanup
kubectl delete ns restore-drill-demo-api
velero restore delete drill-${BACKUP}
```

### 3.3 CNPG PITR

```bash
# 1) 최근 시점 (1시간 전)
TARGET=$(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%SZ)
echo "Target: $TARGET"

# 2) restore (rbcn wrapper)
rbcn restore demo-db --to "$TARGET"
# → demo-db-restored-YYYY... cluster 생성

# 3) READY 까지 watch
kubectl get cluster -n demo -w
# 약 10~20분

# 4) 데이터 비교 (count rows)
ORIG=$(kubectl exec -n demo demo-db-1 -- psql -U postgres -tc "SELECT count(*) FROM transactions WHERE created_at < '$TARGET';" | xargs)
REST=$(kubectl exec -n demo demo-db-restored-XXX-1 -- psql -U postgres -tc "SELECT count(*) FROM transactions;" | xargs)
echo "원본 ($TARGET 시점) = $ORIG, 복구 = $REST"
# → 동일해야 OK

# 5) cleanup
kubectl delete cluster demo-db-restored-XXX -n demo
```

### 3.4 MinIO mirror

```bash
# 평소 mc 로 daily mirror 가 도는지 확인
mc ls minio-mirror/cnpg-wal/ | tail -5
# → 최신 폴더가 24h 안에 갱신되어야 OK

# drill: source bucket 의 size 와 mirror size 비교
SRC=$(mc du --json minio/cnpg-wal | jq -r .size)
MIR=$(mc du --json minio-mirror/cnpg-wal | jq -r .size)
echo "src=$SRC mir=$MIR diff=$((SRC-MIR))"
# diff < 5% 면 OK
```

---

## 4. 측정 지표

각 drill 은 다음 4 가지 시간 측정:

| 지표 | 목표 |
|------|------|
| Detection time (백업 누락 발견까지) | < 24h (cron 알림) |
| Restore start time (decide → start) | < 15min |
| Restore end time (start → ready) | per type: etcd 5min, velero 30min, CNPG 30min, MinIO N/A |
| Validation time (data correct?) | < 30min |

총 RTO 측정 → `STANDARDS.md` 의 RPO/RTO 표 갱신.

---

## 5. Action Items

drill 에서 발견된 문제는 24h 내 GitHub issue + P1 backlog:

```bash
gh issue create -R rebellions-sw/rbcn-docs \
  --title "[drill 2026-Q2] etcd restore fail: missing snapshot at <date>" \
  --label "P1,backup" \
  --body "..."
```

---

## 6. 관련 문서

- [`gameday.md`](./gameday.md)
- [`db-pitr.md`](./db-pitr.md)
- [`vault.md`](./vault.md)
- [`minio-velero.md`](./minio-velero.md)

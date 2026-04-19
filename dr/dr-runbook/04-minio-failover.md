# DR Runbook 04 — MinIO Failover (cross-bucket mirror)

**Tier**: T1 (Important)
**RTO**: 30분
**RPO**: 30분 (mirror 주기)
**Owner**: Platform team

---

## 시나리오

Primary MinIO bucket 손상 / 디스크 fail / 데이터 corruption.

---

## 사전 확인

```bash
mc admin info minio-primary
mc admin info minio-mirror
mc ls minio-mirror/velero-backups/ | tail -10        # 최근 mirror 시점 확인
```

---

## 복구 절차

### Step 1. Velero BSL (Backup Storage Location) 변경

```bash
KUBECONFIG=~/.kube/config-prod kubectl -n velero edit backupstoragelocation default
# spec.config.s3Url: http://minio-mirror.minio.svc.cluster.local:9000  ← 변경
```

또는 yaml 직접 적용:
```bash
KUBECONFIG=~/.kube/config-prod kubectl -n velero patch backupstoragelocation default --type merge -p '
spec:
  config:
    s3Url: http://minio-mirror.minio.svc.cluster.local:9000
'
```

### Step 2. Velero refresh

```bash
KUBECONFIG=~/.kube/config-prod kubectl -n velero rollout restart deploy/velero
sleep 30
KUBECONFIG=~/.kube/config-prod velero backup get | head
```

### Step 3. Primary 복구 후 mirror 방향 변경 (선택)

```bash
mc mirror --remove --watch minio-mirror/velero-backups minio-primary/velero-backups
```

---

## 사전 예방

- mc-mirror 30분 주기 cron (`/etc/cron.d/minio-mirror`)
- Prometheus alert: `minio_bucket_replication_lag_seconds > 1800`

---

## 참고

- MinIO 공식: https://min.io/docs/minio/linux/operations/data-recovery.html
- MinIO mirror 스크립트: `/opt/rbcn-infra-iac/k8s-helm-releases/minio-mirror.tf`

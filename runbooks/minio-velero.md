# MinIO + Velero Restore Runbook

**서비스**: 
- MinIO (S3-compatible, Velero backup target)
- Velero (K8s namespace/PVC backup → MinIO bucket)

**위치**:
- MinIO: 192.168.7.199 (backup-vm-01) — port 9000 (S3 API), 9001 (console)
- Velero: 3 클러스터 모두 deployed (`namespace: velero`)

**RPO**: 6시간 (Velero schedule)
**RTO**: 2시간 (single namespace), 6시간 (전체 cluster restore)

---

## 알림: VeleroBackupFailed / MinIODiskFull

### 즉시 확인

```bash
# 1) Velero backup 목록
KUBECONFIG=/root/.kube/config-prod velero backup get

# 2) 마지막 backup 상세
KUBECONFIG=/root/.kube/config-prod velero backup describe <backup-name> --details

# 3) MinIO 상태
ssh rbcn@192.168.7.199 "sudo mc admin info minio-local"

# 4) MinIO bucket 사용량
ssh rbcn@192.168.7.199 "sudo mc du minio-local/velero-prod"
```

### Backup schedule 재실행 (수동 트리거)

```bash
# 다음 schedule 안 기다리고 즉시 backup
KUBECONFIG=/root/.kube/config-prod velero backup create manual-$(date +%Y%m%d-%H%M) \
  --include-namespaces demo,demo-db \
  --wait
```

### Single namespace restore (예: demo-db 가 망가졌을 때)

```bash
# 1) 사용 가능한 backup 확인
KUBECONFIG=/root/.kube/config-prod velero backup get | grep demo-db

# 2) Restore (기존 ns drop 후)
KUBECONFIG=/root/.kube/config-prod kubectl delete ns demo-db
KUBECONFIG=/root/.kube/config-prod velero restore create demo-db-restore-$(date +%Y%m%d-%H%M) \
  --from-backup demo-db-daily-YYYYMMDD-HHMM \
  --include-namespaces demo-db \
  --restore-volumes \
  --wait

# 3) 검증
KUBECONFIG=/root/.kube/config-prod kubectl -n demo-db get pods,pvc,svc
```

### 전체 cluster restore (DR 시나리오)

```bash
# 1) 새 cluster 에 Velero 설치 (동일 backend MinIO 사용)
KUBECONFIG=/root/.kube/config-prod-NEW velero install \
  --provider aws \
  --plugins velero/velero-plugin-for-aws:v1.10.0 \
  --bucket velero-prod \
  --secret-file /tmp/credentials-velero \
  --backup-location-config region=local,s3ForcePathStyle=true,s3Url=http://192.168.7.199:9000

# 2) Backup 목록 검색
KUBECONFIG=/root/.kube/config-prod-NEW velero backup get

# 3) 최신 full backup restore
KUBECONFIG=/root/.kube/config-prod-NEW velero restore create cluster-full-restore-$(date +%Y%m%d) \
  --from-backup full-cluster-daily-YYYYMMDD-HHMM \
  --restore-volumes \
  --wait
```

### MinIO disk full 처리

```bash
# 1) 오래된 backup 삭제 (Velero retention)
KUBECONFIG=/root/.kube/config-prod velero backup get -o json \
  | jq -r '.items[] | select(.status.expiration | fromdate < now) | .metadata.name' \
  | xargs -I{} velero backup delete {} --confirm

# 2) MinIO bucket 직접 정리 (마지막 수단)
ssh rbcn@192.168.7.199 "sudo mc rm --recursive --force --older-than 30d minio-local/velero-prod/backups/"

# 3) 디스크 추가 (Proxmox)
# - VM 1919 에 추가 disk attach
# - LVM extend
```

### Escalation

- backup 24시간 fail → on-call 즉시 페이지 (RPO 위반)
- restore 실패 → DBA + lead engineer 함께 직접 데이터 복구


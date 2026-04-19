# DR Runbook Index

5개의 시나리오 별 복구 절차. 각 runbook 은 **15분-1시간** 안에 복구를 목표로 합니다.

| # | Runbook | Tier | RTO | RPO | 시나리오 |
|---|---|---|---|---|---|
| 01 | [etcd Restore](./01-etcd-restore.md) | T0 | 15분 | 6시간 | K8s API 다운, etcd quorum loss |
| 02 | [Vault Raft Restore](./02-vault-raft-restore.md) | T0 | 15분 | 1시간 | Vault unhealthy / 데이터 손상 |
| 03 | [Velero Full Restore](./03-velero-full-restore.md) | T1 | 1시간 | 24시간 | namespace/cluster 재구축 |
| 04 | [MinIO Failover](./04-minio-failover.md) | T1 | 30분 | 30분 | Primary MinIO bucket fail |
| 05 | [Postgres PITR](./05-pg-pitr.md) | T1 | 1시간 | 5분 | 잘못된 DB 변경 → 시점 복구 |

---

## 빠른 참조

| 증상 | Runbook | 첫 명령 |
|---|---|---|
| `kubectl` 모든 명령 timeout | 01 | `rbcn etcd health` |
| Vault sealed | 02 | `rbcn vault` |
| Pod 다 사라짐 | 03 | `rbcn backup ls` |
| Velero backup 실패 | 04 | `mc admin info minio-primary` |
| 잘못된 DB UPDATE | 05 | `rbcn diag demo-postgres` |

---

## 복구 명령 (1줄)

| 시나리오 | 명령 |
|---|---|
| Velero 즉시 백업 | `rbcn backup now <ns>` |
| Velero 복원 | `rbcn restore <backup-name>` |
| etcd 스냅샷 목록 | `rbcn backup ls` |
| Vault 상태 | `rbcn vault` |

---

## DR Drill 자동화

- **stage 클러스터**: 매월 1일 03:00 UTC 자동 실행 (Velero CronJob `dr-drill`)
- **결과 알림**: Slack `#alerts-dr` (또는 `kubectl -n velero get job`)
- **검증**: `bash /root/final_phase_for_full_stack_demo_infra/05_storage_backup/99-verify.sh`

---

## 더 보기

- [RTO/RPO 정의](../rto-rpo.md)
- [Postmortem 템플릿](../../postmortems/TEMPLATE.md)
- [Platform SOT](../../PLATFORM.md)

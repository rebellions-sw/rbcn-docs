# DR (Disaster Recovery) Index

| 문서 | 설명 |
|---|---|
| [RTO/RPO Targets](./rto-rpo.md) | SLA/SLO 정의 + 백업 매트릭스 + 시나리오별 절차 |
| [DR Runbook 인덱스](./dr-runbook/INDEX.md) | 5개 시나리오 별 복구 절차 |

## 빠른 참조

| 증상 | Runbook |
|---|---|
| K8s 다운 | [01-etcd-restore](./dr-runbook/01-etcd-restore.md) |
| Vault sealed | [02-vault-raft-restore](./dr-runbook/02-vault-raft-restore.md) |
| Pod 사라짐 | [03-velero-full-restore](./dr-runbook/03-velero-full-restore.md) |
| MinIO fail | [04-minio-failover](./dr-runbook/04-minio-failover.md) |
| DB 잘못 변경 | [05-pg-pitr](./dr-runbook/05-pg-pitr.md) |

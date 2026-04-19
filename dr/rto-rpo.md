# RTO / RPO Targets — Disaster Recovery Plan

> **Owner**: SRE/Platform team
> **Last reviewed**: 2026-04-19
> **Next review**: 2026-07-19 (분기별)
> **Tested by**: Velero CronJob `dr-drill` (매월 1일 stage 클러스터)

---

## 1. SLA / SLO 정의

### 1.1 Tier 별 분류

| Tier | 설명 | 예시 서비스 | RTO 목표 | RPO 목표 |
|---|---|---|---|---|
| **T0 — Critical** | 즉시 다운 시 비즈니스 중단 | Vault, Keycloak, Ingress, DNS, etcd | **15분** | **5분** |
| **T1 — Important** | 1시간 다운 가능, 데이터 손실 최소 | Postgres (prod), Redis (prod), Harbor | **1시간** | **15분** |
| **T2 — Standard** | 4시간 다운 가능, 일일 단위 복구 | Demo apps, GitOps repos, MkDocs | **4시간** | **1일** |
| **T3 — Best Effort** | 1일 다운 가능, 최선 복구 | Dev clusters, Goldilocks UI, OpenCost UI | **24시간** | **1주일** |

---

## 2. 백업 매트릭스

| 영역 | 빈도 | 보존 기간 | 저장 위치 | 검증 |
|---|---|---|---|---|
| **etcd snapshot (k8s)** | 6시간 | 7일 | CP node `/var/backups/etcd/` + BACKUP_VM rsync | weekly cron + size check |
| **Velero (k8s 리소스)** | daily | 30일 | MinIO `velero-backups` bucket | monthly DR drill (stage) |
| **Velero (PVC 스냅샷)** | daily | 30일 | MinIO `velero-backups` (Restic) | monthly DR drill |
| **Restic repository check** | weekly | n/a | k8s CronJob `restic-repo-check` | exit-code monitoring |
| **MinIO cross-bucket mirror** | 30분 | 90일 | MinIO `audit-logs-mirror` (DR copy) | object count diff |
| **Audit logs S3 archive** | 1시간 | **7년 (2555일)** | MinIO `audit-logs` (ILM rule) | weekly compliance report |
| **Postgres (Vault, Keycloak, NetBox)** | daily | 30일 | pg_dump → MinIO | DR drill restore test |
| **Vault Raft snapshot** | 6시간 | 30일 | Vault auto-snapshot → MinIO | weekly checksum |
| **NetBox state (TF)** | per-change | unlimited | Atlantis state lock + MinIO | drift detection daily |

---

## 3. 시나리오별 복구 절차

### 3.1 Single VM 장애 (Proxmox HA)
- **자동 복구**: Proxmox HA 가 다른 호스트로 VM live migration (~30초)
- **RTO 실측**: 30~60초 (HA Group 21개, fence agent 포함)
- **재현**: `8/01_proxmox_ha_setup.sh` 후 `qm shutdown <vmid>` → 다른 노드에서 자동 시작
- **검증**: `cd 8 && bash 99-verify.sh`

### 3.2 단일 etcd 노드 손실
- **수동 복구 RTO**: 30분 (snapshot restore + member 추가)
- **절차**:
  ```bash
  # 1. 손상된 멤버 제거
  ETCDCTL_API=3 etcdctl member remove <id>
  # 2. 새 노드에서 snapshot 복원
  scp rbcn@CP1:/var/backups/etcd/etcd-LATEST.db .
  ETCDCTL_API=3 etcdctl snapshot restore etcd-LATEST.db \
      --name=cp-3 --initial-cluster=... --initial-advertise-peer-urls=https://NEW_IP:2380
  # 3. etcd 시작 → kubeadm join
  ```

### 3.3 K8s 클러스터 전체 손실 (worst case)
- **RTO**: 4시간 (Velero full restore + 검증)
- **RPO**: 1일 (마지막 daily Velero backup)
- **절차**:
  1. Proxmox HA 로 VM 자체는 살아있어야 함
  2. kubeadm reset + 새 cluster init
  3. CNI / kube-prometheus-stack / Velero 재설치
  4. `velero restore create --from-backup daily-full-LATEST --wait`
  5. 검증: `bash 13/04-rbcn-cli.sh && rbcn pods`

### 3.4 MinIO (object storage) 장애
- **RPO**: 30분 (cross-bucket mirror)
- **자동**: prod cluster 의 `minio-cross-bucket-mirror` CronJob 이 30분마다 audit-logs 를 audit-logs-mirror 로 복제
- **RTO**: 15분 (mirror bucket 으로 client endpoint 전환)

### 3.5 Vault 장애
- **RTO**: 30분 (Raft snapshot restore)
- **RPO**: 6시간 (자동 snapshot 주기)
- **절차**: `vault operator raft snapshot restore /backup/vault-LATEST.snap`

### 3.6 데이터센터 전체 손실 (multi-region 외부 의존)
- **현재 상태**: ❌ 미지원 (단일 사이트)
- **요구사항**: 별도 DC + 광 회선 ($$$)
- **임시 대안**: BACKUP_VM (192.168.7.199) 의 etcd snapshot + Velero backup 을 외부 cold storage 에 보관

---

## 4. DR drill 자동화

### 4.1 월간 자동 drill (stage 클러스터)
- **CronJob**: `velero/dr-drill` schedule `0 5 1 * *` (매월 1일 05:00)
- **동작**:
  1. 가장 최근 Completed Velero backup 식별
  2. `demo` ns → `demo-dr-drill` ns 로 restore
  3. 60초 후 Pod Running 확인
  4. PASS 시 `demo-dr-drill` ns 삭제

### 4.2 분기별 수동 drill (prod-like)
- 시뮬레이션: prod 의 demo 앱을 stage 의 신규 ns 로 restore
- 측정 지표: 실 RTO (초), 데이터 일치율 (%)
- 결과 기록: `/var/log/dr-drill/YYYY-MM-DD.md` + Grafana panel

### 4.3 연간 game day
- 전체 SRE 팀 참여
- 시나리오 예: prod cluster 전체 손실, Vault 장애, MinIO 손실 동시 발생
- 평가: 실제 RTO/RPO vs 목표값, 절차 갭, runbook 갱신

---

## 5. 모니터링 / 알람 연동

| 메트릭 | 알람 임계값 | 액션 |
|---|---|---|
| `velero_backup_failure_total` | > 0 (24h) | PagerDuty 알람 |
| `etcd_snapshot_age_hours` | > 7 (CP node 단위) | Alertmanager warning |
| `minio_bucket_objects` (audit-logs) | drop > 10% (1h) | Critical alarm |
| `restic_repo_check` exit code | non-zero | Slack #infra |
| Vault auto-snapshot age | > 8h | Vault audit log 알람 |

---

## 6. 외부 의존 / 갭

| 항목 | 현재 | 목표 | 갭 / 비용 |
|---|---|---|---|
| Multi-region active-active | ❌ | DC 2개 | 회선 + 인프라 2배 ($$$) |
| 외부 cold storage (S3 Glacier) | ❌ | AWS S3 IA + Glacier | 월 ~$30 (TB 단위) |
| Cross-region etcd mirror | ❌ | 외부 DC 또는 cloud | DC 의존 |
| 외부 SOC2 Type II auditor | ❌ | 외부 감사 | 1회 $30k+ |

---

## 7. Runbook 인덱스

- `dr-runbook/01-etcd-restore.md` — etcd snapshot 복원
- `dr-runbook/02-vault-raft-restore.md` — Vault Raft snapshot 복원
- `dr-runbook/03-velero-full-restore.md` — Velero full restore
- `dr-runbook/04-minio-failover.md` — MinIO mirror bucket 전환
- `dr-runbook/05-pg-pitr.md` — Postgres PITR (point-in-time recovery)

---

## 8. 변경 이력

| 일자 | 변경 | 담당 |
|---|---|---|
| 2026-04-19 | 초안 작성 (Phase 05 보강) | SRE Platform |
| 2026-04-19 | etcd snapshot 6시간 자동화 추가 | SRE Platform |
| 2026-04-19 | DR drill CronJob (월간) PSS 호환 | SRE Platform |

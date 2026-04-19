# DR Runbook 03 — Velero Full Restore

**Tier**: T1 (Important)
**RTO**: 1시간
**RPO**: 24시간 (daily backup)
**Owner**: Platform team

---

## 시나리오

전체 namespace 가 손상되거나, 클러스터 전체 재구축 후 워크로드 복원.

---

## 사전 확인

```bash
rbcn backup ls
# 또는
KUBECONFIG=~/.kube/config-prod kubectl -n velero get backup --sort-by='.status.startTimestamp' | tail -10
```

---

## 복구 절차

### Step 1. 복원할 백업 선정

```bash
KUBECONFIG=~/.kube/config-prod velero backup describe <backup-name>
KUBECONFIG=~/.kube/config-prod velero backup logs <backup-name> | head -50
```

### Step 2. 충돌 방지 (기존 namespace 비우기)

```bash
NS=demo
KUBECONFIG=~/.kube/config-prod kubectl delete deploy,sts,svc,ingress -n $NS --all
# PVC 는 유지 (데이터 보존)
```

### Step 3. 복원

```bash
rbcn restore <backup-name>
# 내부적으로:
#   velero restore create restore-$(date +%s) --from-backup <backup-name>

KUBECONFIG=~/.kube/config-prod velero restore describe restore-...
```

### Step 4. 검증

```bash
KUBECONFIG=~/.kube/config-prod kubectl -n $NS get all
rbcn diag <pod-prefix>
curl -sf https://prod.infra.rblnconnect.ai/healthz
```

---

## 부분 복원

특정 리소스만:
```bash
velero restore create my-restore \
    --from-backup <backup-name> \
    --include-namespaces $NS \
    --include-resources deployments,services,configmaps
```

---

## 자동화 검증

매월 1일 stage 클러스터에서 dr-drill 자동 실행:
- `KUBECONFIG=~/.kube/config-stage kubectl -n velero get cronjob dr-drill`
- 결과: `KUBECONFIG=~/.kube/config-stage kubectl -n velero get job -l app=dr-drill`

---

## 참고

- Velero 공식: https://velero.io/docs/main/restore-reference/
- MinIO bucket: `velero-backups` (cross-bucket mirror 30분)
- 검증 스크립트: `/root/final_phase_for_full_stack_demo_infra/05_storage_backup/06-dr-drill-automation.sh`

# DR Runbook 01 — etcd Snapshot 복원

**Tier**: T0 (Critical)
**RTO**: 15분
**RPO**: 6시간 (snapshot 주기)
**Owner**: Platform team

---

## 시나리오

K8s API 가 응답 안 함 / etcd quorum loss / 잘못된 etcdctl write 발생.

---

## 사전 확인

```bash
# 1. 어떤 클러스터인가?
ENV=prod    # dev | stage | prod
CP_NODES=(rbcn-pve-cp-${ENV}-01 rbcn-pve-cp-${ENV}-02 rbcn-pve-cp-${ENV}-03)

# 2. 어느 snapshot 으로 돌릴 것인가?
ssh rbcn@${CP_NODES[0]} 'ls -lh /var/backups/etcd/ | tail -10'

# 3. Backup VM 에서도 확인 (offsite copy)
ssh rbcn@192.168.7.199 "ls -lh /backup/etcd/${ENV}/ | tail -10"
```

---

## 복구 절차

### Step 1. 모든 CP 노드 stop (kubelet + etcd)

```bash
for n in "${CP_NODES[@]}"; do
    ssh rbcn@$n 'sudo systemctl stop kubelet'
    ssh rbcn@$n 'sudo crictl ps --name etcd -q | xargs -r sudo crictl stop'
done
```

### Step 2. etcd data dir 백업 (실패 시 롤백 위해)

```bash
TS=$(date +%Y%m%d-%H%M%S)
for n in "${CP_NODES[@]}"; do
    ssh rbcn@$n "sudo mv /var/lib/etcd /var/lib/etcd.broken-$TS"
done
```

### Step 3. snapshot 복원 (각 CP 노드)

```bash
SNAPSHOT=etcd-snapshot-2026-04-19-12-00.db    # 선택한 snapshot
for n in "${CP_NODES[@]}"; do
    NAME=$(echo $n | sed 's/rbcn-pve-//')
    PEER=$(ssh rbcn@$n 'cat /etc/kubernetes/manifests/etcd.yaml | grep initial-advertise-peer-urls | head -1 | awk -F= "{print \$2}"')
    ssh rbcn@$n "sudo /usr/local/bin/etcdctl snapshot restore /var/backups/etcd/$SNAPSHOT \
        --name=$NAME \
        --initial-cluster=cp-01=$PEER1,cp-02=$PEER2,cp-03=$PEER3 \
        --initial-cluster-token=etcd-cluster-1 \
        --initial-advertise-peer-urls=$PEER \
        --data-dir=/var/lib/etcd"
done
```

### Step 4. kubelet 재시작 + 검증

```bash
for n in "${CP_NODES[@]}"; do
    ssh rbcn@$n 'sudo systemctl start kubelet'
done

sleep 30
KUBECONFIG=~/.kube/config-${ENV} kubectl get nodes
KUBECONFIG=~/.kube/config-${ENV} kubectl get pod -A | head
```

### Step 5. 데이터 정합성 확인

```bash
# ArgoCD 가 자동으로 sync 하면서 어플리케이션 복구
KUBECONFIG=~/.kube/config-${ENV} kubectl -n argocd get application

# 만약 OutOfSync 가 보이면 manual sync
rbcn sync <app-name>
```

---

## 롤백 (snapshot 복원이 실패한 경우)

```bash
for n in "${CP_NODES[@]}"; do
    ssh rbcn@$n "sudo systemctl stop kubelet && sudo rm -rf /var/lib/etcd && sudo mv /var/lib/etcd.broken-$TS /var/lib/etcd && sudo systemctl start kubelet"
done
```

---

## 사전 예방

- etcd snapshot cron 은 6시간 주기로 자동 (`/etc/cron.d/etcd-snapshot`)
- BACKUP_VM 으로 매일 rsync (다른 호스트에 offsite)
- DR drill 매월 stage 클러스터에서 자동 실행 (`dr-drill` Velero CronJob)

---

## 참고

- etcd 공식 docs: https://etcd.io/docs/v3.5/op-guide/recovery/
- Velero restore (다른 시나리오): `dr-runbook/03-velero-full-restore.md`
- 검증 스크립트: `/root/final_phase_for_full_stack_demo_infra/05_storage_backup/09-etcd-snapshot-cron.sh`

# K8s Control Plane Recovery Runbook

**서비스**: K8s CP (3 노드 stacked etcd) — dev/stage/prod 동일 구조
**노드**: 
- dev:   192.168.7.121/122/123
- stage: 192.168.7.131/132/133
- prod:  192.168.7.141/142/143

**VIP**: 171 (dev API), 173 (stage API), 175 (prod API)
**RPO**: 1시간 (etcd snapshot 시간당)
**RTO**: 2시간 (단일 노드 재입령), 4시간 (전체 cluster 재구축)

---

## 알림: KubeAPIDown / EtcdMemberDown

### 즉시 확인

```bash
# 1) 노드 상태 (master 노드에서 - kubeconfig 사용)
KUBECONFIG=/root/.kube/config-prod kubectl get nodes -o wide
KUBECONFIG=/root/.kube/config-prod kubectl get cs

# 2) etcd cluster 상태
KUBECONFIG=/root/.kube/config-prod kubectl -n kube-system exec etcd-rbcn-prod-k8scp-01 -- \
  etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  endpoint status --cluster --write-out=table

# 3) apiserver pod 직접 (cri)
ssh rbcn@<failed_cp_node> "sudo crictl pods --name kube-apiserver --no-trunc"
```

### 단일 CP 노드 장애 → kubelet 재시작 / 노드 재부팅

```bash
ssh rbcn@<failed_cp_node> "sudo systemctl restart kubelet"
# 또는 노드 재부팅
ssh rbcn@<failed_cp_node> "sudo reboot"
```

### Static pod (apiserver/controller-manager/scheduler) 강제 재시작

```bash
ssh rbcn@<failed_cp_node> '
POD_ID=$(sudo crictl pods --name kube-apiserver -q | head -1)
sudo crictl rmp -f $POD_ID
# kubelet 이 manifest 다시 읽어 60초 안에 새 pod 생성
'
```

### etcd 멤버 1대 영구 손실 → 멤버 제거 + 재가입

```bash
# 1) 살아있는 멤버에서 죽은 멤버 ID 확인 후 제거
ETCD_POD=etcd-rbcn-prod-k8scp-01
KUBECONFIG=/root/.kube/config-prod kubectl -n kube-system exec ${ETCD_POD} -- \
  etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  member remove <DEAD_MEMBER_ID>

# 2) 새 노드 (또는 재설치한 동일 노드) 에서 kubeadm reset
ssh rbcn@<dead_node> "sudo kubeadm reset --force"
ssh rbcn@<dead_node> "sudo rm -rf /etc/kubernetes /var/lib/etcd"

# 3) join (workspace VM 에서 토큰 생성)
NEW_TOKEN=$(KUBECONFIG=/root/.kube/config-prod kubeadm token create --print-join-command)
CERT_KEY=$(KUBECONFIG=/root/.kube/config-prod kubeadm init phase upload-certs --upload-certs | tail -1)
ssh rbcn@<new_node> "sudo ${NEW_TOKEN} --control-plane --certificate-key ${CERT_KEY}"
```

### Cluster 전체 장애 → etcd snapshot restore

```bash
# 1) 최신 snapshot
ssh rbcn@192.168.7.199 "ls -la /backup/etcd/prod/ | tail -5"

# 2) 모든 CP 노드 stop
for n in 141 142 143; do
  ssh rbcn@192.168.7.${n} "sudo systemctl stop kubelet"
  ssh rbcn@192.168.7.${n} "sudo crictl ps -q | xargs -r sudo crictl rm -f"
done

# 3) 첫 번째 노드에 snapshot restore
SNAPSHOT=/backup/etcd/prod/etcd-snapshot-YYYYMMDD-HHMM.db
scp rbcn@192.168.7.199:${SNAPSHOT} /tmp/
ssh rbcn@192.168.7.141 'sudo etcdutl snapshot restore /tmp/etcd-snapshot-*.db \
  --data-dir=/var/lib/etcd \
  --name=rbcn-prod-k8scp-01 \
  --initial-cluster=rbcn-prod-k8scp-01=https://192.168.7.141:2380 \
  --initial-advertise-peer-urls=https://192.168.7.141:2380'
ssh rbcn@192.168.7.141 "sudo systemctl start kubelet"
sleep 60

# 4) 다른 두 노드는 새 멤버로 join (member add 후 join 절차)
```

### Escalation

- API down 1시간 → 모든 deploy/promotion 중단 (CI/CD 일시정지)
- 2시간 미해결 → CTO + 비상 점검 (cluster 단일 장애 사례 분석)


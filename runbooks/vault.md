# Vault HA Cluster Runbook

**서비스**: Vault HA (3 노드 cluster, integrated storage Raft)
**노드**: 192.168.7.161 (vault-vm-01), 162 (vm-02), 163 (vm-03)
**VIP**: 192.168.7.153 (keepalived, active 노드 한 대)
**도메인**: https://vault.infra.rblnconnect.ai
**RPO**: 5분 (Raft snapshot 5분 주기)
**RTO**: 30분 (단일 노드 장애), 2시간 (cluster 전체)

---

## 알림: VaultDown / VaultSealed

### 즉시 확인 (5분 이내)

```bash
# 1) Cluster 상태
for n in 161 162 163; do
  echo "── 192.168.7.${n} ──"
  ssh rbcn@192.168.7.${n} "VAULT_ADDR=https://localhost:8200 vault status 2>&1 | grep -E 'Sealed|Active|HA Mode'"
done

# 2) keepalived VIP active node
ssh rbcn@192.168.7.161 "ip a show ens18 | grep 192.168.7.153"
ssh rbcn@192.168.7.162 "ip a show ens18 | grep 192.168.7.153"
ssh rbcn@192.168.7.163 "ip a show ens18 | grep 192.168.7.153"

# 3) Vault 로그 (마지막 50줄)
ssh rbcn@<failed_node> "sudo journalctl -u vault -n 50 --no-pager"
```

### 단일 노드 장애 복구

```bash
# 1) 노드 재시작
ssh rbcn@<failed_node> "sudo systemctl restart vault"
sleep 10

# 2) Sealed 상태면 unseal (3 keys 필요, /root/.vault/vault-init.json 참고)
ssh rbcn@<failed_node> "VAULT_ADDR=https://localhost:8200 vault operator unseal <KEY1>"
ssh rbcn@<failed_node> "VAULT_ADDR=https://localhost:8200 vault operator unseal <KEY2>"
ssh rbcn@<failed_node> "VAULT_ADDR=https://localhost:8200 vault operator unseal <KEY3>"

# 3) Cluster 재합류 확인
ssh rbcn@<failed_node> "VAULT_ADDR=https://localhost:8200 vault operator raft list-peers"
```

### Cluster 전체 장애 → Raft snapshot 복구

```bash
# 1) 가장 최신 snapshot 찾기 (BACKUP_VM 192.168.7.199)
ssh rbcn@192.168.7.199 "ls -la /backup/vault/snapshots/ | tail -5"

# 2) 신규 leader 노드에 복원 (예: 161)
scp rbcn@192.168.7.199:/backup/vault/snapshots/vault-snapshot-YYYYMMDD-HHMM.snap /tmp/
ssh rbcn@192.168.7.161 "sudo systemctl stop vault"
ssh rbcn@192.168.7.161 "sudo rm -rf /opt/vault/data/raft/*"
ssh rbcn@192.168.7.161 "sudo systemctl start vault"
sleep 10
ssh rbcn@192.168.7.161 "vault operator raft snapshot restore -force /tmp/vault-snapshot-*.snap"

# 3) Unseal + 다른 노드들 raft join
# (자세한 절차는 https://developer.hashicorp.com/vault/docs/concepts/integrated-storage)
```

### Escalation

- 30분 이내 미해결 → on-call (`secret/oncall/rotation`)
- 2시간 이내 미해결 → CTO 페이지 + statuspage.io 업데이트


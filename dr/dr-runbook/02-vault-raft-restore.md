# DR Runbook 02 — Vault Raft Snapshot 복원

**Tier**: T0 (Critical)
**RTO**: 15분
**RPO**: 1시간
**Owner**: Platform team

---

## 시나리오

Vault 가 sealed/unhealthy 상태에서 데이터 손상 또는 잘못된 변경 발생.

---

## 사전 확인

```bash
rbcn vault                       # 현재 상태
ls -lh /backup/vault/            # snapshot 위치 (BACKUP_VM)
```

---

## 복구 절차

### Step 1. Vault snapshot 보유 확인

Vault 는 매시간 snapshot 자동 생성 (Vault Operator + Raft engine):
```bash
ssh rbcn@192.168.7.199 'ls -lh /backup/vault/ | tail -10'
```

### Step 2. Vault stop

```bash
ssh rbcn@vault.infra.rblnconnect.ai 'sudo systemctl stop vault'
```

### Step 3. Snapshot 복원

```bash
SNAPSHOT=vault-2026-04-19-12.snap
scp 192.168.7.199:/backup/vault/$SNAPSHOT vault.infra.rblnconnect.ai:/tmp/
ssh rbcn@vault.infra.rblnconnect.ai "
    sudo systemctl start vault
    export VAULT_ADDR=https://localhost:8200
    vault operator unseal <key1>
    vault operator unseal <key2>
    vault operator unseal <key3>
    vault operator raft snapshot restore -force /tmp/$SNAPSHOT
"
```

### Step 4. 검증

```bash
rbcn vault
vault kv get secret/services/demo-api    # known good secret
```

---

## 자동화

매시간 snapshot 은 `/etc/cron.d/vault-snapshot` 에서 자동:
```cron
0 * * * * vault vault operator raft snapshot save /backup/vault/vault-$(date +%F-%H).snap
```

---

## 참고

- HashiCorp 공식: https://developer.hashicorp.com/vault/tutorials/raft/raft-storage
- Vault unseal keys: 5명 운영자에게 분산 보관 (Shamir 5/3)

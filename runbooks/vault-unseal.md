# Vault Unseal Runbook

> Vault 가 sealed 상태가 되면 모든 시크릿 read 가 막힙니다.
> 본 runbook 은 [`vault.md`](./vault.md) 의 unseal 섹션을 발췌·요약한 신입용 가이드입니다.

---

## 0. 빠른 진단

```bash
rbcn vault                      # sealed=true / false 한 줄
# 또는
ssh rbcn@192.168.7.161 "VAULT_ADDR=https://localhost:8200 vault status | grep -E 'Sealed|Active'"
```

`Sealed: true` 면 unseal 필요.

## 1. Unseal 실행 (3 keys 필요)

unseal key 보유자 5명 중 3명이 모여야 합니다.

```bash
ssh rbcn@192.168.7.161 "VAULT_ADDR=https://localhost:8200 vault operator unseal <KEY1>"
ssh rbcn@192.168.7.161 "VAULT_ADDR=https://localhost:8200 vault operator unseal <KEY2>"
ssh rbcn@192.168.7.161 "VAULT_ADDR=https://localhost:8200 vault operator unseal <KEY3>"

# 다른 노드들도 동일하게 (162, 163)
```

각 unseal key 는 보유자가 1Password / yubikey / 종이봉투 중 한 곳에 따로 보관.

## 2. 클러스터 재합류 확인

```bash
ssh rbcn@192.168.7.161 "VAULT_ADDR=https://localhost:8200 vault operator raft list-peers"
# Voter 3개 모두 alive 여야 정상
```

## 3. 자동 unseal 도입 검토

수동 3명 모임이 자주 일어난다면 [Auto-Unseal with KMS](https://developer.hashicorp.com/vault/docs/configuration/seal/awskms) 도입 검토.
현재는 air-gap 환경이라 미적용.

## 4. 더 자세히

- [`vault.md`](./vault.md) — Vault HA 전체 운영 (raft snapshot 복구 포함)
- [HashiCorp Vault docs](https://developer.hashicorp.com/vault/docs/concepts/seal)

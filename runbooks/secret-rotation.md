# Secret Rotation Runbook

> 정기적으로 회전해야 하는 시크릿 목록과 절차.
> **원칙**: 모든 시크릿은 Vault 가 source of truth → ESO/`rbcn secret sync-gh` 가 다른 시스템으로 전파.

---

## 0. 회전 주기 (정책)

| 항목 | 주기 | 우선순위 | 자동 알림 |
|------|------|----------|-----------|
| `MANIFESTS_PAT` (GitHub PAT) | 90일 | P1 | 만료 7일 전 PagerDuty + `#alerts-platform` (TODO: 알림 미적용) |
| `HARBOR_USER` / `HARBOR_PASS` | 180일 | P2 | Harbor admin UI 알림 |
| `COSIGN_KEY` / `COSIGN_PASSWORD` | 365일 | P3 | 만료 30일 전 |
| Vault root token (재발급 정책) | 부재 (revoke-only) | — | 사용 시점에만 |
| `keycloak-admin` | 90일 | P1 | Keycloak audit log |
| `etcd encryption key` | 365일 | P2 | calendar 등록 |
| Service DB password (CNPG 자동) | 30일 | P3 | CNPG 자동 회전 (앱 reload 필요 시 reloader annotation) |

---

## 1. GitHub PAT (MANIFESTS_PAT) 회전 — 가장 자주 함

### 1.1 새 PAT 생성

GitHub > Settings > Developer settings > Personal Access Tokens (Classic)
- name: `rbcn-bot manifests <YYYY-MM-DD>`
- expiration: 90일
- scopes: `repo`, `workflow`, `admin:org`

생성된 토큰은 한번만 보임. 복사.

### 1.2 Vault 에 저장

```bash
vault kv put secret/github \
    token=<NEW-PAT> \
    username=rbcn-bot \
    webhook_secret=<existing-webhook-secret>
```

(`webhook_secret` 은 기존 값 유지. `vault kv get secret/github` 으로 미리 확인.)

### 1.3 GitHub Org Secret + ArgoCD repo-creds 일괄 sync

```bash
rbcn secret sync-gh
# → 5개 secret (HARBOR_USER, HARBOR_PASS, COSIGN_KEY, COSIGN_PASSWORD, MANIFESTS_PAT) 모두 sync
# → validation 자동 (placeholder 거부, 길이 < 30 거부)
```

ArgoCD repo-creds 도 같이:

```bash
kubectl -n argocd patch secret github-rebellions-sw-creds \
    -p "{\"stringData\":{\"password\":\"$(vault kv get -field=token secret/github)\"}}"
```

### 1.4 검증

```bash
# CI 새 trigger 가 잘 되나
gh workflow run ci.yml -R rebellions-sw/example-payments
gh run watch -R rebellions-sw/example-payments
# bump-dev-manifest job 의 checkout 단계 GREEN 이어야 함

# ArgoCD 가 manifests repo 잘 읽나
rbcn sync example-payments-dev
```

### 1.5 옛 PAT revoke

새것이 잘 작동 확인된 후, GitHub > PAT 페이지에서 옛 PAT delete.

---

## 2. Harbor 자격증명 회전

```bash
# 1) Harbor UI > Administration > Users > rbcn-bot > 비밀번호 변경
# 2) Vault 업데이트
vault kv put secret/harbor/admin username=rbcn-bot password=<new-password>
# 3) GitHub org secret + cluster pull secret sync
rbcn secret sync-gh
# 4) 모든 ns 의 imagePullSecret refresh (Kyverno policy 자동, 1분 이내)
```

---

## 3. Cosign 키 회전 (1년 주기)

서명된 이미지를 깨지 않으려면 신중히. 보통 **새 키로 새 이미지부터 서명** + **기존 키는 retire** 패턴:

```bash
# 1) 새 키 페어 생성
COSIGN_PASSWORD=<new-pwd> cosign generate-key-pair --output-key-prefix=cosign-2027

# 2) Vault 에 저장
vault kv put secret/cosign \
    key="$(cat cosign-2027.key)" \
    password=<new-pwd> \
    pub="$(cat cosign-2027.pub)"

# 3) 새 키로 GH org secret sync
rbcn secret sync-gh

# 4) cluster 의 cosign verifier policy 에 새 pub 키 추가 (옛 키도 당분간 유지)
kubectl edit policy cosign-verify -n kyverno
```

옛 이미지는 옛 키로, 새 이미지는 새 키로 verify 가능. 6개월 후 옛 키 제거.

---

## 4. Service DB password (CNPG 자동)

CNPG operator 가 자동 회전. 앱은 reloader annotation 이 있으면 자동 재시작.

수동 강제 회전:

```bash
kubectl annotate cluster <db-name> -n <ns> \
    cnpg.io/reloadAt="$(date -u +%Y-%m-%dT%H:%M:%SZ)" --overwrite
```

---

## 5. 더 자세히

- [`vault.md`](./vault.md) — Vault 운영 전체
- [`vault-unseal.md`](./vault-unseal.md) — Vault sealed 복구
- [HashiCorp Vault Secret Rotation](https://developer.hashicorp.com/vault/docs/secrets)

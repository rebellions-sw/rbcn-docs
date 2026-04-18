# Incident Post-mortem Repository

이 디렉토리는 모든 인시던트 사후분석(post-mortem)을 보관합니다.

## 디렉토리 구조

```
postmortems/
├── README.md           ← 이 파일
├── TEMPLATE.md         ← 표준 템플릿
├── INDEX.md            ← 자동생성 (update-index.sh)
├── new-postmortem.sh   ← 새 PM 생성 헬퍼
├── update-index.sh     ← INDEX.md 갱신
├── backup-to-vault.sh  ← Vault 백업
├── 2026/
│   └── 2026-04-19-chaos-mesh-webhook-blocked.md
└── 2027/
```

## 새 Post-mortem 생성

```bash
cd /opt/rbcn-docs/postmortems
./new-postmortem.sh <slug> <severity> <category>
# 예시:
./new-postmortem.sh harbor-tls-expiry P2 security
```

## 작성 원칙

1. **Blameless** — 사람을 비난하지 않고 시스템/프로세스 개선에 집중
2. **24h 룰** — P1 인시던트는 24시간 내 Draft, 7일 내 Finalized
3. **Action item** — 모든 항목은 owner, due date, tracking issue 필수
4. **References** — Grafana/Loki 링크는 timestamp 고정 (영구 보존)

## Vault 백업

모든 finalized PM 은 `secret/postmortems/<id>` 에 base64 백업됩니다.
저장소 손실 시 복원:

```bash
vault kv get -field=content secret/postmortems/PM-YYYY-MM-DD-slug | base64 -d > restored.md
```

## Severity 정의

| Severity | 정의 | 대응 시간 |
|----------|------|-----------|
| **P1** | 전사 영향 / 데이터 손실 / 보안 침해 | 즉시 (24/7) |
| **P2** | 단일 서비스 다운 / 성능 심각 저하 | 1시간 내 |
| **P3** | Degraded but functional / cosmetic | 영업일 4시간 내 |

## Category 정의

| Category | 예시 |
|----------|------|
| **infra** | Proxmox 노드 down, 디스크 fail |
| **k8s** | etcd 손상, CP 응답 없음 |
| **network** | Calico, NetworkPolicy, DNS |
| **security** | TLS 만료, 인증 우회, SSRF |
| **data** | DB corruption, backup 실패 |
| **app** | demo-nextjs OOM, deploy 회귀 |
| **human** | 잘못된 명령, config drift |

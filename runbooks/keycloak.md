# Keycloak HA + DB Runbook

**서비스**: Keycloak 26.x HA (3 노드) + 외부 PostgreSQL
**노드**: 167/168/169 (keycloak-vm-01..03), 170 (keycloak-db-vm-01)
**VIP**: 192.168.7.165/166 (Ingress VM HA proxy 뒤)
**도메인**: https://keycloak.infra.rblnconnect.ai
**RPO**: 15분 (PostgreSQL pg_basebackup 15분, WAL stream)
**RTO**: 1시간

---

## 알림: KeycloakDown / KeycloakDBDown

### 즉시 확인

```bash
# 1) Keycloak pod 3 노드
for n in 167 168 169; do
  echo "── 192.168.7.${n} ──"
  ssh rbcn@192.168.7.${n} "sudo systemctl is-active keycloak; sudo journalctl -u keycloak -n 10 --no-pager"
done

# 2) Health check
curl -sk https://keycloak.infra.rblnconnect.ai/health/ready | jq '.'

# 3) DB 연결
ssh rbcn@192.168.7.170 "sudo systemctl is-active postgresql; sudo -u postgres psql -c 'SELECT version();'"
```

### 단일 노드 장애

```bash
# 1) 노드 재시작 (Keycloak 만)
ssh rbcn@<failed_node> "sudo systemctl restart keycloak"

# 2) Ingress VM 에서 health check 통과 후 자동 합류
# 192.168.7.165/166 의 nginx upstream 에 자동 추가됨
```

### DB 장애 → 백업 복구

```bash
# 1) 최신 backup
ssh rbcn@192.168.7.199 "ls -la /backup/keycloak-db/ | tail -5"

# 2) 복구 (PostgreSQL 17)
ssh rbcn@192.168.7.170 "sudo systemctl stop postgresql"
ssh rbcn@192.168.7.170 "sudo -u postgres pg_restore -d keycloak /backup/keycloak-db/keycloak-YYYYMMDD.dump"
ssh rbcn@192.168.7.170 "sudo systemctl start postgresql"

# 3) Keycloak 노드들 재시작
for n in 167 168 169; do
  ssh rbcn@192.168.7.${n} "sudo systemctl restart keycloak"
done
```

### Escalation

- 30분 미해결 → on-call
- DB 데이터 손실 의심 → DBA 페이지 + 즉시 read-only 모드 전환


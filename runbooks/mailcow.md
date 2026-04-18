# Mailcow (Docker stack) Runbook

**서비스**: Mailcow Dockerized (Postfix, Dovecot, SOGo, ClamAV, Rspamd, Nginx)
**노드**: 192.168.7.185 (mail-vm-01)
**도메인**: https://mail.infra.rblnconnect.ai (admin), https://autodiscover.infra.rblnconnect.ai
**RPO**: 24시간 (메일 데이터 일일 백업)
**RTO**: 1시간

---

## 알림: MailcowDown / SmtpAuthFail / DiskFull

### 즉시 확인

```bash
# 1) Docker 컨테이너 상태
ssh rbcn@192.168.7.185 "cd /opt/mailcow-dockerized && sudo docker compose ps"

# 2) 디스크
ssh rbcn@192.168.7.185 "df -h /var/lib/docker /opt/mailcow-dockerized"

# 3) Postfix 로그
ssh rbcn@192.168.7.185 "sudo docker logs mailcowdockerized-postfix-mailcow-1 --tail=50 2>&1 | grep -iE 'error|reject|defer'"

# 4) 큐
ssh rbcn@192.168.7.185 "sudo docker exec mailcowdockerized-postfix-mailcow-1 mailq | tail -20"
```

### 단일 컨테이너 재시작

```bash
ssh rbcn@192.168.7.185 "cd /opt/mailcow-dockerized && sudo docker compose restart <container_name>"

# 예: SMTP 만 재시작
ssh rbcn@192.168.7.185 "cd /opt/mailcow-dockerized && sudo docker compose restart postfix-mailcow"
```

### 전체 stack 재시작

```bash
ssh rbcn@192.168.7.185 "cd /opt/mailcow-dockerized && sudo docker compose down && sleep 5 && sudo docker compose up -d"
```

### 메일 데이터 복구 (vmail)

```bash
# 1) 최신 백업
ssh rbcn@192.168.7.199 "ls -la /backup/mailcow/ | tail -5"

# 2) Mailcow stop
ssh rbcn@192.168.7.185 "cd /opt/mailcow-dockerized && sudo docker compose down"

# 3) vmail 볼륨 복구
scp rbcn@192.168.7.199:/backup/mailcow/vmail-YYYYMMDD.tar.gz /tmp/
ssh rbcn@192.168.7.185 "sudo tar xzf /tmp/vmail-*.tar.gz -C /var/lib/docker/volumes/mailcowdockerized_vmail-vol-1/_data/"

# 4) MariaDB 복구
scp rbcn@192.168.7.199:/backup/mailcow/mysql-YYYYMMDD.sql.gz /tmp/
ssh rbcn@192.168.7.185 "cd /opt/mailcow-dockerized && sudo docker compose up -d mysql-mailcow"
sleep 10
ssh rbcn@192.168.7.185 "zcat /tmp/mysql-*.sql.gz | sudo docker exec -i mailcowdockerized-mysql-mailcow-1 mysql -u root mailcow"

# 5) 전체 start
ssh rbcn@192.168.7.185 "cd /opt/mailcow-dockerized && sudo docker compose up -d"
```

### Escalation

- 외부 발신 차단 시 (RBL/blocklist) → 즉시 IP reputation 확인 (mxtoolbox)
- 데이터 손실 의심 → CTO + GDPR 통보 절차 검토


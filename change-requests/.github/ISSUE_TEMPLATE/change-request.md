---
name: Change Request
about: 인프라/애플리케이션 변경 요청
title: "[CR-YYYYMMDD-NNN] 변경 제목"
labels: ["change-request"]
assignees: ""
---

## 1. 변경 개요

**유형**: [ ] Standard / [ ] Normal / [ ] Emergency

**변경 분류**: [ ] Infrastructure / [ ] Application / [ ] Configuration / [ ] Security / [ ] Database

**영향도**: [ ] None / [ ] Low / [ ] Medium / [ ] High / [ ] Critical

**예상 다운타임**: __ minutes

## 2. 변경 사유 (Why)

## 3. 변경 내용 (What)

## 4. 적용 절차 (How)

```bash
# Step 1
# Step 2
```

## 5. 영향 범위 (Impact)

- [ ] dev cluster
- [ ] stage cluster
- [ ] prod cluster
- [ ] Vault
- [ ] Keycloak
- [ ] DNS

## 6. Rollback 계획

```bash
# rollback steps
```

## 7. 검증 방법

## 8. 모니터링 / Alert

- 관련 Grafana dashboard:
- 관련 Alertmanager rule:

## 9. 승인 (Approvals)

- [ ] Tech Lead: @
- [ ] SRE Lead: @
- [ ] Security: @ (security-related 일 때)

## 10. 결과 (Post-change)

- 적용 시간:
- 결과: [ ] 성공 / [ ] 부분 성공 / [ ] 실패 + Rollback
- 학습 포인트:
- Post-mortem (실패 시): #

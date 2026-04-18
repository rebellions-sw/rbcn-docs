# Incident Post-mortem: <간결한 제목>

| 항목 | 값 |
|------|----|
| **ID** | PM-YYYY-MM-DD-<slug> |
| **Date (UTC)** | YYYY-MM-DD |
| **Detection Time** | YYYY-MM-DD HH:MM UTC |
| **Resolution Time** | YYYY-MM-DD HH:MM UTC |
| **Duration** | XXm |
| **Severity** | P1 / P2 / P3 |
| **Category** | infra / k8s / network / security / data / app / human |
| **Affected Services** | (예: harbor.infra.rblnconnect.ai, demo-prod) |
| **Affected Users** | (예: 전사 / 약 N명 / 외부 고객) |
| **SLA Breach** | YES / NO |
| **Status** | Draft / Review / Finalized |
| **Author** | <이름 / 팀> |
| **Reviewers** | <이름1, 이름2> |

---

## 1. Summary

(2–3줄. 무슨 일이 일어났고, 어떻게 해결했는지)

## 2. Impact

- **사용자 영향**: 
- **데이터 손실**: 있음 / 없음 (있다면 범위)
- **금전적 영향**: 
- **외부 보고 의무**: (예: GDPR, ISMS, 고객 SLA)

## 3. Timeline (모두 UTC)

| 시각 | 이벤트 |
|------|--------|
| HH:MM | 첫 알림 (Prometheus alert: `AlertName`) |
| HH:MM | On-call 대응 시작 |
| HH:MM | 1차 원인 가설 |
| HH:MM | 완화 조치 적용 |
| HH:MM | 정상 동작 확인 |
| HH:MM | 인시던트 종료 |

## 4. Root Cause (5 Whys)

1. **Why?** 
2. **Why?** 
3. **Why?** 
4. **Why?** 
5. **Why?** (Root cause)

## 5. Detection

- **어떻게 발견되었나?**: Alert / 모니터링 / 사용자 제보
- **MTTD (Mean Time To Detect)**: XX분
- **개선점**: (조기 탐지를 위한 알림 추가/조정)

## 6. Resolution

(어떻게 해결했는지 단계별로 — 명령어 / 변경사항 포함)

```bash
# 예시
kubectl -n monitoring rollout restart deploy/prometheus-server
```

- **MTTR (Mean Time To Repair)**: XX분

## 7. What went well?

- 
- 

## 8. What went wrong?

- 
- 

## 9. Where did we get lucky?

- 

## 10. Action Items

| # | Action | Owner | Priority | Due | Status | Tracking |
|---|--------|-------|----------|-----|--------|----------|
| 1 | | | P1/P2/P3 | YYYY-MM-DD | Open | (issue link) |
| 2 | | | | | | |
| 3 | | | | | | |

## 11. Prevention

(재발 방지책: 코드 변경 / 알림 추가 / 런북 갱신 / 교육)

## 12. References

- **Grafana Dashboard**: https://grafana.infra.rblnconnect.ai/d/<uid>?from=<ts>&to=<ts>
- **Loki Logs**: https://grafana.infra.rblnconnect.ai/explore?...
- **Alert Definition**: `PrometheusRule/<name>`
- **Runbook**: `/opt/rbcn-docs/runbooks/<service>.md`
- **Related PRs**: 
- **Related Incidents**: 

## 13. Appendix

(스크린샷, 로그 발췌, 설정 diff 등)

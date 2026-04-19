# Maintenance Window Policy

> 의도된 유지보수 / 변경의 시간/방법 표준.

---

## 1. Window

| Window | 시간 (KST) | 허용 작업 |
|--------|-----------|-----------|
| **Standard** | 평일 09:00~18:00 | dev/stage 자유, prod 는 PR + review |
| **Evening**  | 평일 18:00~22:00 | prod 변경 권장 (트래픽 ↓) |
| **Night**    | 22:00~06:00 | emergency only |
| **Weekend**  | 토/일 | emergency only |
| **Maintenance Day** | 매월 첫 토요일 02:00~06:00 KST | major upgrade (CP, DB major version, etc) |

---

## 2. Change Freeze (calendar-based)

`change-requests/POLICY.md` 의 freeze 와 동일:

- 분기 마감 D-3 ~ D+1 (CFO 발표 영향)
- 연말 12/24 ~ 1/2
- 회사 휴무일 (custom freeze)

freeze 중 emergency: plat-team-lead approve.

---

## 3. Silence 절차 (의도된 다운타임)

prod 변경 전 알람 silence:

```bash
# Alertmanager UI: https://alertmanager.dev.infra.rblnconnect.ai
# 또는 amtool
amtool silence add \
  --alertmanager.url=https://alertmanager.dev.infra.rblnconnect.ai \
  --duration=2h \
  --comment="DB minor upgrade — change CR-2026-04-19-01" \
  service=payments
```

silence 종료 후 자동 알람 복귀.

**규칙**:
- silence 는 반드시 `--comment` 에 change request ID 포함
- silence > 4h 면 plat-team 알림
- silence 만료 후 알람이 다시 fire 하면 그건 진짜 incident

---

## 4. SLA 와의 관계

Maintenance Window 안의 다운타임은 SLO 계산에서 **제외** (planned downtime).

```promql
# planned downtime 마스킹 (label maintenance="true" 인 시간)
1 - (
  sum(rate(http_requests_total{code=~"5.."}[5m])) /
  sum(rate(http_requests_total[5m]))
) unless on() (alertmanager_silence_active{maintenance="true"})
```

---

## 5. Communication

prod 영향 변경:
1. T-24h: `#announce` 에 시간/영향/롤백 plan 공지
2. T-1h: 다시 알림 + on-call mention
3. 시작: status page → "investigating"
4. 종료: status page → "resolved"

---

## 6. 관련 문서

- [`../change-requests/POLICY.md`](../change-requests/POLICY.md)
- [`alert-policy.md`](./alert-policy.md)
- [`../runbooks/oncall.md`](../runbooks/oncall.md)

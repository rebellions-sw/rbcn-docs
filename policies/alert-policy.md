# Alert Policy — 알람 등급 + Noise Budget

> 모든 알람은 등급이 있고, 등급은 누가 어디서 받는지 정함.
> Noise budget 을 두어 알람 자체의 신뢰성 보장.

---

## 1. 알람 등급

| Severity | 의미 | 채널 | SLA | 예시 |
|----------|------|------|-----|------|
| **page**     | 사용자 영향 + 즉시 조치 | PagerDuty | ack ≤ 5분 | 5xx burst, prod down |
| **ticket**   | 잠재 사용자 영향 + 영업시간 | Slack `#alerts-<svc>` | ack ≤ 30분 | replica lag, cert D-3 |
| **info**     | 운영 참고 | Slack `#alerts-platform` | best-effort | cost spike, dev cluster warn |

**Severity 결정 규칙** (PrometheusRule 의 `labels.severity`):
- T1 service 의 burn rate ≥ 6× → `page`
- T2 service 의 burn rate ≥ 6× → `ticket` (T2 는 page 안 함; 평일 영업시간만)
- 모든 인프라 컴포넌트 down (vault, etcd, ingress, harbor) → `page`
- 모든 cert 만료 ≤ 7d → `ticket`
- 모든 cert 만료 ≤ 1d → `page`

---

## 2. Routing

`alertmanager-config.yaml` (자동 적용):

```yaml
route:
  receiver: slack-platform
  group_by: [alertname, service]
  routes:
    - matchers: [severity="page", tier="T1"]
      receiver: pagerduty-prod-t1
    - matchers: [severity="page"]
      receiver: pagerduty-prod
    - matchers: [severity="ticket"]
      receiver: slack-team-routed   # owner label 로 #alerts-<owner> 자동
    - matchers: [severity="info"]
      receiver: slack-platform
```

---

## 3. Noise Budget

빅테크 표준: **on-call 1명당 한 주 < 10건** (Google SRE).

| 측정 항목 | 목표 | 계산 |
|----------|------|------|
| Page / 주 / on-call | < 10 | sum(rate) over 7d |
| 거짓양성 (false positive) 비율 | < 30% | post-mortem 의 'no-action' 분류 |
| 한밤(22시~06시) page / 월 | < 5 | timezone 인식 |

대시보드: Grafana > "Alert Hygiene".

**초과 시**:
1. Owner team 이 alert tuning PR (threshold up, window 확장, group)
2. plat-team approve 후 merge
3. 1 주 모니터링 → 다시 noisy 면 alert 제거 검토

---

## 4. 알람 작성 규칙 (PR review checklist)

PrometheusRule PR 머지 전 다음 5 가지 확인:

```
[ ] severity 정확 (page/ticket/info 중 1개)
[ ] for: 충분히 길음 (page 는 ≥ 2m, ticket 은 ≥ 10m)
[ ] expr 가 SLO-based (burn rate) 또는 인프라 down
[ ] annotations.summary, annotations.runbook_url 명시
[ ] team_label (owner: <team>) 자동 routing 가능
```

표준 템플릿: [`../templates/prometheus-burn-rate.yaml`](../templates/prometheus-burn-rate.yaml)

---

## 5. 관련 문서

- [`slo-policy.md`](./slo-policy.md)
- [`maintenance.md`](./maintenance.md) — 유지보수 시 silence 절차
- [`../runbooks/oncall.md`](../runbooks/oncall.md)

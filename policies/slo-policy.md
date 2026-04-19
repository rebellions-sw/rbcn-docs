# SLO Policy — Tier 별 표준

> 우리 모든 user-facing service 는 Tier 가 있고, Tier 가 정해지면 SLO/Error Budget 자동 적용.
> 기준: Google SRE workbook (2016) + Stripe SRE practice.

---

## 1. Tier 정의

| Tier | 설명 | 예시 | 적용 |
|------|------|------|------|
| **T1** | 매출 직결 / 사용자 직접 영향 | payments, portal, auth | 99.9% (SLO), 24/7 on-call P1 |
| **T2** | 사용자 영향 있으나 우회 가능 | search, recommender, notifications | 99.5%, 평일 09~18 P1 |
| **T3** | 내부 도구 / 백오피스 | analytics, admin-portal | 99.0%, best-effort |

`services-catalog/services/<svc>-<env>.yaml` 의 `tier` 필드가 source of truth.

---

## 2. SLO + Error Budget

| Tier | Availability SLO (월) | Error Budget (월) | Latency SLO P99 |
|------|----------------------|------------------|-----------------|
| T1   | 99.9%                | 43m 49s          | < 300ms         |
| T2   | 99.5%                | 3h 39m           | < 800ms         |
| T3   | 99.0%                | 7h 18m           | < 2000ms        |

> Error Budget = (1 - SLO) × 월시간 (43,800m).

---

## 3. Burn Rate Alert (Multi-window, Multi-burn-rate)

빅테크 표준 (Google SRE Ch.5): **fast burn + slow burn 동시 사용** 으로 거짓양성 ↓.

| Severity | Window | Threshold | 의미 | 행동 |
|----------|--------|-----------|------|------|
| **page** | 1h     | burn ≥ 14.4× | 1h 안에 한 달 budget 의 2% 소진 | PagerDuty (즉시) |
| **page** | 6h     | burn ≥ 6×    | 6h 안에 한 달 budget 의 5% 소진 | PagerDuty (즉시) |
| **ticket** | 1d   | burn ≥ 3×    | 1d 안에 한 달 budget 의 10% 소진 | Slack (영업시간) |
| **ticket** | 3d   | burn ≥ 1×    | 3d 안에 한 달 budget 의 10% 소진 | Slack (영업시간) |

자동 적용은 [`templates/prometheus-burn-rate.yaml`](../templates/prometheus-burn-rate.yaml) 참고.

---

## 4. Error Budget 정책

- 한 달 budget 50% 소진: **release velocity 감속** — 신규 기능 PR 보다 안정성 PR 우선
- 80% 소진: **freeze** — 신규 기능 freeze, 운영 개선만
- 100% 소진: **incident review** — 즉시 post-mortem + RCA

본 정책은 `change-requests/POLICY.md` 의 freeze 와 다름 (분기 마감, 연말은 calendar-based; 본 정책은 metric-based).

---

## 5. Tier 변경 절차

1. 서비스 owner 가 PR (`services-catalog/services/<svc>-<env>.yaml` 의 `tier` 수정)
2. plat-team review (T1 으로 올릴 때는 capacity / on-call 필요)
3. merge → 자동으로 PrometheusRule + alertmanager routing 변경

---

## 6. 검증

서비스의 SLO 가 잘 동작하는지:

```bash
rbcn slo <svc>                   # Grafana SLO 대시보드 직접
# 또는
rbcn url grafana
# Dashboards > SLO > <svc> 에서:
#   - Availability (30d window)
#   - Error Budget remaining
#   - Burn rate (1h, 6h, 1d, 3d)
```

---

## 7. 관련 문서

- [`alert-policy.md`](./alert-policy.md) — 알람 등급
- [`maintenance.md`](./maintenance.md) — 유지보수 윈도우
- [`../templates/prometheus-burn-rate.yaml`](../templates/prometheus-burn-rate.yaml)
- [Google SRE Workbook Ch.5 — Alerting on SLOs](https://sre.google/workbook/alerting-on-slos/)

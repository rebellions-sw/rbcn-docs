# Change Request Policy

> 어떤 변경이 어떤 환경에 어떻게 들어가는지의 합의.

---

## 0. 환경별 변경 정책

| 환경 | 변경 권한 | Review | 검증 후 자동? |
|------|-----------|--------|---------------|
| **dev** | 누구나 (CODEOWNERS 의 1명만 OK) | 1 reviewer | YES (PR merge → ArgoCD 즉시 sync) |
| **stage** | 본인 팀 또는 plat-team | 1 team reviewer | YES (rbcn promote 가 PR 생성 → merge) |
| **prod** | plat-team OR on-call lead | 2 reviewer (1명 plat-team 必) | NO (rbcn promote PR → 수동 merge → ArgoCD sync) |

---

## 1. PR 표준

모든 manifest 변경 PR 의 description 에 다음 4 가지 필수:

```markdown
## What
<무엇을 바꾸나>

## Why
<왜 바꾸나>

## Risk
<예상 risk + 영향 범위>

## Rollback Plan
<문제 시 어떻게 되돌리나>
```

PR 자동 점검 (`promote.yml` reusable workflow):
- yamllint
- kubeconform (k8s schema)
- conftest (조직 정책 OPA)
- diff preview (kustomize build 결과)

---

## 2. Emergency Change (긴급)

P1 incident 대응 시:
1. `#incident-<date>` 채널에 announce
2. PR 만들고 plat-team 1명만 reviewer 로 지정
3. merge 후 즉시 사후 review (24시간 내 retrospective PR)

---

## 3. Window / Freeze

| 시기 | 정책 |
|------|------|
| 평일 09:00 ~ 18:00 KST | 자유 (단, P1 service 는 19:00 이후 권장) |
| 주말 / 공휴일 | emergency 외 금지 |
| 분기 마감 D-3 | freeze (CFO 발표 영향) |
| 연말 12/24 ~ 1/2 | freeze (소수 인력) |

freeze 중 emergency 는 plat-team-lead approve 필요.

---

## 4. Change Log

모든 prod 변경은 자동으로 `change-requests/log/YYYY-MM.md` 에 추가 (GitHub Actions hook).

---

## 5. 더 자세히

- [`runbooks/oncall.md`](../runbooks/oncall.md) — on-call 대응
- [`postmortems/TEMPLATE.md`](../postmortems/TEMPLATE.md) — post-mortem

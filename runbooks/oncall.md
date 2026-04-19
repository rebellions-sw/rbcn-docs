# On-Call Runbook

> 본인이 이번 주 on-call 일 때 보는 가이드.

---

## 0. 첫 5분 체크리스트

```
[ ] PagerDuty 앱/노트북 알림 활성화
[ ] Slack #alerts-prod / #alerts-platform mute 해제
[ ] workspace VM ssh 가능
[ ] rbcn status 실행 → 모든 cluster GREEN
[ ] grafana > 'On-Call Dashboard' 북마크 확인
```

---

## 1. 알림 등급 / SLA

| Severity | 응답 SLA | 예시 |
|----------|---------|------|
| P1 (사용자 영향) | 즉시 ack ≤ 5분 | API 5xx > 1%, prod cluster 다운, DB master 다운 |
| P2 (잠재 사용자 영향) | ack ≤ 30분 | replica lag, cert 만료 D-3, disk > 85% |
| P3 (운영) | 다음 영업일 | dev cluster 알림, cost spike |

---

## 2. 첫 대응 (모든 P1 공통)

```bash
# (변수로 한번 정의 → 그대로 복붙 가능)
SVC=payments        # 영향 받는 서비스 (rbcn problems 출력에서)
NS=payments         # 보통 동일

# 1. 누구든 ack (PagerDuty 모바일 또는 https://rebellions.pagerduty.com)
# 2. Slack 에서 #incident 채널 새로: '/incident new <한줄 제목>' 입력

# 3. 즉시 진단
rbcn problems
rbcn diag $SVC

# 4. 영향 범위 확인 (Grafana)
rbcn slo $SVC                    # 5xx, latency, error budget burn rate

# 5. 변경 사항 점검 (최근 30분 deploy)
gh run list -R rebellions-sw/$SVC -L 5
kubectl get events -A --sort-by='.lastTimestamp' | tail -30
```

---

## 3. 자주 보는 알림 → runbook 매핑

| 알림 | 즉시 명령 | runbook |
|------|----------|---------|
| `KubeAPIDown` | `rbcn nodes` | [k8s-cp.md](./k8s-cp.md) |
| `VaultSealed` | `rbcn vault` | [vault-unseal.md](./vault-unseal.md) |
| `IngressNGINXBackendDown` | `kubectl get pods -n ingress-nginx` | [k8s-cp.md](./k8s-cp.md) |
| `CertExpiringSoon` | `rbcn cert renew <name>` | [`onboarding/troubleshooting.md`](../onboarding/troubleshooting.md) §5.2 |
| `CNPGReplicaLag` | `kubectl describe cluster <db>` | [db-pitr.md](./db-pitr.md) |
| `TargetDown` (Prometheus) | `kubectl get servicemonitor -A` | grafana > target |
| `CostSpike` | `rbcn cost recommend` | OpenCost dashboard |

---

## 4. 롤백 (가장 빠른 안전장치)

```bash
SVC=payments
NS=payments
rbcn rollback $SVC                  # Argo Rollouts 직전 stable revision
# 또는 specific revision 으로
kubectl argo rollouts undo $SVC -n $NS
```

배포 PR 자체를 revert 해야 한다면 (PR 번호는 GitHub UI 에서 확인):

```bash
SVC=payments
PR_NUM=42      # ← 본인이 채워야 함
gh pr revert $PR_NUM -R rebellions-sw/$SVC-manifests
```

---

## 5. Escalation

- 30분 이내 미해결 → CTO + plat-team-lead PagerDuty 페이지
- 2시간 이내 미해결 → statuspage.io 업데이트 ("investigating")
- 4시간 이내 미해결 → 외부 communication (고객 메일)

연락처: `secret/oncall/contacts` (Vault)

---

## 6. 사후 (post-mortem)

- 증상 종료 후 24시간 내 [`postmortems/TEMPLATE.md`](../postmortems/TEMPLATE.md) 복사 → `postmortems/2026/YYYY-MM-DD-<title>.md` 작성
- 다음 주 화 office hour 에서 review
- action item 은 GitHub issue 로 변환

---

## 7. 인계

매주 월 10:00 oncall handoff:
- 지난 주 인시던트 요약
- 현재 진행중 P2 issue
- 새 PagerDuty schedule 확인 (PD UI)
- 본 runbook 의 신규 알림 매핑 업데이트

---

## 8. 더 자세히

- [postmortems/INDEX.md](../postmortems/INDEX.md) — 과거 사고 분석
- [dr/INDEX.md](../dr/INDEX.md) — 재해 복구 (cluster 전체 손실)
- [PLATFORM.md](../PLATFORM.md) — 운영자 SOT

# Incident Post-mortem: chaos-mesh webhook 호출 차단으로 Schedule 생성 실패

| 항목 | 값 |
|------|----|
| **ID** | PM-2026-04-18-chaos-mesh-webhook-blocked |
| **Date (UTC)** | 2026-04-18 |
| **Detection Time** | 2026-04-18 03:47 UTC |
| **Resolution Time** | 2026-04-18 03:49 UTC |
| **Duration** | 2m |
| **Severity** | P3 |
| **Category** | network |
| **Affected Services** | chaos-mesh on dev/stage K8s clusters |
| **Affected Users** | Internal (DevOps team) |
| **SLA Breach** | NO |
| **Status** | Finalized |
| **Author** | DevOps Bot |
| **Reviewers** | (auto-generated) |

---

## 1. Summary

Phase 08 chaos engineering 도입 중, chaos-mesh 의 `Schedule` CR 을 생성하려 할 때 admission webhook timeout (`mschedule.kb.io: context deadline exceeded`) 으로 모든 생성 요청이 실패. 원인은 chaos-mesh 네임스페이스에 적용된 `default-deny-ingress` NetworkPolicy 가 kube-apiserver 에서 chaos-controller-manager:10250 webhook 으로의 ingress 트래픽을 차단했기 때문. `allow-webhook-ingress` NetworkPolicy 를 추가하여 즉시 해결.

## 2. Impact

- **사용자 영향**: 없음 (내부 도구 도입 단계)
- **데이터 손실**: 없음
- **금전적 영향**: 없음
- **외부 보고 의무**: 없음

## 3. Timeline (모두 UTC)

| 시각 | 이벤트 |
|------|--------|
| 03:47 | 04-chaos-experiments.sh 실행 → 6개 Schedule 모두 admission webhook timeout |
| 03:48 | NetworkPolicy 분석 → `default-deny-ingress` 발견 |
| 03:48 | Webhook 컨테이너 포트 확인 (10250) |
| 03:49 | `allow-webhook-ingress` NP 적용 |
| 03:49 | 테스트 Schedule 생성 성공 |
| 03:49 | dev/stage 각 6개 Schedule 정상 등록 (총 12) |

## 4. Root Cause (5 Whys)

1. **Why?** Schedule CR 생성이 timeout 으로 실패
2. **Why?** kube-apiserver 가 chaos-controller-manager 의 admission webhook 호출 불가
3. **Why?** NetworkPolicy 가 ingress 트래픽 차단
4. **Why?** `default-deny-ingress` NP 가 적용되었지만 webhook 트래픽을 명시적으로 허용하지 않음
5. **Why? (Root)** 03-chaos-mesh-install.sh 작성 시 prometheus scrape ingress 만 고려하고, kube-apiserver → controller webhook 트래픽 허용 NP 누락

## 5. Detection

- **어떻게 발견되었나?**: 04-chaos-experiments.sh 실행 직접 에러
- **MTTD**: 즉시 (실행 직후)
- **개선점**: chaos-mesh helm 설치 후 dummy Schedule 생성하는 self-test 추가

## 6. Resolution

```bash
kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-webhook-ingress
  namespace: chaos-mesh
spec:
  podSelector:
    matchLabels:
      app.kubernetes.io/component: controller-manager
  policyTypes: [Ingress]
  ingress:
  - from:
    - ipBlock:
        cidr: 0.0.0.0/0
        except: [169.254.0.0/16]
    ports:
    - protocol: TCP
      port: 10250
EOF
```

- **MTTR**: 2분

## 7. What went well?

- 에러 메시지가 명확 ("failed calling webhook")
- NetworkPolicy 분석 → 즉시 원인 식별
- F06-08-01 (trivy) 와 동일 패턴 → 신속 대응

## 8. What went wrong?

- 03-chaos-mesh-install.sh 에 self-test 부재
- chaos-mesh 공식 차트 기본 NetworkPolicy 미제공 (자체 작성 필요)

## 9. Where did we get lucky?

- Production 영향 없음 (dev/stage 만 적용됨)
- 같은 turn 에서 즉시 발견 → context loss 없음

## 10. Action Items

| # | Action | Owner | Priority | Due | Status | Tracking |
|---|--------|-------|----------|-----|--------|----------|
| 1 | 03-chaos-mesh-install.sh 에 webhook self-test 추가 | DevOps | P3 | 2026-04-18 | Open | (TBD) |
| 2 | 다른 namespace 의 default-deny-ingress 영향 분석 (audit) | DevOps | P2 | 2026-04-25 | Open | (TBD) |
| 3 | chaos-mesh kyverno policy 작성 (필요 NP 자동 생성) | Platform | P3 | 2026-05-18 | Open | (TBD) |

## 11. Prevention

- Helm 차트 install 직후 webhook 호출 테스트 (Schedule with cron `0 0 1 1 *`) 자동화
- 모든 `default-deny` NP 적용 시 admission controller 의존성 검토 체크리스트 작성
- chaos-mesh 등 webhook 사용 컴포넌트 install script 에 NetworkPolicy 사전 설정 표준화

## 12. References

- **Alert**: 없음 (수동 발견)
- **Runbook**: `/opt/rbcn-docs/runbooks/k8s-cp.md`
- **Related Incidents**: F06-08-01 (trivy networking)
- **Related Files**:
  - `08_ha_dr/03-chaos-mesh-install.sh` (수정됨)
  - `08_ha_dr/04-chaos-experiments.sh`

## 13. Appendix

### Webhook 컨테이너 포트
```
Container chaos-mesh:
  - containerPort: 10250, name: webhook
  - containerPort: 10080, name: http
  - containerPort: 10081, name: pprof
  - containerPort: 10082, name: ctrl
```

### 적용된 NetworkPolicies
- allow-api-egress (모든 egress)
- allow-prometheus-scrape (monitoring → 10080/10081/2333)
- allow-webhook-ingress (모든 ingress → 10250) ← **NEW**
- allow-dashboard-ingress (모든 ingress → 2333) ← **NEW**
- default-deny-ingress (기본 차단)
- allow-dns-egress (kube-system DNS)

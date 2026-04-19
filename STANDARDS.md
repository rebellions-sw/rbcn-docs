# RBCN Platform — Big-Tech Standards Gap Analysis

> 본 문서는 빅테크 (Google SRE, Meta, Netflix, Stripe, AWS) 표준 대비 우리 플랫폼의 갭과
> 채워진 항목을 한 페이지에 매핑합니다. 매 분기 한 번 업데이트.
> 작성: 2026-04-19

## 0. 점수 요약 (10 카테고리, 총 100점)

| # | 카테고리 | 빅테크 표준 | 우리 점수 | 상태 |
|---|---------|-----------|----------|------|
| 1 | SLO / Error Budget | 모든 user-facing service | **8/10** | OK |
| 2 | Observability (RED+USE+Trace) | Golden signals + tracing | **9/10** | OK |
| 3 | CI/CD (build → scan → sign → deploy) | Sigstore, SLSA-3 | **9/10** | OK |
| 4 | GitOps + IaC | Terraform + ArgoCD + drift detection | **8/10** | OK (drift detect P1) |
| 5 | Secret 관리 | Vault + auto-rotation + ESO | **8/10** | OK (회전 알림 P1) |
| 6 | Security Hardening | mTLS, NetPol, OPA/Kyverno, image sign | **9/10** | OK |
| 7 | DR / Backup | RPO ≤ 5분, RTO ≤ 30분, GameDay 분기 | **8/10** | OK (GameDay 미실시) |
| 8 | Cost / Capacity | OpenCost, Goldilocks, autoscaling | **9/10** | OK |
| 9 | Developer Experience | golden path, 1-cmd onboarding, local-loop | **9/10** | OK |
| 10 | On-call / Incident | PagerDuty, runbook, post-mortem culture | **8/10** | OK (GameDay 도입 필요) |

**총점: 85/100** — 빅테크 mid-tier 수준. 95+ 진입을 위해 P1 backlog 5건 (§4) 필요.

---

## 1. SLO / Error Budget (8/10)

| 항목 | 빅테크 표준 | 우리 현황 | 상태 |
|------|-----------|----------|------|
| user-facing service 의 SLO 명시 | 모든 service | `services-catalog/services.yaml` 의 `tier` 필드로 분류 (T1/T2/T3) | OK |
| SLI 정의 (latency, availability, error rate) | RED method | Prometheus + ServiceMonitor 자동 (new-service 시) | OK |
| Error budget burn alert | multi-window, multi-burn-rate | PrometheusRule template 에 5xx > 5% (10m) 만 (단순) | **GAP** → §4 P1-A |
| SLO 대시보드 | service 별 1개 | `rbcn slo <svc>` → grafana | OK |

**채워진 것**:
- `services-catalog/services/<svc>-<env>.yaml` 의 `tier` field
- `base/prometheusrule.yaml` 에 자동 5xx + latency + crashloop alert
- [`onboarding/api-service.md`](./onboarding/api-service.md) §6 SLO 확인 절차

**P1 GAP** (채울 수 있음):
- 표준 multi-window burn rate alert 템플릿 → §4 추가
- error budget 정책 문서 (T1=99.9%, T2=99.5%, T3=99.0%) → §4 추가

## 2. Observability (9/10)

| 항목 | 빅테크 표준 | 우리 현황 | 상태 |
|------|-----------|----------|------|
| Metrics | Prometheus | OK (kube-prometheus-stack) | OK |
| Logs | Loki/ELK + 1-week retention | Loki + 30일 retention | OK |
| Traces | Tempo/Jaeger + auto-propagation | Tempo + Istio auto inject | OK |
| Dashboards | per-service + global | Grafana provisioned + dashboards-as-code | OK |
| RUM (real user monitoring) | 일부 빅테크만 | 미적용 | **GAP** → §4 P2-A (선택) |
| Profiling (continuous) | Pyroscope, Polar Signals | 미적용 | **GAP** → §4 P2-B (선택) |

## 3. CI/CD (9/10)

| 항목 | 빅테크 표준 | 우리 현황 | 상태 |
|------|-----------|----------|------|
| Reusable workflow (drift 0) | OK (org-level) | `rebellions-sw/.github` 의 `reusable-build/promote/manifest-validate` | OK |
| Image signing (Cosign) | SLSA-3 | Cosign 자동 (`secret/cosign/signing`) | OK |
| SBOM (Syft/CycloneDX) | 모든 image | Syft 자동 → artifact upload | OK |
| Trivy scan + 정책 | severity gate | `severity_fail: CRITICAL,HIGH` 기본 | OK |
| Self-hosted runner HA | 다중 노드, autoscale | `rbcn-ci-runner-01` **단일 VM** + ARC | **GAP** → §4 P1-B |
| 환경별 Trivy 차등 | dev=HIGH, prod=CRITICAL | 동일 정책 | **GAP** → §4 P1-C |
| 빌드 캐시 | registry / s3 backed | docker buildx registry cache | OK |
| Provenance (in-toto attestation) | SLSA-3 | 미적용 | **GAP** → §4 P2-C (선택) |

## 4. GitOps + IaC (8/10)

| 항목 | 빅테크 표준 | 우리 현황 | 상태 |
|------|-----------|----------|------|
| Single source of truth | Git | `rbcn-docs` + `<svc>-manifests` | OK |
| ArgoCD ApplicationSet | catalog-driven onboarding | `services-catalog/services/*.yaml` glob | OK |
| Terraform / OpenTofu | infra as code | `/opt/rbcn-infra-iac` | OK |
| Drift detection | tfstate diff alert | 수동만 | **GAP** → §4 P1-D |
| PR-based change | mandatory | `change-requests/POLICY.md` (env 별) | OK |

## 5. Secret 관리 (8/10)

| 항목 | 빅테크 표준 | 우리 현황 | 상태 |
|------|-----------|----------|------|
| 중앙 vault | Vault / SecretsManager | Vault HA 3-node | OK |
| ESO 로 K8s 전파 | 자동 | ESO + 30s refresh | OK |
| GH Org secret 동기화 | 자동 | `rbcn secret sync-gh` (validation 포함) | OK |
| 회전 정책 | 90일 PAT, 365일 cosign | `runbooks/secret-rotation.md` | OK |
| 회전 만료 알림 | 7일 전 PagerDuty | **미적용** | **GAP** → §4 P1-E |
| Audit (누가 언제 read) | 100% | Vault audit log → Loki | OK |
| Sealed Vault recovery | 5명 중 3명 키 | `runbooks/vault-unseal.md` | OK |

## 6. Security Hardening (9/10)

| 항목 | 빅테크 표준 | 우리 현황 | 상태 |
|------|-----------|----------|------|
| mTLS 모든 서비스 | Istio STRICT | OK | OK |
| NetworkPolicy default-deny | OK | base/networkpolicy.yaml 자동 (allow-ingress only) | OK |
| Pod Security | restricted | securityContext: runAsNonRoot, seccomp RuntimeDefault, readOnlyRootFilesystem, drop ALL caps | OK |
| OPA/Kyverno policy | image signing, label, resource | Kyverno (cosign verify, harbor pull secret 자동, label 강제) | OK |
| Image scan in CI | Trivy CRITICAL/HIGH gate | OK | OK |
| Image scan in cluster | runtime (Trivy operator) | OK | OK |
| Distroless / minimal base | OK | Go 는 distroless, Python/Node 는 alpine/slim | OK |
| Secret in Git 검출 | gitleaks pre-commit | base-app pre-commit 에 포함 | OK |
| supply-chain (SLSA) | Provenance | 미적용 | **GAP** → §4 P2-C |
| CIS Kubernetes benchmark | quarterly | 미실시 | **GAP** → §4 P2-D |

## 7. DR / Backup (8/10)

| 항목 | 빅테크 표준 | 우리 현황 | 상태 |
|------|-----------|----------|------|
| etcd snapshot | 매 6h, 보관 7d | 매 6h, 보관 30d | OK |
| Velero backup | daily, off-site | daily, MinIO mirror | OK |
| CNPG WAL archive | 매 5분, PITR 30d | OK | OK |
| Backup 검증 (restore drill) | quarterly | 수동, 비주기 | **GAP** → §4 P1-F |
| GameDay (chaos exercise) | quarterly | **미실시** | **GAP** → §4 P1-G |
| RPO / RTO 정의 + 측정 | 모든 service | `runbooks/vault.md` 에만 | **GAP** → §4 P1-H |

## 8. Cost / Capacity (9/10)

| 항목 | 빅테크 표준 | 우리 현황 | 상태 |
|------|-----------|----------|------|
| 비용 가시성 (per ns) | OpenCost | OK | OK |
| Rightsizing 권장 | Goldilocks | OK | OK |
| HPA 기본 적용 | OK | base/hpa.yaml 자동 | OK |
| 월간 cost report | OK | `cost-reports/` | OK |
| Cluster autoscaler | optional | 노드 수 고정 (on-prem) | OK |

## 9. Developer Experience (9/10)

| 항목 | 빅테크 표준 | 우리 현황 | 상태 |
|------|-----------|----------|------|
| Golden path bootstrapping | 1-cmd | `rbcn new <svc> --type=...` | OK |
| Onboarding < 1일 | OK | `ONBOARDING.md` 90분 | OK |
| Local dev loop | < 30s | skaffold + tilt | OK |
| API/lib catalog | internal portal | `services/INDEX.md` (basic) | OK |
| Inner-source contribution | clear path | CODEOWNERS + PR template 자동 | OK |
| ChatOps / Slack bot | 일부 빅테크 | 미적용 | (선택) |

## 10. On-call / Incident (8/10)

| 항목 | 빅테크 표준 | 우리 현황 | 상태 |
|------|-----------|----------|------|
| PagerDuty rotation | OK | OK | OK |
| Runbook per alert | OK | `runbooks/INDEX.md` 7개 | OK |
| Post-mortem (blameless) | mandatory | template + 기존 사례 보유 | OK |
| Incident commander training | annual | 미진행 | (선택) |
| GameDay | quarterly | 미진행 | **GAP** → §4 P1-G |
| Alert hygiene (noise budget) | < 10/주 | 측정 안함 | **GAP** → §4 P1-I |

---

## P1 Backlog (이번 분기 채워야 빅테크 95+)

| # | 항목 | 카테고리 | 형태 | ETA |
|---|------|---------|------|-----|
| P1-A | Multi-window burn-rate SLO alert template | SLO | 문서 + PromRule 템플릿 | 1d |
| P1-B | rbcn-ci-runner SPOF 제거 (VM +1 또는 ARC DinD) | CI/CD | 인프라 작업 | 2~5d |
| P1-C | 환경별 Trivy 정책 (dev=HIGH, prod=CRITICAL) | CI/CD | reusable-build.yaml input | 0.5d |
| P1-D | Terraform drift detection (atlantis or tfstate diff cron) | IaC | 인프라 작업 | 2d |
| P1-E | PAT 만료 7일 전 PagerDuty 알림 | Secret | cron job + Alertmanager | 1d |
| P1-F | 분기별 백업 restore drill 자동화 | DR | runbook + cron | 1d |
| P1-G | 분기별 GameDay 시나리오 5종 | DR/Incident | 문서 + 실행 | 1d |
| P1-H | RPO/RTO 표 (서비스별) | DR | 문서 (services-catalog 확장) | 0.5d |
| P1-I | Alert hygiene 대시보드 + noise SLO | On-call | Grafana panel | 1d |

**합산: 약 1주 작업 + 인프라 작업 1주.**

---

## P2 Backlog (선택, 6 개월 내)

| # | 항목 |
|---|------|
| P2-A | RUM (browser real user metric) — Sentry / Datadog RUM |
| P2-B | Continuous profiling (Pyroscope) |
| P2-C | SLSA-3 Provenance (in-toto attestation) |
| P2-D | CIS Kubernetes benchmark scan (kube-bench) quarterly |

---

## 본 문서가 채운 GAP — 즉시 사용 가능

다음 신규 문서가 본 분석 직후 같이 추가됨:

- [`STANDARDS.md`](./STANDARDS.md) (이 문서) — 분기별 자가진단
- [`policies/slo-policy.md`](./policies/slo-policy.md) — Tier 별 SLO 표준 + multi-window burn-rate
- [`policies/alert-policy.md`](./policies/alert-policy.md) — 알람 등급 + noise budget
- [`policies/maintenance.md`](./policies/maintenance.md) — 유지보수 윈도우 + freeze
- [`runbooks/gameday.md`](./runbooks/gameday.md) — 분기별 GameDay 5 시나리오
- [`runbooks/restore-drill.md`](./runbooks/restore-drill.md) — 분기 백업 검증 드릴
- [`templates/prometheus-burn-rate.yaml`](./templates/prometheus-burn-rate.yaml) — multi-window burn rate alert template

---

## 분기 점검 (다음: 2026-Q3)

매 분기 첫 월요일에 본 문서를 다시 평가:
1. 각 카테고리 점수 갱신
2. P1 backlog 진행 상황
3. 신규 GAP 식별 (CNCF/SRE blog 변경 반영)
4. 점수 95+ 면 P2 부터 진입

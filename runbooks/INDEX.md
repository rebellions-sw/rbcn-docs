# runbooks

운영 중 자주 보는 절차서. 신입은 [`onboarding/troubleshooting.md`](../onboarding/troubleshooting.md) 부터.

## 일상 운영

| File | 주제 |
|---|---|
| [oncall.md](./oncall.md) | On-call 대응 (이번 주 내가 on-call) |
| [secret-rotation.md](./secret-rotation.md) | 시크릿 회전 (PAT, Harbor, Cosign) |

## 인프라 컴포넌트

| File | 주제 |
|---|---|
| [k8s-cp.md](./k8s-cp.md) | Kubernetes control plane |
| [keycloak.md](./keycloak.md) | Keycloak SSO |
| [vault.md](./vault.md) | Vault HA cluster (운영) |
| [vault-unseal.md](./vault-unseal.md) | Vault sealed → unseal 빠른 가이드 |
| [mailcow.md](./mailcow.md) | Mail server |
| [minio-velero.md](./minio-velero.md) | MinIO + Velero 백업 |

## 데이터

| File | 주제 |
|---|---|
| [db-pitr.md](./db-pitr.md) | CloudNative-PG 시점 복구 |

## 관련 문서

- [`../onboarding/troubleshooting.md`](../onboarding/troubleshooting.md) — 신입용 증상별 case-study
- [`../postmortems/INDEX.md`](../postmortems/INDEX.md) — 과거 사고 분석
- [`../dr/INDEX.md`](../dr/INDEX.md) — 재해 복구
- [`../change-requests/POLICY.md`](../change-requests/POLICY.md) — 변경 정책

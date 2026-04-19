# Identity — Single Source of Truth

> **목표**: 사용자 추가/제거를 **Keycloak 한 곳**에서. 모든 시스템 자동 연동. 퇴사 시 `kc rm` 1번.

## 통합 현황 (현재 → 목표)

| 시스템 | 현재 SSO | 목표 SSO | 상태 |
|--------|---------|---------|------|
| Grafana    | YES (OIDC) | YES | OK |
| ArgoCD     | NO         | YES | TODO (`02-argocd-keycloak.sh`) |
| Harbor     | NO         | YES | TODO (`03-harbor-keycloak.sh`) |
| Headlamp   | NO (token) | YES | TODO (`04-headlamp-keycloak.sh`) |
| MinIO      | NO         | YES | TODO (`05-minio-keycloak.sh`) |
| Vault      | YES (LDAP/OIDC backend) | YES | OK |
| K8s API    | NO (kubeconfig)        | OPTIONAL | low priority |

## RBAC Matrix (표준)

| Keycloak Group | ArgoCD Role | Harbor Role | Headlamp | Grafana | K8s |
|----------------|-------------|-------------|----------|---------|-----|
| `rbcn-admins`  | admin (전체) | admin       | admin   | Admin   | cluster-admin |
| `rbcn-platform`| project-admin (default + infra) | maintainer | edit | Editor  | edit (cluster) |
| `rbcn-dev`     | sync (default) | developer | view + custom | Editor (own) | edit (own ns) |
| `rbcn-readonly`| read | guest | view | Viewer | view |

> 각 그룹은 Keycloak 의 `rebellions` realm 에 정의. group claim 으로 모든 시스템에 전파.

## Onboarding (1 명령)

```bash
# Keycloak 에 user 추가 + group 부여
rbcn user add alice@rebellions.ai --groups=rbcn-dev
# → 1분 내 Argo/Harbor/Headlamp/Grafana 모두 접근 가능.
```

## Offboarding

```bash
rbcn user rm alice@rebellions.ai
# → 모든 시스템에서 즉시 무효화 (token rotation 까지 ≤ 1h).
```

## 클라이언트 설정 (Keycloak)

| Client ID | redirect | flow | role mapping |
|-----------|----------|------|--------------|
| `argocd`   | `https://argocd.dev/api/dex/callback`        | code | groups → argocd_role |
| `harbor`   | `https://harbor.infra.rblnconnect.ai/c/oidc/callback`| code | groups → project_role |
| `headlamp` | `https://headlamp.dev/oidc-callback`         | code | groups → impersonate_groups |
| `grafana`  | `https://grafana.dev/login/generic_oauth`    | code | groups → grafana role |
| `minio`    | `https://minio.dev/oauth_callback`           | code | groups → policies |

## 설치 스크립트

```bash
ls /opt/rbcn-docs/identity/install/
# 01-keycloak-setup.sh        # realm/groups/clients 생성 (idempotent)
# 02-argocd-keycloak.sh       # argocd-cm + argocd-rbac-cm 패치
# 03-harbor-keycloak.sh       # Harbor admin API 호출
# 04-headlamp-keycloak.sh     # headlamp configmap + ingress oidc
# 05-minio-keycloak.sh        # mc admin idp openid add
```

## 감사 (Audit)

```bash
rbcn audit users          # Keycloak users + 마지막 login + 해당 그룹
rbcn audit access alice   # alice 가 어떤 시스템에서 무엇을 했는지
```

> 모든 감사 로그는 Loki + S3 archive (90 day retention).

## 보안 권장

- MFA 강제: `rbcn-admins`, `rbcn-platform` 그룹 필수
- WebAuthn / TOTP
- Token TTL: 1h (admin), 8h (dev), 24h (readonly)
- Session 강제 종료: `rbcn user logout-all alice@rebellions.ai`

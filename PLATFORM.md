# Rebellions Infra Platform — 단일 진실 (Single Source of Truth) v2

**대상**: 1-2명 운영팀 + 개발자 전체가 매일 보는 페이지.

> **개발자**: [DEVELOPER.md](./DEVELOPER.md) (신규 서비스 1 명령) 부터 보세요.
> **운영자**: 이 페이지가 진입점.

---

## 0. 30초 요약 — 지금 무슨 일이 일어나고 있나?

```bash
rbcn status               # 모든 클러스터/서비스 health 한눈에
rbcn problems             # 현재 CrashLoop / Pending / Failed 모두
rbcn cert ls              # 모든 인증서 + 만료일
rbcn backup ls            # 최근 백업 (etcd, Velero, MinIO mirror)
rbcn cost                 # 월간 cost report
rbcn appset               # ApplicationSet 상태 + 자동 생성된 app 수
rbcn catalog              # 등록된 서비스 카탈로그
```

> **문제 발생 시 첫 명령**: `rbcn problems` → `rbcn logs <pod>` → `rbcn runbook <topic>`
> **신규 서비스**: `rbcn new <name> --type=api|web|mfe|db|cache --owner=team`

---

## 1. 시스템 지도 (한 페이지 아키텍처)

### 1.1 인프라 계층

```
┌────────────────────────────────────────────────────────────────┐
│ Workspace VM (192.168.7.151)                                    │
│   - 모든 스크립트 실행, kubectl, helm, vault, ansible           │
│   - rbcn CLI (/usr/local/bin/rbcn)                              │
│   - /opt/rbcn-docs (docs SOT)                                   │
│   - /opt/rbcn-infra-iac (Terraform SOT)                         │
└────────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌────────────────────────────────────────────────────────────────┐
│ Proxmox VE Cluster (HA, 47 VM)                                  │
│   pve01, pve02, pve03, ...                                      │
│   - Ceph RBD storage                                            │
│   - VRRP VIP per service                                        │
└────────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌──────────────────┬──────────────────┬──────────────────────────┐
│ K8s dev (3 CP)   │ K8s stage (3 CP) │ K8s prod (3 CP)          │
│ .172 ingress     │ .174 ingress     │ .176 ingress             │
│ ArgoCD HUB ★     │ ArgoCD client    │ ArgoCD client            │
│ Gitea, Vault     │ Workloads only   │ Workloads only           │
│ Harbor registry  │                  │                          │
└──────────────────┴──────────────────┴──────────────────────────┘
                           │
                           ▼
┌────────────────────────────────────────────────────────────────┐
│ DNS Primary 192.168.7.181 (BIND, DNSSEC 5 zone)                 │
│ DNS Secondary 192.168.7.182                                     │
│ Backup VM 192.168.7.199 (etcd snapshots, Velero offload)        │
└────────────────────────────────────────────────────────────────┘
```

### 1.2 Demo App 계층 (현재 운영 중)

```
ArgoCD (dev cluster) → 5개 Application
  ├─ demo-nextjs-dev   →  dev cluster   demo NS  (Argo Rollouts canary)
  ├─ demo-nextjs-stage →  stage cluster demo NS
  ├─ demo-nextjs-prod  →  prod cluster  demo NS
  ├─ demo-api-dev      →  dev cluster   demo NS  (Go REST :8081)
  └─ demo-db-api-dev   →  dev cluster   demo NS  (Go DB API :8080)

Source repos (GitHub org: rebellions-sw):
  - rbcn-demo-nextjs-manifests (overlays/{dev,stage,prod})
  - rbcn-demo-api-manifests
  - rbcn-demo-db-api-manifests

Image registry:
  - harbor.infra.rblnconnect.ai/library/<service>:<tag>

DB: demo-postgres (PostgreSQL 16) in demo-db NS (dev only)
```

### 1.3 Public URL

| 환경 | UI | API |
|---|---|---|
| dev | `https://dev.infra.rblnconnect.ai` | `https://dev.infra.rblnconnect.ai/api` |
| stage | `https://stage.infra.rblnconnect.ai` | (UI only) |
| prod | `https://prod.infra.rblnconnect.ai` | (UI only) |

---

## 2. 일상 작업 — 명령어 카드

### 2.1 관측

| 의도 | 명령 |
|---|---|
| 모든 클러스터 health | `rbcn status` |
| 특정 클러스터 컨텍스트 | `eval $(rbcn ctx prod)` |
| 네임스페이스 변경 | `rbcn ns demo` |
| Pod 목록 | `rbcn pods` |
| Pod 로그 tail | `rbcn logs <pod>` |
| 최근 이벤트 | `rbcn events` |
| Port-forward | `rbcn pf demo-api 8080` |
| 서비스 진단 (status+events+logs) | `rbcn diag <svc>` |

### 2.2 배포

| 의도 | 명령 |
|---|---|
| 새 서비스 부트스트랩 | `rbcn new <svc> [go\|node\|python]` |
| 이미지 promote (dev→stage) | `rbcn promote <svc> dev stage` |
| 롤백 (Argo Rollouts) | `rbcn rollback <svc>` |
| 동기화 (ArgoCD) | `rbcn sync <app>` |
| ArgoCD app 목록 | `rbcn apps` |

### 2.3 인증서/시크릿

| 의도 | 명령 |
|---|---|
| 모든 cert + 만료 | `rbcn cert ls` |
| Vault secret 읽기 | `rbcn secret get <path>` |
| Vault secret 쓰기 | `rbcn secret put <path> k=v` |
| Vault status | `rbcn vault` |

### 2.4 백업/복구

| 의도 | 명령 |
|---|---|
| 백업 목록 | `rbcn backup ls` |
| 즉시 백업 (Velero) | `rbcn backup now <ns>` |
| 복구 | `rbcn restore <backup-name>` |
| etcd snapshot 목록 | `rbcn etcd snapshots` |

### 2.5 비용

| 의도 | 명령 |
|---|---|
| 현재 비용 | `rbcn cost` |
| 월간 보고서 | `rbcn cost report` |
| Goldilocks (rightsizing 제안) | `rbcn cost recommend <ns>` |

---

## 3. 새 서비스 추가 — Golden Path v2 (1 명령, 5 타입)

> **v2 차이**: gh repo create + push 자동, 5 타입 지원 (api/web/mfe/db/cache),
> ApplicationSet 자동 onboard, 조직 표준 reusable workflow.

```bash
rbcn new payments --type=api  --lang=go    --owner=billing       # backend
rbcn new dashboard --type=web --lang=node  --owner=platform      # web (next.js)
rbcn new billing-mfe --type=mfe            --owner=billing       # micro frontend
rbcn db    create payments-db    --ns=payments --instances=3      # CloudNative-PG
rbcn cache create payments-cache --ns=payments                    # Redis HA
```

이 한 줄이 자동으로 만들어 주는 것 (api 기준):

| # | 산출물 | 위치 |
|---|---|---|
| 1 | App skeleton + Dockerfile + Makefile + skaffold.yaml | `~/svc/<name>/` |
| 2 | GitHub repo (auto push) | `rebellions-sw/<name>` |
| 3 | GitHub manifests repo (auto push, dev/stage/prod 브랜치) | `rebellions-sw/<name>-manifests` |
| 4 | Kustomize base + 3 overlays (replicas=1/2/3) | manifests repo |
| 5 | CI workflow (호출만): `reusable-build.yaml@main` | app `.github/workflows/ci.yml` |
| 6 | Promote workflow (호출만): `reusable-promote.yaml@main` | manifests `.github/workflows/promote.yml` |
| 7 | Validate workflow (호출만): `reusable-manifest-validate.yaml@main` | manifests PR |
| 8 | Ingress + Certificate (vault-internal ClusterIssuer) | overlays |
| 9 | ServiceMonitor + PrometheusRule (3 SLO alert) | base |
| 10 | NetworkPolicy (ingress-nginx + monitoring 만 허용) | base |
| 11 | HPA + PDB | base |
| 12 | **Catalog 등록** → ApplicationSet 이 자동 ArgoCD App 3개 생성 | `services-catalog/services.yaml` |
| 13 | Vault secret 골격 + service docs stub | Vault + docs |
| 14 | 조직 표준 (CODEOWNERS, PR template, pre-commit, commitlint, SECURITY.md, .editorconfig) | app repo |

**개발자 다음 단계** (코드만):
```bash
cd ~/svc/payments
# 코드 작성
git push
# → reusable-build.yaml 자동 실행: SBOM + Trivy + Cosign + Harbor + dev tag bump
# → ArgoCD 60초 내 자동 sync
# → https://payments.dev.infra.rblnconnect.ai 즉시 확인
```

**Promotion (dev → stage → prod)**:
```bash
rbcn promote payments dev stage     # PR 자동 생성, CODEOWNERS 승인 후 merge → ArgoCD sync
rbcn promote payments stage prod    # 동일
```

---

## 4. 장애 대응 — 5 분 안에

| 증상 | 첫 명령 | 다음 |
|---|---|---|
| Pod CrashLoop | `rbcn diag <pod-prefix>` | logs + events 자동 출력 |
| Service 5xx 급증 | `rbcn slo <svc>` | Grafana 대시보드 자동 open |
| 인증서 만료 임박 | `rbcn cert ls --expiring` | `rbcn cert renew <name>` |
| etcd 불안정 | `rbcn etcd health` | runbook: `rbcn runbook etcd` |
| 노드 다운 | `rbcn node ls --down` | Proxmox HA 가 자동 복구; `rbcn runbook k8s-cp` |
| ArgoCD OutOfSync | `rbcn sync <app>` | manifests repo 확인 |
| DB 접근 불가 | `rbcn diag demo-postgres` | NetworkPolicy 확인: `rbcn netpol -n demo-db` |

**전체 runbook 카탈로그**: `rbcn runbook ls`

---

## 5. 재현성 — 처음부터 전체 스택 다시 만들기

### 5.1 사전 조건

| # | 항목 | 자동화 여부 |
|---|---|---|
| 1 | Proxmox VE 클러스터 (HA, 3+ node) | 수동 (HW 의존) |
| 2 | Workspace VM 1대 (Ubuntu 22.04, 8 vCPU 16GB) | Ansible (`bootstrap-workspace.yml`) |
| 3 | GitHub org + Personal Access Token | 수동 (계정 생성) |
| 4 | 외부 BIND DNS 2대 (위/아래) | Ansible (`bootstrap-dns.yml`) |
| 5 | Backup VM 1대 (rsync target) | Ansible (`bootstrap-backup.yml`) |

### 5.2 Bootstrap 순서 (전체 자동화)

```bash
# Workspace VM 에서 1회 실행
git clone https://github.com/rebellions-sw/rbcn-infra-iac.git
cd rbcn-infra-iac
make bootstrap
```

`make bootstrap` 이 실행하는 단계 (`Makefile` 참조):

| 단계 | 시간 | 검증 |
|---|---|---|
| 01 IaC foundation (Terraform state, Ansible inventory) | 5min | `bash 01_iac_foundation/99-verify.sh` |
| 02 Compute (3 K8s cluster via kubeadm + HPA/VPA/KEDA) | 60min | `bash 02_compute_k8s/99-verify.sh` |
| 03 CI/CD (ArgoCD + Cosign + SLSA + Kyverno verify) | 15min | `bash 03_cicd_gitops/99-verify.sh` |
| 04 Networking (BIND zones + DNSSEC + Calico + Ingress) | 15min | `bash 04_networking_dns/99-verify.sh` |
| 05 Storage (Velero + MinIO + etcd cron + DR drill) | 10min | `bash 05_storage_backup/99-verify.sh` |
| 06 Security (Vault TLS + secret 이관 + PSS + Bastion) | 10min | `bash 06_security_secrets/99-verify.sh` |
| 07 Observability (Prom + Loki + Tempo + Alertmanager) | 15min | `bash 07_observability/99-verify.sh` |
| 08 HA/DR (Proxmox HA rules + Chaos Mesh) | 5min | `bash 08_ha_dr/99-verify.sh` |
| 09 IaC migration (Atlantis + Gitea + NetBox-IaC) | 10min | `bash 09_iac_migration/99-verify.sh` |
| 10 Cost (OpenCost + Goldilocks + LimitRange) | 5min | `bash 10_cost_rightsizing/99-verify.sh` |
| 11 Cert/TLS (Vault PKI + LE + cert-manager) | 5min | `bash 11_cert_tls/99-verify.sh` |
| 12 Service Mesh (Istio CNI + mTLS + Kiali) | 10min | `bash 12_service_mesh/99-verify.sh` |
| 13 Developer Experience (Headlamp + rbcn CLI + MkDocs) | 5min | `bash 13_developer_experience/99-verify.sh` |
| 14 Compliance (kube-bench + Kyverno + audit + SOC2/CIS/ISO) | 10min | `bash 14_compliance_governance/99-verify.sh` |
| **TOTAL** | **~3 hour** | **452/452 PASS** |

> **검증**: `make verify` → 14 phase 모두 자동 verify, 결과 표 출력.
> **재시작 가능**: 실패 시 해당 phase 만 재실행 (`make phase-04`).

### 5.3 Demo app 재배포

```bash
make demo
# = bash demo/00-deploy-postgres.sh
# = bash demo/01-deploy-nextjs.sh
# = bash demo/02-deploy-api.sh
# = bash demo/03-deploy-db-api.sh
```

---

## 6. 외부 의존 (사람이 결정해야 하는 것)

| 항목 | 영향 | 결정사항 |
|---|---|---|
| GitHub PAT 만료 (90일) | CI/CD 중단 | Vault `secret/github` 갱신 + GitHub Actions `secrets` 업데이트 |
| Vault 재밀봉 (재부팅 후) | 모든 secret 접근 불가 | `vault operator unseal` × 3 keys (Vault Operator 가 보관) |
| BIND zone 변경 | DNS 일관성 | `04_networking_dns` 스크립트로 IaC 화 |
| Backup VM 디스크 풀 | 백업 실패 | Prometheus alert 자동 (`backup_disk_full > 80%`) |
| Let's Encrypt 발급 (외부 노출 시) | 공인 cert | `11_cert_tls/08-le-issuer-skeleton.sh` 가 ClusterIssuer 만 준비, 실 발급은 외부 ingress 필요 |
| 클러스터 인증서 갱신 (kubeadm 1y) | API 서버 다운 | `kubeadm certs renew all` (cron 자동) |

---

## 7. SLO / 책임 범위

| 서비스 | SLO | Owner | On-call |
|---|---|---|---|
| K8s API (3 cluster) | 99.9% / month | Platform | rbcn-platform |
| ArgoCD | 99.9% | Platform | rbcn-platform |
| Vault | 99.95% | Platform | rbcn-platform |
| Harbor | 99.9% | Platform | rbcn-platform |
| demo-nextjs | 99.5% | demo-team | demo-team |
| demo-api | 99.5% | demo-team | demo-team |

**On-call escalation**: AlertManager → Slack `#alerts-prod` → PagerDuty (외부 의존, optional)

---

## 8. 참고 문서 인덱스

| 카테고리 | 위치 |
|---|---|
| 부트스트랩 (이 문서) | `/opt/rbcn-docs/PLATFORM.md` ← **여기** |
| 서비스 카탈로그 | `/opt/rbcn-docs/services/INDEX.md` |
| Runbook | `/opt/rbcn-docs/runbooks/INDEX.md` |
| DR Runbook | `/opt/rbcn-docs/dr/INDEX.md` |
| RTO/RPO | `/opt/rbcn-docs/dr/rto-rpo.md` |
| Postmortem 템플릿 | `/opt/rbcn-docs/postmortems/TEMPLATE.md` |
| 개발자 온보딩 | `/opt/rbcn-docs/dev-onboarding.md` |
| 변경 요청 (Change Request) | `/opt/rbcn-docs/change-requests/` |
| MkDocs 사이트 | `https://docs.infra.rblnconnect.ai` (또는 `mkdocs serve`) |
| Phase 14 (전체 자동화) | `/root/final_phase_for_full_stack_demo_infra/README.md` |

---

## 9. 가장 자주 보는 명령 (북마크)

```bash
# 매일 아침
rbcn status && rbcn problems && rbcn cert ls --expiring

# 새 서비스
rbcn new mysvc go --owner=mlops

# 장애 대응
rbcn diag <pod-prefix>

# 백업 확인
rbcn backup ls

# 비용
rbcn cost report
```

---

## 부록 A. 빠진 영역 (외부 의존)

| 항목 | 영향 점수 | 결정 필요 |
|---|---|---|
| Multi-region DR | 1.0 | 별도 DC + 광 회선 (CapEx 큼) |
| 외부 SOC2 Type II | 0.5 | 외부 auditor 비용 |
| WAF/DDoS | 0.5 | Cloudflare/AWS Shield (월 $200+) |
| Public CA 실 발급 | 0.5 | LE 80/443 외부 노출 또는 DNS-01 |
| Cilium eBPF | n/a | CNI 교체 필요 (Calico → Cilium) |

**현재 점수: 9.18/10 (자체 가능 영역 100% 완료)**

---

> **이 문서가 진실의 단일 출처입니다.**
> 다른 문서가 이것과 다르면, 이것이 옳습니다.
> 변경은 PR 로만 (`change-requests/`).

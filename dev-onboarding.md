# RBCN Infra — Developer Onboarding Guide

## 5분 setup

```bash
# 1) ssh access (sysadmin 으로부터 SSH key 받기)
ssh rbcn@<bastion-ip>

# 2) kubeconfig 가져오기
ssh rbcn@<workspace-vm-ip> "tar czf - .kube/" | tar xzf - -C $HOME

# 3) rbcn CLI 사용
rbcn clusters       # cluster 목록
rbcn ctx dev        # KUBECONFIG 환경변수
eval $(rbcn ctx dev)  # 적용
rbcn pods           # pod 목록
rbcn whoami         # current 정보
rbcn svc            # 모든 web UI URL
```

## 자주 쓰는 alias (~/.bashrc)

```bash
alias k=kubectl
alias kgp='kubectl get pod -o wide'
alias kgs='kubectl get svc'
alias kgi='kubectl get ingress'
alias kdp='kubectl describe pod'
alias kl='kubectl logs -f'
alias ke='kubectl exec -it'
alias kk='k9s'
alias kx=kubectx
alias kn=kubens

# rbcn shortcut
alias rdev='eval $(rbcn ctx dev)'
alias rstg='eval $(rbcn ctx stage)'
alias rprd='eval $(rbcn ctx prod)'

# Service URLs (env 별)
alias gf='echo grafana && open https://grafana.${ENV:-dev}.infra.rblnconnect.ai'
```

## Troubleshooting Quick Links

- All Runbooks:     /opt/rbcn-docs/runbooks/
- Recent Incidents: /opt/rbcn-docs/incidents/
- Cost Reports:     /opt/rbcn-docs/cost-reports/
- Service Catalog:  /opt/rbcn-docs/services/

## Debug Workflow

1. **앱 안 됨** → `rbcn pods` → `rbcn logs <pod>`
2. **Pod CrashLoopBackOff** → `kubectl describe pod` → events 확인
3. **Mesh 문제** → Kiali 그래프 + `istioctl proxy-config`
4. **느림** → Grafana 대시보드 (RED method)
5. **Trace 분석** → Tempo/Jaeger via Grafana
6. **CVE 알림** → Trivy ConfigAuditReport

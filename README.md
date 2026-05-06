# rbcn-k8s-platform

ArgoCD App-of-Apps that installs the K8s platform stack on every cluster.

## Stack
- cert-manager + Vault PKI ClusterIssuer
- External-Secrets Operator (Vault backend)
- ingress-nginx
- Kyverno + ClusterPolicies (from rbcn-k8s-policies)
- kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
- promtail (-> Loki on rbcn-obs-loki-vm-01)
- tempo agent
- Velero (-> RGW S3)
- Argo Rollouts
- Falco (DaemonSet)

## Structure
```
root/
├── root-app.yaml         # Application of Applications
applications/
├── cert-manager.yaml
├── external-secrets.yaml
├── ingress-nginx.yaml
├── kyverno.yaml
├── kube-prometheus-stack.yaml
├── promtail.yaml
├── velero.yaml
├── argo-rollouts.yaml
├── falco.yaml
└── ...
```

## Per-environment values
ApplicationSet generators dispatch per env via Helm value overrides.

## Owner
seanlee@rebellions.ai

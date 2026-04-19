# Services ApplicationSet

**한 줄 요약**: services-catalog/services.yaml 에 1줄 추가 → 3환경 ArgoCD Application 자동 생성.

## 동작 원리

```
┌─────────────────────────────────────────────────────────┐
│ services-catalog/services.yaml (Git)                    │
│   - name: my-svc, repo: ..., environments: [dev,...]    │
└─────────────────────────────────────────────────────────┘
                       ↓ git generator
┌─────────────────────────────────────────────────────────┐
│ ApplicationSet (services-appset.yaml)                   │
│  matrix(services × [dev,stage,prod])                    │
└─────────────────────────────────────────────────────────┘
                       ↓ template
┌─────────────────────────────────────────────────────────┐
│ Application 자동 생성:                                   │
│   my-svc-dev    → overlays/dev    (branch: dev)         │
│   my-svc-stage  → overlays/stage  (branch: stage)       │
│   my-svc-prod   → overlays/prod   (branch: prod)        │
└─────────────────────────────────────────────────────────┘
```

## 설치

```bash
kubectl -n argocd apply -f services-appset.yaml
```

## 새 서비스 추가 (1 PR)

```bash
# 1) services-catalog/services.yaml 편집
cat >> /opt/rbcn-docs/services-catalog/services.yaml <<EOF
  - name: my-new-svc
    type: api
    owner: platform
    tier: T1
    repo: https://github.com/rebellions-sw/rbcn-my-new-svc-manifests.git
    environments: [dev, stage, prod]
EOF

# 2) PR + merge → 60초 내 ArgoCD 가 my-new-svc-{dev,stage,prod} 자동 생성
```

## 검증

```bash
kubectl -n argocd get applicationset
kubectl -n argocd get application -l owner=platform
```

## 주의

- `preserveResourcesOnDeletion: false`: 카탈로그에서 entry 삭제 시 Application 도 삭제됨.
- prod 환경은 신중히 추가/제거.
- repo 가 private 이면 ArgoCD repo credentials 필요 (이미 설정됨).

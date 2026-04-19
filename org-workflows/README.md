# Organization Reusable Workflows

이 디렉토리의 workflow 들은 **`rebellions-sw/.github` repo 의 `.github/workflows/`** 에 push 되어
조직 내 모든 repo 가 호출할 수 있는 **단일 진실 (single source of truth)** 입니다.

> **drift = 0**: workflow 변경은 한 곳만 (이 repo). 모든 service repo 는 자동으로 새 버전 사용.

## 파일

| 파일 | 용도 | 호출 측 |
|------|------|---------|
| `reusable-build.yaml`   | Build → SBOM → Trivy → Cosign → Harbor push → dev manifest bump | `<svc>` (app code repo) |
| `reusable-promote.yaml` | dev→stage→prod tag 복사 + PR 생성 | `<svc>-manifests` (manifests repo) |
| `reusable-manifest-validate.yaml` | kustomize build + kubeconform + conftest | `<svc>-manifests` PR |

## 설치 (1회만)

```bash
# rebellions-sw/.github repo 가 없으면 생성:
gh repo create rebellions-sw/.github --public --description "Org-level standards"

# 이 디렉토리를 push:
cd /opt/rbcn-docs/org-workflows
git init
git add .
git commit -m "feat: reusable workflows"
gh repo create rebellions-sw/.github --source=. --remote=origin --public --push
```

## App repo 에서 호출 (.github/workflows/ci.yml)

```yaml
name: ci
on:
  push:
    branches: [main, dev]
  pull_request:
jobs:
  build:
    uses: rebellions-sw/.github/.github/workflows/reusable-build.yaml@main
    with:
      service: my-service
      language: go
    secrets: inherit
```

## Manifests repo 에서 호출 (.github/workflows/promote.yml)

```yaml
name: promote
on:
  workflow_dispatch:
    inputs:
      from: { type: choice, options: [dev, stage] }
      to:   { type: choice, options: [stage, prod] }
jobs:
  promote:
    uses: rebellions-sw/.github/.github/workflows/reusable-promote.yaml@main
    with:
      from: ${{ inputs.from }}
      to:   ${{ inputs.to }}
    secrets: inherit
```

## Manifest PR 검증 (.github/workflows/validate.yml)

```yaml
name: validate
on: [pull_request]
jobs:
  v:
    uses: rebellions-sw/.github/.github/workflows/reusable-manifest-validate.yaml@main
```

## 버전 정책

- `@main` → 항상 최신 (dev). 안정성 필요시 tag 사용.
- `@v1` → semver tag (release 시점에 cut).
- 변경 후에는 모든 service repo 가 다음 push 시 새 workflow 적용 → 사실상 drift 불가.

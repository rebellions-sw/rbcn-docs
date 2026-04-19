# Organization Repository Templates

신규 repo 의 표준 시작점. **`rebellions-sw/<repo-name>`** 생성 시 이 디렉토리의 파일들이 자동 복사됩니다.

## 구조

| 디렉토리 | 용도 |
|---------|------|
| `base-app/`       | 모든 application repo 공통 (CODEOWNERS, PR template, pre-commit, commitlint) |
| `base-manifests/` | 모든 manifests repo 공통 (validate workflow, kustomization 표준) |

## 적용 방법

### 신규 repo (자동)

`rbcn new <svc>` golden path 가 자동으로 이 템플릿을 복사합니다.

### 기존 repo (수동)

```bash
cd path/to/existing-repo
rsync -av --ignore-existing /opt/rbcn-docs/org-templates/base-app/ ./
git add .
git commit -m "chore: adopt org standards"
```

## 표준 항목

| 파일 | 강제? | 효과 |
|------|-------|------|
| `.github/CODEOWNERS`              | YES | 자동 reviewer |
| `.github/PULL_REQUEST_TEMPLATE.md`| YES | PR 일관성 |
| `.github/ISSUE_TEMPLATE/`         | YES | 이슈 일관성 |
| `.pre-commit-config.yaml`         | YES | 로컬 lint, gitleaks, shellcheck |
| `commitlint.config.js`            | YES | conventional commits 강제 |
| `.markdownlint.json`              | YES | 문서 lint |
| `.editorconfig`                   | YES | 들여쓰기 일관성 |
| `SECURITY.md`                     | YES | 취약점 보고 정책 |

## drift 방지

GitHub `repository-rulesets` 또는 `requiredStatusChecks` 로 commitlint/pre-commit 통과 강제 권장.

```bash
gh api -X POST /orgs/rebellions-sw/rulesets ...
```

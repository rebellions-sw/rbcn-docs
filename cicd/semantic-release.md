# 각 앱 repo에 추가할 설정

## `.releaserc.json`
```json
{
  "branches": ["main", {"name": "dev", "prerelease": true}],
  "plugins": [
    ["@semantic-release/commit-analyzer", {
      "preset": "conventionalcommits",
      "releaseRules": [
        {"type": "feat", "release": "minor"},
        {"type": "fix", "release": "patch"},
        {"type": "perf", "release": "patch"},
        {"breaking": true, "release": "major"}
      ]
    }],
    "@semantic-release/release-notes-generator",
    "@semantic-release/changelog",
    "@semantic-release/github",
    ["@semantic-release/git", {
      "assets": ["CHANGELOG.md", "package.json"],
      "message": "chore(release): ${nextRelease.version} [skip ci]"
    }]
  ]
}
```

## `.github/workflows/release.yml`
```yaml
name: Release
on:
  push:
    branches: [main]
jobs:
  release:
    runs-on: [self-hosted, rebel-k8s-runner]
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: actions/setup-node@v4
        with: { node-version: 20 }
      - run: npx semantic-release
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

## Commit convention
- `feat: add user login` → minor (1.1.0)
- `fix: handle null response` → patch (1.0.1)
- `feat!: remove deprecated API` → major (2.0.0)
- `docs: update README` → no release
- `chore:`, `refactor:`, `test:`, `build:` → no release

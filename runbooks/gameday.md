# GameDay Runbook — 분기별 카오스 훈련

> 분기 1회, 의도적인 fault injection 으로 incident response / DR 검증.
> 빅테크 표준 (Netflix Chaos Engineering, AWS Resilience).

---

## 1. 일정 / 참여자

| 항목 | 내용 |
|------|------|
| 주기 | 분기 1회 (Q1=2월, Q2=5월, Q3=8월, Q4=11월) |
| 시간 | 화요일 14:00~16:00 KST (영향 최소) |
| 참여 | plat-team 전원 + 해당 분기 on-call + 해당 service owner |
| 환경 | **stage 클러스터**에서 실행 (prod 는 carve-out 시나리오만, 분기 1회) |
| 사전 공지 | T-3d Slack `#announce` + calendar invite |
| 사후 | 24h 내 retrospective + 발견 사항을 P1 backlog 등록 |

---

## 2. 5 표준 시나리오 (Q마다 1~2개 선택)

### S1: Vault sealed
**목표**: vault 가 sealed 되었을 때 ESO 가 어떻게 행동하고, 새 secret 생성 가능 여부.

```bash
# stage 의 vault leader pod 에서
ssh rbcn@<stage-vault-leader> "vault operator seal"
# → 즉시 alert: VaultSealed
# → 5명 중 3명 unseal 시도
# → ESO 의 SecretSyncedError 가 30s 안에 표시되는지
# → 새 deployment 가 ESO secret 못 받아 Pending 되는지
```

**검증**: [`vault-unseal.md`](./vault-unseal.md) 절차로 5분 안에 복구.

### S2: Postgres primary kill
**목표**: CNPG 가 자동 failover 하는지, 앱이 connection lost 후 자동 재연결.

```bash
# stage payments-db 의 primary 강제 kill
kubectl delete pod -n payments payments-db-1 --force --grace-period=0
# → primary 는 새 pod (예: payments-db-2 promoted)
# → app 의 active connection 들이 1~5초 끊기고 재연결
# → Sentinel-aware redis-go / sqlx 가 새 primary 발견
```

**검증**: 30초 안에 connection 복구, 데이터 손실 0.

### S3: 노드 1대 다운 (drain)
**목표**: PDB / anti-affinity 가 user impact 없는지.

```bash
NODE=$(kubectl get nodes -o name | head -1)
kubectl drain $NODE --ignore-daemonsets --delete-emptydir-data
# → pod 들이 다른 노드로 이동
# → ingress / service 모두 영향 0
# → 5분 후 kubectl uncordon $NODE
```

**검증**: stage 트래픽 5xx 0%, latency P99 변화 < 10%.

### S4: 외부 DNS 다운 (PowerDNS down 시뮬)
**목표**: cluster 내부 통신은 ClusterDNS 라 영향 없어야.

```bash
# stage 의 power-dns VM stop
ssh rbcn@<powerdns-vm> "sudo systemctl stop powerdns"
# → 외부 도메인 (https://payments.stage.infra...) 해석 불가 (외부 client)
# → cluster 내부 service 통신 정상 (ClusterDNS = CoreDNS)
sleep 600
ssh rbcn@<powerdns-vm> "sudo systemctl start powerdns"
```

**검증**: 외부 트래픽 down, 내부 통신 정상. 외부 client retry policy 가 fallback 작동.

### S5: 이미지 registry (Harbor) 다운
**목표**: 새 pod 시작은 못 하지만 기존 pod 는 영향 0.

```bash
ssh rbcn@<harbor-vm> "sudo systemctl stop harbor"
# → 기존 running pod 들 영향 없음
# → 새 deployment / scale-up 시 ImagePullBackOff
# → image-pull caching (registry-mirror) 검증
sleep 600
ssh rbcn@<harbor-vm> "sudo systemctl start harbor"
```

**검증**: HPA 가 scale-up 시도 → cache 가 없으면 fail. 캐시 hit 율 측정 → 이번 분기 P1.

---

## 3. 각 시나리오 공통 체크리스트

```
[ ] T-7d: 시나리오 선정 + 시간 확정 + invite
[ ] T-3d: Slack 공지 + 영향 받는 service owner 들 ack
[ ] T-1d: stage 가 충분히 trafficked 인지 확인 (필요 시 synthetic load)
[ ] T-0:  pre-state snapshot (prom snapshot, k8s state)
[ ] inject fault → 실제 alert 확인 → on-call response 측정
[ ] runbook 대로 복구 → 시간 측정
[ ] post-state snapshot
[ ] 24h 안에 retrospective (5 questions, 아래 §4)
```

---

## 4. Retrospective Template (5 questions)

1. **시나리오**: 무엇을 inject 했나?
2. **알람**: 어떤 alert 이 어떤 lag 로 fire? (목표 < 1m)
3. **응답**: on-call 이 ack → 첫 mitigation step 까지 몇 분?
4. **runbook**: 우리가 가진 runbook 으로 충분했나? gap 은?
5. **action**: 다음 분기 P1 으로 등록할 것 (alert, runbook, code)?

문서: `gameday/YYYY-Q?-S?-<scenario>.md` 에 저장.

---

## 5. 자동화 — 주기 알림

```yaml
# K8s CronJob (kube-system 에 미리 배포)
apiVersion: batch/v1
kind: CronJob
metadata: { name: gameday-reminder }
spec:
  schedule: "0 9 1 2,5,8,11 *"   # 분기 시작 월의 1일 09:00
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: notify
              image: curlimages/curl
              command:
                - /bin/sh
                - -c
                - 'curl -X POST $SLACK_WEBHOOK -d "{\"text\":\"GameDay 분기 알림: 이번 달 셋째 화 14:00 일정 잡으세요. /opt/rbcn-docs/runbooks/gameday.md\"}"'
              envFrom: [{ secretRef: { name: slack-webhook } }]
          restartPolicy: OnFailure
```

---

## 6. 관련 문서

- [`oncall.md`](./oncall.md)
- [`restore-drill.md`](./restore-drill.md)
- [`vault-unseal.md`](./vault-unseal.md)
- [`db-pitr.md`](./db-pitr.md)
- [`../STANDARDS.md`](../STANDARDS.md) §7 DR
- [Netflix Chaos Engineering](https://principlesofchaos.org/)

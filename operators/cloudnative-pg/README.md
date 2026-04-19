# CloudNative-PG (DB Self-Service)

> **목표**: 새 DB 한 장 = `kubectl apply -f db-template.yaml` (수정한 것).

## 설치 (1회/클러스터)

```bash
bash install.sh dev
bash install.sh stage
bash install.sh prod
```

## 새 DB 만들기 (개발자)

```bash
# 방법 1: rbcn CLI
rbcn db create my-svc-db --owner=platform --instances=3

# 방법 2: 매니페스트 직접
cp /opt/rbcn-docs/operators/cloudnative-pg/db-template.yaml /tmp/mydb.yaml
sed -i 's/my-db/my-svc-db/g; s/my-svc/my-svc/g' /tmp/mydb.yaml
kubectl apply -f /tmp/mydb.yaml
```

3분 후 `kubectl get cluster` 확인:

```
NAME       AGE   INSTANCES   READY   STATUS
my-svc-db  3m    3           3       Cluster in healthy state
```

## 연결

```bash
# 서비스에서:
DB_HOST=my-svc-db-rw.my-svc.svc.cluster.local
DB_USER=app
DB_PASS=$(kubectl -n my-svc get secret my-svc-db-app -o jsonpath='{.data.password}' | base64 -d)
DB_NAME=app
```

또는 ExternalSecret (권장):

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata: { name: my-svc-db, namespace: my-svc }
spec:
  refreshInterval: 1h
  secretStoreRef: { name: vault, kind: ClusterSecretStore }
  target: { name: my-svc-db-creds }
  dataFrom:
    - extract:
        key: services/my-svc/db
```

## 작업

| 작업 | 명령 |
|------|------|
| 상태 확인       | `kubectl get cluster -n <ns>` |
| Primary 확인    | `kubectl get pods -n <ns> -L cnpg.io/instanceRole` |
| Failover 강제   | `kubectl cnpg promote <cluster> <pod>` |
| Backup 즉시     | `kubectl cnpg backup <cluster>` |
| PITR 복구       | `kubectl cnpg restore` (run-book 참조) |
| Scale up        | `kubectl patch cluster <c> --type=merge -p '{"spec":{"instances":5}}'` |
| Version upgrade | `kubectl patch cluster ... -p '{"spec":{"imageName":"...:16.4"}}'` |

## 비교

| 옵션 | DR | HA | 운영 부담 | 셀프서비스 |
|------|----|----|-----------|-----------|
| **CloudNative-PG (이 표준)** | barman + PITR + WAL | 자동 failover | 낮음 (operator) | 1 CR |
| Bitnami helm chart           | 수동 백업 스크립트 | 보통 | 중간 | helm install |
| 외부 RDS                     | managed | managed | 매우 낮음 | terraform |
| 단일 pod (demo-postgres)     | 없음 | 없음 | 높음 | 매니페스트 직접 |

> 운영은 CNPG 권장, 외부 의존이 가능하면 RDS, 데모만 단일 pod.

## DR

`/opt/rbcn-docs/dr/dr-runbook/05-pg-pitr.md` 참조.
CNPG 의 PITR 명령어와 호환됩니다.

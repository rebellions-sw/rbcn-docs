#!/bin/bash
# new-service.sh — 새 service 부트스트랩 (5분)
set -e

SVC_NAME="${1:?service name 필수: bash new-service.sh my-svc}"
LANG="${2:-go}"  # go | node | python
OWNER="${OWNER:-platform}"

DIR=/opt/rbcn-docs/services/${SVC_NAME}
echo "→ Creating service: $SVC_NAME (lang=$LANG, owner=$OWNER)"

# 1) Catalog entry
cat > /opt/rbcn-docs/services/${SVC_NAME}.md <<MD
# ${SVC_NAME}

**Type**: TBD
**Owner**: ${OWNER} team
**Slack**: #${OWNER}
**Tier**: 3
**Repo**: TBD
**Image**: harbor.infra.rblnconnect.ai/library/${SVC_NAME}

## Endpoints
- dev:   TBD

## Deployment
- 표준: Argo Rollouts canary
- HPA: min=2 max=5

## Observability
- **Grafana**: 자동 생성 (kube-prometheus-stack)
- **Logs**: Loki — \`{namespace="<ns>", app="${SVC_NAME}"}\`
- **Traces**: Tempo

## Dependencies
TBD

## Runbooks
TBD

## On-call
- Primary: @${OWNER}-oncall
MD

# 2) Update INDEX (간단히 추가)
INDEX=/opt/rbcn-docs/services/INDEX.md
if ! grep -q "${SVC_NAME}" $INDEX; then
    sed -i "/^| Service /a | [${SVC_NAME}](./${SVC_NAME}.md) | TBD | ${OWNER} | #${OWNER} | 3 | TBD | 🚧 |" $INDEX
fi

# 3) Suggested k8s manifest skeleton
mkdir -p $DIR
cat > $DIR/deployment.yaml <<MANIFEST
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${SVC_NAME}
  namespace: <NS>
  labels:
    app: ${SVC_NAME}
    owner: ${OWNER}
    tier: "3"
spec:
  replicas: 2
  selector:
    matchLabels: { app: ${SVC_NAME} }
  template:
    metadata:
      labels: { app: ${SVC_NAME} }
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 1001
        seccompProfile: { type: RuntimeDefault }
      containers:
        - name: ${SVC_NAME}
          image: harbor.infra.rblnconnect.ai/library/${SVC_NAME}:v0.1.0
          ports: [{ containerPort: 8080 }]
          resources:
            requests: { cpu: 50m, memory: 64Mi }
            limits:   { cpu: 200m, memory: 256Mi }
          livenessProbe:
            httpGet: { path: /healthz, port: 8080 }
            initialDelaySeconds: 10
          readinessProbe:
            httpGet: { path: /ready, port: 8080 }
          securityContext:
            allowPrivilegeEscalation: false
            capabilities: { drop: ["ALL"] }
            readOnlyRootFilesystem: true
MANIFEST

cat > $DIR/service.yaml <<MANIFEST
apiVersion: v1
kind: Service
metadata:
  name: ${SVC_NAME}
  namespace: <NS>
spec:
  selector: { app: ${SVC_NAME} }
  ports:
    - port: 80
      targetPort: 8080
      name: http
MANIFEST

cat > $DIR/hpa.yaml <<MANIFEST
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: ${SVC_NAME}-hpa
  namespace: <NS>
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: ${SVC_NAME}
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource: { name: cpu, target: { type: Utilization, averageUtilization: 60 } }
MANIFEST

cat > $DIR/pdb.yaml <<MANIFEST
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: ${SVC_NAME}
  namespace: <NS>
spec:
  minAvailable: 1
  selector: { matchLabels: { app: ${SVC_NAME} } }
MANIFEST

echo ""
echo "✅ Service ${SVC_NAME} created!"
echo ""
echo "Files:"
echo "  - Catalog: /opt/rbcn-docs/services/${SVC_NAME}.md"
echo "  - Skeletons: $DIR/{deployment,service,hpa,pdb}.yaml"
echo ""
echo "Next steps:"
echo "  1. Edit $DIR/*.yaml — replace <NS> with namespace"
echo "  2. git push to repo"
echo "  3. Create ArgoCD Application"
echo "  4. Update INDEX.md with real URLs"

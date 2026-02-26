# Rollback Strategy Guide

## Overview

This document provides comprehensive rollback procedures for the Jenkins-to-EKS CI/CD pipeline. Rollbacks are critical for maintaining service availability when deployments fail or introduce issues.

## Table of Contents

1. [Automatic Rollback](#automatic-rollback)
2. [Manual Rollback](#manual-rollback)
3. [Helm Rollback](#helm-rollback)
4. [Emergency Procedures](#emergency-procedures)
5. [Rollback Testing](#rollback-testing)
6. [Post-Rollback Actions](#post-rollback-actions)

## Automatic Rollback

The Jenkins pipeline includes automatic rollback on deployment failure.

### How It Works

```groovy
post {
  failure {
    script {
      try {
        sh """
          echo "🔄 Attempting automatic rollback..."
          kubectl rollout undo deployment/${env.APP_NAME} -n ${env.PROD_NS}
        """
      } catch (Exception e) {
        echo "⚠️ Automatic rollback failed. Manual intervention required."
      }
    }
  }
}
```

### Triggers

Automatic rollback is triggered when:
- Deployment fails to reach ready state
- Health checks fail
- Timeout exceeded (180 seconds)
- Pod crash loop detected

## Manual Rollback

### Quick Rollback Commands

#### Rollback to Previous Version

```bash
# Staging environment
kubectl rollout undo deployment/fastapi -n staging

# Production environment
kubectl rollout undo deployment/fastapi -n prod
```

#### Rollback to Specific Revision

```bash
# View deployment history
kubectl rollout history deployment/fastapi -n prod

# Output example:
# REVISION  CHANGE-CAUSE
# 1         Initial deployment
# 2         Update to version abc1234
# 3         Update to version def5678

# Rollback to revision 2
kubectl rollout undo deployment/fastapi -n prod --to-revision=2
```

#### Check Rollback Status

```bash
# Monitor rollback progress
kubectl rollout status deployment/fastapi -n prod

# Verify pods are running
kubectl get pods -n prod -l app=fastapi

# Check deployment details
kubectl describe deployment fastapi -n prod
```

### Step-by-Step Manual Rollback

#### Step 1: Identify the Issue

```bash
# Check current deployment status
kubectl get deployments -n prod

# Check pod status
kubectl get pods -n prod

# View pod logs
kubectl logs -l app=fastapi -n prod --tail=100

# Check events
kubectl get events -n prod --sort-by='.lastTimestamp' | head -20
```

#### Step 2: Determine Target Revision

```bash
# View deployment history with details
kubectl rollout history deployment/fastapi -n prod

# View specific revision details
kubectl rollout history deployment/fastapi -n prod --revision=2
```

#### Step 3: Execute Rollback

```bash
# Rollback to previous version
kubectl rollout undo deployment/fastapi -n prod

# Or rollback to specific revision
kubectl rollout undo deployment/fastapi -n prod --to-revision=2
```

#### Step 4: Verify Rollback

```bash
# Wait for rollback to complete
kubectl rollout status deployment/fastapi -n prod --timeout=180s

# Verify all pods are ready
kubectl get pods -n prod -l app=fastapi

# Check service endpoint
kubectl get svc fastapi -n prod

# Test application
LB_URL=$(kubectl get svc fastapi -n prod -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl http://$LB_URL/health
```

## Helm Rollback

### Helm Rollback Commands

#### View Helm Release History

```bash
# List all releases in namespace
helm list -n prod

# View release history
helm history fastapi -n prod

# Output example:
# REVISION  UPDATED                   STATUS      CHART           APP VERSION  DESCRIPTION
# 1         Mon Jan 1 10:00:00 2024   superseded  fastapi-1.0.0   1.0.0       Install complete
# 2         Mon Jan 1 11:00:00 2024   superseded  fastapi-1.0.0   1.0.0       Upgrade complete
# 3         Mon Jan 1 12:00:00 2024   deployed    fastapi-1.0.0   1.0.0       Upgrade complete
```

#### Rollback Helm Release

```bash
# Rollback to previous release
helm rollback fastapi -n prod

# Rollback to specific revision
helm rollback fastapi 2 -n prod

# Rollback with wait
helm rollback fastapi -n prod --wait --timeout 5m

# Dry run (test without applying)
helm rollback fastapi -n prod --dry-run
```

#### Verify Helm Rollback

```bash
# Check release status
helm status fastapi -n prod

# Get release values
helm get values fastapi -n prod

# Get release manifest
helm get manifest fastapi -n prod
```

### Helm Rollback via Jenkins

Create a separate Jenkins job for Helm rollback:

```groovy
pipeline {
  agent any
  
  parameters {
    choice(name: 'ENVIRONMENT', choices: ['staging', 'prod'], description: 'Environment to rollback')
    string(name: 'REVISION', defaultValue: '', description: 'Revision number (leave empty for previous)')
  }
  
  stages {
    stage('Rollback') {
      steps {
        script {
          def rollbackCmd = "helm rollback fastapi -n ${params.ENVIRONMENT} --wait"
          if (params.REVISION) {
            rollbackCmd += " ${params.REVISION}"
          }
          
          sh """
            aws eks update-kubeconfig --region eu-west-2 --name cicd-eks
            ${rollbackCmd}
            kubectl rollout status deployment/fastapi -n ${params.ENVIRONMENT}
          """
        }
      }
    }
    
    stage('Verify') {
      steps {
        sh """
          kubectl get pods -n ${params.ENVIRONMENT}
          kubectl get svc -n ${params.ENVIRONMENT}
        """
      }
    }
  }
}
```

## Emergency Procedures

### Critical Production Issue

#### Immediate Actions (< 5 minutes)

```bash
# 1. Scale down problematic deployment
kubectl scale deployment fastapi -n prod --replicas=0

# 2. Rollback to last known good version
kubectl rollout undo deployment/fastapi -n prod

# 3. Scale up to normal replica count
kubectl scale deployment fastapi -n prod --replicas=3

# 4. Monitor rollout
kubectl rollout status deployment/fastapi -n prod
```

#### Alternative: Switch to Staging

If rollback fails, temporarily route traffic to staging:

```bash
# 1. Scale up staging
kubectl scale deployment fastapi -n staging --replicas=5

# 2. Update DNS or load balancer to point to staging
# (This depends on your DNS/LB configuration)

# 3. Fix production issue
# 4. Redeploy to production
# 5. Switch traffic back
```

### Database Migration Rollback

If deployment includes database migrations:

```bash
# 1. Rollback application first
kubectl rollout undo deployment/fastapi -n prod

# 2. Rollback database migration
# (Depends on your migration tool)
# Example with Alembic:
kubectl exec -it <pod-name> -n prod -- alembic downgrade -1

# 3. Verify application functionality
curl http://$LB_URL/health
```

### Complete Environment Rollback

Rollback entire environment including all services:

```bash
# Create rollback script
cat > rollback-all.sh <<'EOF'
#!/bin/bash
NAMESPACE=$1
REVISION=$2

echo "Rolling back all services in $NAMESPACE to revision $REVISION"

# Get all deployments
DEPLOYMENTS=$(kubectl get deployments -n $NAMESPACE -o jsonpath='{.items[*].metadata.name}')

for DEPLOY in $DEPLOYMENTS; do
  echo "Rolling back $DEPLOY..."
  if [ -z "$REVISION" ]; then
    kubectl rollout undo deployment/$DEPLOY -n $NAMESPACE
  else
    kubectl rollout undo deployment/$DEPLOY -n $NAMESPACE --to-revision=$REVISION
  fi
done

echo "Waiting for rollouts to complete..."
for DEPLOY in $DEPLOYMENTS; do
  kubectl rollout status deployment/$DEPLOY -n $NAMESPACE --timeout=180s
done

echo "Rollback complete!"
EOF

chmod +x rollback-all.sh

# Execute
./rollback-all.sh prod 2
```

## Rollback Testing

### Pre-Production Testing

Test rollback procedures in staging before production:

```bash
# 1. Deploy version 1
helm upgrade --install fastapi ./helm/fastapi -n staging \
  --set image.tag=v1.0.0

# 2. Deploy version 2
helm upgrade fastapi ./helm/fastapi -n staging \
  --set image.tag=v2.0.0

# 3. Test rollback
helm rollback fastapi -n staging

# 4. Verify version 1 is running
kubectl get pods -n staging -o jsonpath='{.items[0].spec.containers[0].image}'
```

### Rollback Drill

Conduct regular rollback drills:

```bash
# Rollback drill script
cat > rollback-drill.sh <<'EOF'
#!/bin/bash
set -e

echo "=== Rollback Drill Started ==="
echo "Current time: $(date)"

# 1. Record current state
echo "Recording current state..."
kubectl get deployment fastapi -n staging -o yaml > pre-rollback-state.yaml

# 2. Perform rollback
echo "Performing rollback..."
kubectl rollout undo deployment/fastapi -n staging

# 3. Wait for completion
echo "Waiting for rollback to complete..."
kubectl rollout status deployment/fastapi -n staging --timeout=180s

# 4. Verify health
echo "Verifying application health..."
kubectl wait --for=condition=ready pod -l app=fastapi -n staging --timeout=120s

# 5. Test endpoints
echo "Testing endpoints..."
SVC_URL=$(kubectl get svc fastapi -n staging -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -f http://$SVC_URL/health || exit 1

echo "=== Rollback Drill Completed Successfully ==="
echo "Duration: $SECONDS seconds"
EOF

chmod +x rollback-drill.sh
./rollback-drill.sh
```

## Post-Rollback Actions

### 1. Incident Documentation

```bash
# Create incident report
cat > incident-report-$(date +%Y%m%d-%H%M%S).md <<EOF
# Incident Report

## Summary
- Date: $(date)
- Environment: Production
- Action: Rollback
- Previous Version: [version]
- Rolled Back To: [version]

## Timeline
- [Time] Issue detected
- [Time] Rollback initiated
- [Time] Rollback completed
- [Time] Service restored

## Root Cause
[Description of what went wrong]

## Impact
- Duration: [X minutes]
- Affected Users: [number/percentage]
- Services Affected: [list]

## Resolution
[How the issue was resolved]

## Prevention
[Steps to prevent recurrence]

## Action Items
- [ ] Fix root cause
- [ ] Update tests
- [ ] Update documentation
- [ ] Review deployment process
EOF
```

### 2. Verify System Health

```bash
# Comprehensive health check
cat > health-check.sh <<'EOF'
#!/bin/bash
NAMESPACE=$1

echo "=== System Health Check ==="

# Check deployments
echo "Deployments:"
kubectl get deployments -n $NAMESPACE

# Check pods
echo -e "\nPods:"
kubectl get pods -n $NAMESPACE

# Check services
echo -e "\nServices:"
kubectl get svc -n $NAMESPACE

# Check resource usage
echo -e "\nResource Usage:"
kubectl top pods -n $NAMESPACE

# Check recent events
echo -e "\nRecent Events:"
kubectl get events -n $NAMESPACE --sort-by='.lastTimestamp' | tail -10

# Test endpoints
echo -e "\nEndpoint Tests:"
SVC_URL=$(kubectl get svc fastapi -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
curl -s http://$SVC_URL/health | jq .
curl -s http://$SVC_URL/ready | jq .

echo -e "\n=== Health Check Complete ==="
EOF

chmod +x health-check.sh
./health-check.sh prod
```

### 3. Notify Stakeholders

```bash
# Send notification (example with Slack)
curl -X POST -H 'Content-type: application/json' \
  --data '{
    "text": "🔄 Production Rollback Completed",
    "attachments": [{
      "color": "warning",
      "fields": [
        {"title": "Environment", "value": "Production", "short": true},
        {"title": "Status", "value": "Restored", "short": true},
        {"title": "Previous Version", "value": "v2.0.0", "short": true},
        {"title": "Current Version", "value": "v1.0.0", "short": true}
      ]
    }]
  }' \
  $SLACK_WEBHOOK_URL
```

### 4. Root Cause Analysis

Schedule and conduct RCA meeting:
- What happened?
- Why did it happen?
- How was it detected?
- How was it resolved?
- How can we prevent it?

### 5. Update Runbooks

Document lessons learned and update procedures.

## Rollback Checklist

### Pre-Rollback

- [ ] Identify the issue
- [ ] Determine target version
- [ ] Notify team members
- [ ] Check rollback history
- [ ] Verify backup availability

### During Rollback

- [ ] Execute rollback command
- [ ] Monitor rollback progress
- [ ] Watch for errors
- [ ] Check pod status
- [ ] Verify service availability

### Post-Rollback

- [ ] Verify application health
- [ ] Test critical endpoints
- [ ] Check logs for errors
- [ ] Monitor metrics
- [ ] Document incident
- [ ] Notify stakeholders
- [ ] Schedule RCA
- [ ] Update runbooks

## Best Practices

1. **Always test rollbacks in staging first**
2. **Keep deployment history (at least 10 revisions)**
3. **Document rollback procedures**
4. **Conduct regular rollback drills**
5. **Monitor application after rollback**
6. **Have a communication plan**
7. **Automate where possible**
8. **Keep rollback scripts updated**
9. **Maintain audit trail**
10. **Learn from each incident**

## Troubleshooting

### Rollback Fails

```bash
# Check deployment status
kubectl describe deployment fastapi -n prod

# Check pod events
kubectl describe pod <pod-name> -n prod

# Check logs
kubectl logs <pod-name> -n prod

# Force delete stuck pods
kubectl delete pod <pod-name> -n prod --force --grace-period=0
```

### Image Not Available

```bash
# List available images in ECR
aws ecr list-images --repository-name fastapi-cicd --region eu-west-2

# If image missing, rebuild and push
# Then update deployment manually
kubectl set image deployment/fastapi fastapi=<ecr-repo>:<tag> -n prod
```

### Database Incompatibility

```bash
# Check database version
kubectl exec -it <pod-name> -n prod -- env | grep DB_VERSION

# Rollback database if needed
# (Depends on your migration tool)
```

## Support

For assistance with rollbacks:
- On-call engineer: [contact]
- Team lead: [contact]
- AWS Support: [case number]
- Escalation procedure: [link]

## References

- [Kubernetes Deployments](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [Helm Rollback](https://helm.sh/docs/helm/helm_rollback/)
- [kubectl Rollout](https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands#rollout)

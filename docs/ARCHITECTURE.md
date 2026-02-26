# Architecture Documentation

## System Architecture Overview

This document describes the complete architecture of the Jenkins-to-EKS CI/CD pipeline, including all components, data flows, and integration points.

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Developer Workflow                          │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                            GitHub                                    │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐             │
│  │ Feature      │  │ Pull Request │  │ Main Branch  │             │
│  │ Branch       │─▶│ Review       │─▶│ (Protected)  │             │
│  └──────────────┘  └──────────────┘  └──────────────┘             │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  │ Webhook Trigger
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    Jenkins CI/CD Server (EC2)                        │
│  ┌──────────────────────────────────────────────────────────────┐  │
│  │                    Pipeline Stages                            │  │
│  │  1. Checkout  →  2. Test  →  3. Build  →  4. Scan           │  │
│  │       ↓              ↓           ↓            ↓              │  │
│  │  5. Push ECR  →  6. Deploy Staging  →  7. Approval          │  │
│  │       ↓              ↓                      ↓                │  │
│  │  8. Deploy Prod  →  9. Verify  →  10. Rollback (if needed)  │  │
│  └──────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────┘
                    │                              │
                    │                              │
                    ▼                              ▼
┌──────────────────────────┐      ┌──────────────────────────────────┐
│     AWS ECR              │      │         AWS EKS Cluster          │
│  ┌────────────────────┐  │      │  ┌────────────────────────────┐ │
│  │ Docker Images      │  │      │  │      Control Plane         │ │
│  │ - Tagged versions  │  │      │  │  (Managed by AWS)          │ │
│  │ - Latest           │  │      │  └────────────────────────────┘ │
│  │ - Scanned          │  │      │              │                  │
│  └────────────────────┘  │      │              ▼                  │
└──────────────────────────┘      │  ┌────────────────────────────┐ │
                                  │  │      Worker Nodes          │ │
                                  │  │  ┌──────────┐ ┌──────────┐ │ │
                                  │  │  │ Staging  │ │   Prod   │ │ │
                                  │  │  │Namespace │ │Namespace │ │ │
                                  │  │  └──────────┘ └──────────┘ │ │
                                  │  └────────────────────────────┘ │
                                  └──────────────────────────────────┘
                                                │
                                                ▼
                                  ┌──────────────────────────────────┐
                                  │    AWS Load Balancer (ALB/NLB)   │
                                  │    - Public endpoint             │
                                  │    - SSL termination             │
                                  └──────────────────────────────────┘
                                                │
                                                ▼
                                  ┌──────────────────────────────────┐
                                  │         End Users                │
                                  └──────────────────────────────────┘
```

## Component Details

### 1. Source Control (GitHub)

**Purpose:** Version control and collaboration platform

**Components:**
- Main branch (protected)
- Feature branches
- Pull requests
- Webhooks

**Security:**
- Branch protection rules
- Required reviews
- Status checks
- Signed commits (optional)

**Integration:**
- Webhook to Jenkins on push events
- GitHub API for status updates

### 2. CI/CD Engine (Jenkins on EC2)

**Purpose:** Orchestrate the entire CI/CD pipeline

**Instance Specifications:**
- Type: t3.medium (2 vCPU, 4 GB RAM)
- OS: Ubuntu 22.04 LTS
- Storage: 30 GB gp3

**Installed Tools:**
- Jenkins 2.x
- Docker 20.10+
- kubectl 1.24+
- Helm 3.8+
- AWS CLI v2
- Trivy (security scanner)
- Python 3.9+

**Jenkins Plugins:**
- Pipeline
- Git
- Docker Pipeline
- Credentials Binding
- Kubernetes CLI
- AWS Credentials

**Security:**
- Security group: Ports 8080 (Jenkins), 22 (SSH)
- IAM role with least privilege
- Credentials stored in Jenkins credential store
- Regular updates and patches

### 3. Container Registry (AWS ECR)

**Purpose:** Store and manage Docker images

**Features:**
- Private repository
- Image scanning on push
- Lifecycle policies (keep last 10 images)
- Encryption at rest
- IAM-based access control

**Image Tagging Strategy:**
```
<account-id>.dkr.ecr.eu-west-2.amazonaws.com/fastapi-cicd:
  - <git-sha>      (e.g., abc1234)
  - latest         (always points to most recent)
  - v1.0.0         (semantic versioning - optional)
```

### 4. Kubernetes Cluster (AWS EKS)

**Purpose:** Container orchestration and deployment

**Cluster Configuration:**
- Version: 1.28
- Region: eu-west-2
- Node type: t3.medium
- Node count: 2 (managed node group)
- Networking: VPC with public/private subnets

**Namespaces:**
- `staging`: Pre-production environment
- `prod`: Production environment
- `kube-system`: System components

**Add-ons:**
- CoreDNS
- kube-proxy
- VPC CNI
- AWS Load Balancer Controller (optional)

### 5. Package Manager (Helm)

**Purpose:** Kubernetes application deployment and management

**Chart Structure:**
```
helm/fastapi/
├── Chart.yaml              # Chart metadata
├── values.yaml             # Default configuration
└── templates/
    ├── deployment.yaml     # Deployment manifest
    ├── service.yaml        # Service manifest
    ├── serviceaccount.yaml # Service account
    ├── hpa.yaml           # Horizontal Pod Autoscaler
    └── _helpers.tpl       # Template helpers
```

**Benefits:**
- Version control for deployments
- Easy rollbacks
- Environment-specific configurations
- Templating and reusability

## Data Flow

### CI Pipeline Flow

```
1. Code Push
   └─▶ GitHub receives commit
       └─▶ Webhook triggers Jenkins

2. Checkout
   └─▶ Jenkins clones repository
       └─▶ Extracts Git SHA for tagging

3. Dependency Installation
   └─▶ Python virtual environment
       └─▶ Install requirements.txt

4. Unit Tests
   └─▶ Run pytest
       └─▶ Generate coverage report

5. Code Quality
   └─▶ Run pylint/flake8
       └─▶ Static analysis

6. Docker Build
   └─▶ Build image with Dockerfile
       └─▶ Tag with Git SHA

7. Security Scan
   └─▶ Trivy scans image
       └─▶ Check for vulnerabilities
       └─▶ Fail on CRITICAL (optional)

8. Push to ECR
   └─▶ Authenticate to ECR
       └─▶ Push tagged image
       └─▶ Push latest tag
```

### CD Pipeline Flow

```
9. Configure kubectl
   └─▶ Update kubeconfig for EKS
       └─▶ Verify cluster connection

10. Deploy to Staging
    └─▶ Helm upgrade/install
        └─▶ Apply manifests
        └─▶ Wait for rollout

11. Smoke Tests
    └─▶ Verify pods running
        └─▶ Check service endpoints
        └─▶ Health check

12. Manual Approval
    └─▶ Jenkins input gate
        └─▶ Human review
        └─▶ Approve/Reject

13. Deploy to Production
    └─▶ Helm upgrade/install
        └─▶ Rolling update
        └─▶ Wait for rollout

14. Verification
    └─▶ Check deployment status
        └─▶ Verify all pods ready
        └─▶ Get LoadBalancer URL

15. Rollback (if failure)
    └─▶ kubectl rollout undo
        └─▶ Restore previous version
```

## Network Architecture

### VPC Configuration

```
VPC (10.0.0.0/16)
│
├── Public Subnets (10.0.1.0/24, 10.0.2.0/24)
│   ├── NAT Gateway
│   ├── Internet Gateway
│   └── Load Balancer
│
└── Private Subnets (10.0.10.0/24, 10.0.11.0/24)
    ├── EKS Worker Nodes
    └── Application Pods
```

### Security Groups

**Jenkins EC2:**
- Inbound: 8080 (HTTP), 22 (SSH)
- Outbound: All traffic

**EKS Nodes:**
- Inbound: From Load Balancer, From other nodes
- Outbound: All traffic

**Load Balancer:**
- Inbound: 80 (HTTP), 443 (HTTPS)
- Outbound: To EKS nodes

## Deployment Strategy

### Rolling Update

Default strategy for zero-downtime deployments:

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1        # Max pods above desired count
    maxUnavailable: 0  # Min pods that must be available
```

**Process:**
1. Create new pod with new version
2. Wait for pod to be ready
3. Terminate old pod
4. Repeat until all pods updated

### Rollback Strategy

**Automatic Rollback:**
- Triggered on deployment failure
- Uses `kubectl rollout undo`

**Manual Rollback:**
```bash
# View history
kubectl rollout history deployment/fastapi -n prod

# Rollback to previous
kubectl rollout undo deployment/fastapi -n prod

# Rollback to specific revision
kubectl rollout undo deployment/fastapi -n prod --to-revision=2
```

## Monitoring and Observability

### Logging

**Application Logs:**
- stdout/stderr captured by Kubernetes
- Accessible via `kubectl logs`

**Jenkins Logs:**
- Build console output
- System logs in `/var/log/jenkins/`

**EKS Logs:**
- Control plane logs to CloudWatch
- Node logs to CloudWatch

### Metrics

**Kubernetes Metrics:**
- CPU and memory usage
- Pod status and health
- Deployment status

**AWS CloudWatch:**
- EC2 metrics (Jenkins)
- EKS cluster metrics
- Load Balancer metrics

### Health Checks

**Liveness Probe:**
```yaml
livenessProbe:
  httpGet:
    path: /health
    port: 8000
  initialDelaySeconds: 30
  periodSeconds: 10
```

**Readiness Probe:**
```yaml
readinessProbe:
  httpGet:
    path: /ready
    port: 8000
  initialDelaySeconds: 10
  periodSeconds: 5
```

## Security Architecture

### Authentication & Authorization

**AWS IAM:**
- Jenkins EC2 instance role
- EKS cluster role
- Node group role
- Service account roles (IRSA)

**Kubernetes RBAC:**
- Service accounts per namespace
- Role-based access control
- Least privilege principle

### Secrets Management

**Options:**
1. AWS Secrets Manager
2. AWS Systems Manager Parameter Store
3. Kubernetes Secrets
4. External Secrets Operator

**Best Practice:**
```bash
# Store in AWS Secrets Manager
aws secretsmanager create-secret \
  --name fastapi/db-password \
  --secret-string "secure-password"

# Reference in Kubernetes
kubectl create secret generic db-creds \
  --from-literal=password=$(aws secretsmanager get-secret-value ...)
```

### Network Security

**Encryption:**
- TLS for all external traffic
- Encryption at rest for ECR
- Encryption at rest for EBS volumes

**Network Policies:**
- Restrict pod-to-pod communication
- Limit egress traffic
- Isolate namespaces

## Scalability

### Horizontal Pod Autoscaling

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
spec:
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 80
```

### Cluster Autoscaling

```bash
# Enable cluster autoscaler
eksctl create cluster \
  --name cicd-eks \
  --nodes-min 2 \
  --nodes-max 10 \
  --node-type t3.medium \
  --asg-access
```

## Disaster Recovery

### Backup Strategy

**What to Backup:**
- Helm release configurations
- Kubernetes manifests
- Jenkins configuration
- ECR images (lifecycle policy)

**Backup Frequency:**
- Daily automated backups
- Before major changes
- Retention: 30 days

### Recovery Procedures

**EKS Cluster Failure:**
1. Create new cluster with eksctl
2. Restore namespaces
3. Redeploy applications with Helm
4. Update DNS records

**Jenkins Failure:**
1. Launch new EC2 instance
2. Restore Jenkins home directory
3. Reconfigure credentials
4. Test pipeline

## Cost Optimization

### Resource Sizing

**Jenkins EC2:**
- Start with t3.medium
- Monitor CPU/memory usage
- Adjust as needed

**EKS Nodes:**
- Use managed node groups
- Enable cluster autoscaler
- Consider spot instances for dev/staging

**ECR:**
- Implement lifecycle policies
- Delete unused images
- Monitor storage costs

### Cost Monitoring

```bash
# Enable cost allocation tags
aws ec2 create-tags \
  --resources <resource-id> \
  --tags Key=Project,Value=CICD Key=Environment,Value=Production

# Use AWS Cost Explorer
# Set up billing alerts
```

## Performance Optimization

### Build Performance

- Use Docker layer caching
- Parallel test execution
- Incremental builds
- Artifact caching

### Deployment Performance

- Pre-pull images on nodes
- Optimize readiness probes
- Use init containers for dependencies
- Implement pod disruption budgets

## Compliance and Auditing

### Audit Logging

**AWS CloudTrail:**
- All API calls logged
- S3 bucket for storage
- CloudWatch integration

**Jenkins Audit:**
- Build history
- User actions
- Configuration changes

### Compliance Requirements

- SOC 2
- GDPR
- HIPAA (if applicable)
- PCI DSS (if applicable)

## Future Enhancements

1. **Multi-region deployment**
   - Active-active setup
   - Cross-region replication

2. **Advanced deployment strategies**
   - Blue-green deployments
   - Canary releases
   - A/B testing

3. **Enhanced monitoring**
   - Prometheus + Grafana
   - ELK stack for logs
   - Distributed tracing

4. **GitOps approach**
   - ArgoCD or Flux
   - Declarative deployments
   - Git as single source of truth

5. **Service mesh**
   - Istio or Linkerd
   - Advanced traffic management
   - Enhanced observability

## References

- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Jenkins Pipeline Documentation](https://www.jenkins.io/doc/book/pipeline/)
- [Helm Documentation](https://helm.sh/docs/)
- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/)

# Jenkins-to-EKS CI/CD on AWS: Complete Pipeline

[![CI/CD Pipeline](https://img.shields.io/badge/CI%2FCD-Jenkins-red)](https://www.jenkins.io/)
[![Kubernetes](https://img.shields.io/badge/Kubernetes-EKS-blue)](https://aws.amazon.com/eks/)
[![Docker](https://img.shields.io/badge/Docker-ECR-orange)](https://aws.amazon.com/ecr/)

## 🚀 Project Overview

A production-grade CI/CD pipeline that automates the complete software delivery lifecycle from code commit to Kubernetes deployment on AWS EKS.

**Pipeline Flow:** Build → Test → Scan → Docker → Push to ECR → Deploy to EKS (Helm) → Verify → Rollback

## 📋 Table of Contents

- [Architecture](#architecture)
- [Pipeline Stages](#pipeline-stages)
- [Prerequisites](#prerequisites)
- [Setup Guide](#setup-guide)
- [Running the Project](#running-the-project)
- [Rollback Strategy](#rollback-strategy)
- [Security](#security)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)

## 🏗️ Architecture

![Architecture Diagram](docs/architecture-diagram.png)

### Components

- **Source Control**: GitHub with webhook triggers
- **CI/CD Engine**: Jenkins on AWS EC2
- **Container Registry**: AWS ECR
- **Orchestration**: AWS EKS (Kubernetes)
- **Package Manager**: Helm Charts
- **Security Scanning**: Trivy
- **Secrets Management**: AWS Secrets Manager / SSM
- **Monitoring**: CloudWatch, Prometheus (optional)

### AWS Resources

```
┌─────────────┐      ┌──────────────┐      ┌─────────────┐
│   GitHub    │─────▶│   Jenkins    │─────▶│   AWS ECR   │
│  (Source)   │      │   (EC2)      │      │  (Registry) │
└─────────────┘      └──────────────┘      └─────────────┘
                            │                      │
                            ▼                      ▼
                     ┌──────────────┐      ┌─────────────┐
                     │   AWS EKS    │◀─────│   Helm      │
                     │  (K8s Cluster)│      │  (Deploy)   │
                     └──────────────┘      └─────────────┘
                            │
                     ┌──────┴──────┐
                     ▼             ▼
              ┌──────────┐  ┌──────────┐
              │ Staging  │  │   Prod   │
              │Namespace │  │Namespace │
              └──────────┘  └──────────┘
```

## 🔄 Pipeline Stages

### 1. Source Control + Triggers
- Developer pushes code to GitHub (feature branch)
- PR created → code review + approvals
- Merge to `main` triggers Jenkins pipeline via webhook

### 2. CI (Build & Validate)
- ✅ Checkout code
- ✅ Install dependencies
- ✅ Run unit tests
- ✅ Build Docker image
- ✅ Static code analysis (optional: SonarQube)
- ✅ Security scans (Trivy)
- ✅ Quality gate validation

### 3. Artifact + Registry
- ✅ Tag image with GIT_COMMIT / semantic version
- ✅ Push image to AWS ECR

### 4. CD to Kubernetes (EKS)
- ✅ Deploy to staging namespace (Helm)
- ✅ Run smoke tests / health checks
- ✅ Manual approval for production
- ✅ Deploy to prod namespace
- ✅ Verify rollout + service reachability
- ✅ Rollback on failure

### 5. Operations
- ✅ Secrets management (AWS SSM/Secrets Manager)
- ✅ Monitoring/logging (CloudWatch)
- ✅ Notifications (Slack/Email)
- ✅ Audit trail (artifact versioning)

## 📦 Prerequisites

### Local Development
- Docker 20.10+
- Python 3.9+
- kubectl 1.24+
- helm 3.8+
- AWS CLI v2
- Git

### AWS Account
- AWS Account with appropriate permissions
- AWS CLI configured with credentials
- IAM user/role with permissions for:
  - EC2 (Jenkins)
  - EKS (Kubernetes cluster)
  - ECR (Container registry)
  - VPC, IAM, CloudWatch

### Tools Installation

```bash
# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Install eksctl
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin

# Install Trivy (security scanner)
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
echo "deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee -a /etc/apt/sources.list.d/trivy.list
sudo apt-get update
sudo apt-get install trivy
```

## 🛠️ Setup Guide

### Step 1: Create ECR Repository

```bash
aws ecr create-repository \
  --repository-name fastapi-cicd \
  --region eu-west-2
```

### Step 2: Create EKS Cluster

```bash
# Using eksctl (recommended)
eksctl create cluster \
  --name cicd-eks \
  --region eu-west-2 \
  --nodes 2 \
  --node-type t3.medium \
  --managed

# Update kubeconfig
aws eks update-kubeconfig --region eu-west-2 --name cicd-eks

# Verify cluster
kubectl get nodes

# Create namespaces
kubectl create namespace staging
kubectl create namespace prod
```

### Step 3: Launch Jenkins on AWS EC2

```bash
# Launch EC2 instance (Ubuntu 22.04, t3.medium)
# Security Group: Allow ports 8080 (Jenkins), 22 (SSH)

# SSH into instance and run:
sudo apt update
sudo apt install -y openjdk-17-jre

# Add Jenkins repository
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | sudo tee \
  /usr/share/keyrings/jenkins-keyring.asc > /dev/null

echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
  https://pkg.jenkins.io/debian-stable binary/ | sudo tee \
  /etc/apt/sources.list.d/jenkins.list > /dev/null

# Install Jenkins
sudo apt update
sudo apt install -y jenkins
sudo systemctl enable --now jenkins

# Install Docker
sudo apt install -y docker.io
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins

# Get initial admin password
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

Access Jenkins at `http://<EC2-PUBLIC-IP>:8080`

### Step 4: Configure Jenkins

#### Install Required Plugins
Navigate to: Manage Jenkins → Manage Plugins → Available

Install:
- Pipeline
- Git
- Docker Pipeline
- Credentials Binding
- Kubernetes CLI
- SonarQube Scanner (optional)
- Slack Notification (optional)

#### Add Credentials
Navigate to: Manage Jenkins → Manage Credentials → Global

1. **AWS Credentials**
   - ID: `aws-creds`
   - Type: AWS Credentials
   - Access Key ID: `<YOUR_AWS_ACCESS_KEY>`
   - Secret Access Key: `<YOUR_AWS_SECRET_KEY>`

2. **GitHub Token** (if private repo)
   - ID: `github-token`
   - Type: Secret text
   - Secret: `<YOUR_GITHUB_TOKEN>`

### Step 5: Configure GitHub Webhook

1. Go to your GitHub repository
2. Settings → Webhooks → Add webhook
3. Configure:
   - Payload URL: `http://<JENKINS-PUBLIC-IP>:8080/github-webhook/`
   - Content type: `application/json`
   - Events: Select "Just the push event"
   - Active: ✅

### Step 6: Create Jenkins Pipeline Job

1. New Item → Pipeline → Name: `fastapi-cicd`
2. Configure:
   - Build Triggers: ✅ GitHub hook trigger for GITScm polling
   - Pipeline:
     - Definition: Pipeline script from SCM
     - SCM: Git
     - Repository URL: `https://github.com/SrinathMLOps/DevOpsCICD.git`
     - Branch: `*/main`
     - Script Path: `Jenkinsfile`

## 🚀 Running the Project

### Local Development

```bash
# Clone repository
git clone https://github.com/SrinathMLOps/DevOpsCICD.git
cd DevOpsCICD

# Run application locally
cd app
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python main.py

# Access at http://localhost:8000
```

### Deploy to Staging

```bash
# Trigger pipeline by pushing to main branch
git add .
git commit -m "Deploy to staging"
git push origin main

# Or manually trigger from Jenkins UI
```

### Deploy to Production

The pipeline includes a manual approval gate before production deployment:
1. Pipeline will pause at "Manual Approval for Production" stage
2. Review staging deployment
3. Click "Deploy" in Jenkins to proceed to production

### Verify Deployment

```bash
# Check staging
kubectl get pods -n staging
kubectl get svc -n staging

# Check production
kubectl get pods -n prod
kubectl get svc -n prod

# Get LoadBalancer URL
kubectl get svc fastapi -n prod -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

## 🔙 Rollback Strategy

### Automatic Rollback

The pipeline includes automatic rollback on deployment failure.

### Manual Rollback

```bash
# Rollback to previous version in staging
kubectl rollout undo deployment/fastapi -n staging

# Rollback to previous version in production
kubectl rollout undo deployment/fastapi -n prod

# Rollback to specific revision
kubectl rollout history deployment/fastapi -n prod
kubectl rollout undo deployment/fastapi -n prod --to-revision=2

# Using Helm
helm rollback fastapi -n prod
helm rollback fastapi 2 -n prod  # Rollback to specific revision
```

### Rollback via Jenkins

Add a separate Jenkins job for rollback:
```groovy
stage("Rollback Production") {
  steps {
    sh "kubectl rollout undo deployment/fastapi -n prod"
  }
}
```

## 🔒 Security

### Image Scanning

Trivy scans for:
- OS vulnerabilities
- Application dependencies
- High and Critical CVEs

Pipeline fails if critical vulnerabilities found.

### Secrets Management

```bash
# Store secrets in AWS Secrets Manager
aws secretsmanager create-secret \
  --name fastapi/db-password \
  --secret-string "your-secret-password"

# Reference in Kubernetes
kubectl create secret generic db-credentials \
  --from-literal=password=$(aws secretsmanager get-secret-value \
    --secret-id fastapi/db-password \
    --query SecretString --output text)
```

### IAM Best Practices

- Use least privilege IAM roles
- Enable MFA for AWS console access
- Rotate credentials regularly
- Use IAM roles for service accounts (IRSA) in EKS

## 📊 Monitoring

### CloudWatch

```bash
# View logs
aws logs tail /aws/eks/cicd-eks/cluster --follow

# Create dashboard
aws cloudwatch put-dashboard \
  --dashboard-name fastapi-metrics \
  --dashboard-body file://cloudwatch-dashboard.json
```

### Kubernetes Monitoring

```bash
# Check pod logs
kubectl logs -f deployment/fastapi -n prod

# Check events
kubectl get events -n prod --sort-by='.lastTimestamp'

# Resource usage
kubectl top nodes
kubectl top pods -n prod
```

## 🐛 Troubleshooting

### Common Issues

**Issue: Pipeline fails at ECR push**
```bash
# Solution: Verify AWS credentials
aws sts get-caller-identity

# Re-authenticate Docker to ECR
aws ecr get-login-password --region eu-west-2 | \
  docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.eu-west-2.amazonaws.com
```

**Issue: kubectl cannot connect to EKS**
```bash
# Solution: Update kubeconfig
aws eks update-kubeconfig --region eu-west-2 --name cicd-eks

# Verify
kubectl cluster-info
```

**Issue: Helm deployment fails**
```bash
# Solution: Check Helm release status
helm list -n staging
helm status fastapi -n staging

# Debug
helm get values fastapi -n staging
kubectl describe pod <pod-name> -n staging
```

**Issue: LoadBalancer pending**
```bash
# Check service
kubectl describe svc fastapi -n prod

# Verify AWS Load Balancer Controller
kubectl get pods -n kube-system | grep aws-load-balancer
```

## 📚 Additional Resources

- [Jenkins Documentation](https://www.jenkins.io/doc/)
- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Helm Documentation](https://helm.sh/docs/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)

## 🤝 Contributing

1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

## 📝 License

This project is licensed under the MIT License.

## 👥 Authors

- **Srinath** - [SrinathMLOps](https://github.com/SrinathMLOps)

## 🙏 Acknowledgments

- AWS for EKS and ECR services
- Jenkins community
- Kubernetes community
- Helm community

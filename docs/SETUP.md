# Complete Setup Guide

## Table of Contents
1. [AWS Prerequisites](#aws-prerequisites)
2. [Jenkins Setup](#jenkins-setup)
3. [EKS Cluster Setup](#eks-cluster-setup)
4. [ECR Repository Setup](#ecr-repository-setup)
5. [GitHub Configuration](#github-configuration)
6. [Pipeline Configuration](#pipeline-configuration)
7. [Verification](#verification)

## AWS Prerequisites

### 1. AWS Account Setup

Ensure you have:
- Active AWS account
- AWS CLI v2 installed and configured
- IAM user with appropriate permissions

### 2. Required IAM Permissions

Create an IAM user with the following policies:
- AmazonEC2FullAccess
- AmazonEKSClusterPolicy
- AmazonEKSWorkerNodePolicy
- AmazonECRFullAccess
- AmazonVPCFullAccess
- IAMFullAccess (for creating service roles)

### 3. Configure AWS CLI

```bash
aws configure
# Enter your AWS Access Key ID
# Enter your AWS Secret Access Key
# Default region: eu-west-2
# Default output format: json

# Verify configuration
aws sts get-caller-identity
```

## Jenkins Setup

### 1. Launch EC2 Instance

```bash
# Create security group
aws ec2 create-security-group \
  --group-name jenkins-sg \
  --description "Security group for Jenkins server" \
  --vpc-id <your-vpc-id>

# Add inbound rules
aws ec2 authorize-security-group-ingress \
  --group-id <sg-id> \
  --protocol tcp \
  --port 8080 \
  --cidr 0.0.0.0/0

aws ec2 authorize-security-group-ingress \
  --group-id <sg-id> \
  --protocol tcp \
  --port 22 \
  --cidr <your-ip>/32

# Launch instance
aws ec2 run-instances \
  --image-id ami-0c76bd4bd302b30ec \
  --instance-type t3.medium \
  --key-name <your-key-pair> \
  --security-group-ids <sg-id> \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=Jenkins-Server}]'
```

### 2. Install Jenkins

SSH into the instance and run:

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Java
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

# Start Jenkins
sudo systemctl enable jenkins
sudo systemctl start jenkins
sudo systemctl status jenkins

# Get initial admin password
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

### 3. Install Docker on Jenkins Server

```bash
# Install Docker
sudo apt install -y docker.io

# Add Jenkins user to docker group
sudo usermod -aG docker jenkins
sudo usermod -aG docker $USER

# Restart Jenkins
sudo systemctl restart jenkins

# Verify Docker installation
docker --version
```

### 4. Install kubectl, helm, and AWS CLI

```bash
# Install kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
kubectl version --client

# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
helm version

# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
sudo apt install -y unzip
unzip awscliv2.zip
sudo ./aws/install
aws --version

# Install eksctl
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
sudo mv /tmp/eksctl /usr/local/bin
eksctl version
```

### 5. Configure Jenkins

1. Access Jenkins at `http://<EC2-PUBLIC-IP>:8080`
2. Enter the initial admin password
3. Install suggested plugins
4. Create admin user
5. Configure Jenkins URL

### 6. Install Required Plugins

Navigate to: Manage Jenkins → Manage Plugins → Available

Install:
- Pipeline
- Git
- GitHub
- Docker Pipeline
- Credentials Binding
- Kubernetes CLI
- AWS Credentials Plugin
- Blue Ocean (optional, for better UI)

### 7. Add Credentials

Navigate to: Manage Jenkins → Manage Credentials → System → Global credentials

#### AWS Credentials
- Kind: AWS Credentials
- ID: `aws-creds`
- Access Key ID: `<YOUR_AWS_ACCESS_KEY_ID>`
- Secret Access Key: `<YOUR_AWS_SECRET_ACCESS_KEY>`
- Description: AWS credentials for ECR and EKS

#### GitHub Token (if private repo)
- Kind: Secret text
- Secret: `<YOUR_GITHUB_PERSONAL_ACCESS_TOKEN>`
- ID: `github-token`
- Description: GitHub access token

## EKS Cluster Setup

### 1. Create EKS Cluster

```bash
# Using eksctl (recommended)
eksctl create cluster \
  --name cicd-eks \
  --region eu-west-2 \
  --nodes 2 \
  --node-type t3.medium \
  --managed \
  --version 1.28

# This will take 15-20 minutes
```

### 2. Configure kubectl

```bash
# Update kubeconfig
aws eks update-kubeconfig --region eu-west-2 --name cicd-eks

# Verify connection
kubectl get nodes
kubectl cluster-info
```

### 3. Create Namespaces

```bash
# Create staging namespace
kubectl create namespace staging

# Create production namespace
kubectl create namespace prod

# Verify
kubectl get namespaces
```

### 4. Install AWS Load Balancer Controller (Optional)

```bash
# Download IAM policy
curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.6.0/docs/install/iam_policy.json

# Create IAM policy
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam_policy.json

# Create service account
eksctl create iamserviceaccount \
  --cluster=cicd-eks \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --attach-policy-arn=arn:aws:iam::<ACCOUNT_ID>:policy/AWSLoadBalancerControllerIAMPolicy \
  --approve

# Install controller using Helm
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=cicd-eks \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller
```

## ECR Repository Setup

### 1. Create ECR Repository

```bash
# Create repository
aws ecr create-repository \
  --repository-name fastapi-cicd \
  --region eu-west-2 \
  --image-scanning-configuration scanOnPush=true

# Get repository URI
aws ecr describe-repositories \
  --repository-names fastapi-cicd \
  --region eu-west-2 \
  --query 'repositories[0].repositoryUri' \
  --output text
```

### 2. Configure ECR Lifecycle Policy (Optional)

```bash
# Create lifecycle policy to keep only last 10 images
cat > lifecycle-policy.json <<EOF
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Keep last 10 images",
      "selection": {
        "tagStatus": "any",
        "countType": "imageCountMoreThan",
        "countNumber": 10
      },
      "action": {
        "type": "expire"
      }
    }
  ]
}
EOF

aws ecr put-lifecycle-policy \
  --repository-name fastapi-cicd \
  --lifecycle-policy-text file://lifecycle-policy.json
```

## GitHub Configuration

### 1. Create GitHub Repository

```bash
# Initialize git repository
git init
git add .
git commit -m "Initial commit: Jenkins to EKS CI/CD pipeline"
git branch -M main
git remote add origin https://github.com/SrinathMLOps/DevOpsCICD.git
git push -u origin main
```

### 2. Configure Webhook

1. Go to your GitHub repository
2. Navigate to Settings → Webhooks → Add webhook
3. Configure:
   - Payload URL: `http://<JENKINS-PUBLIC-IP>:8080/github-webhook/`
   - Content type: `application/json`
   - SSL verification: Enable (if using HTTPS)
   - Events: Select "Just the push event"
   - Active: ✅

### 3. Branch Protection (Recommended)

1. Settings → Branches → Add rule
2. Branch name pattern: `main`
3. Enable:
   - Require pull request reviews before merging
   - Require status checks to pass before merging
   - Require branches to be up to date before merging

## Pipeline Configuration

### 1. Create Jenkins Pipeline Job

1. Jenkins Dashboard → New Item
2. Enter name: `fastapi-cicd-pipeline`
3. Select: Pipeline
4. Click OK

### 2. Configure Pipeline

**General:**
- Description: "CI/CD pipeline for FastAPI to EKS"
- ✅ Discard old builds (Keep last 10 builds)

**Build Triggers:**
- ✅ GitHub hook trigger for GITScm polling

**Pipeline:**
- Definition: Pipeline script from SCM
- SCM: Git
- Repository URL: `https://github.com/SrinathMLOps/DevOpsCICD.git`
- Credentials: (select github-token if private)
- Branch Specifier: `*/main`
- Script Path: `Jenkinsfile`

### 3. Configure Jenkins on EC2 with AWS Credentials

```bash
# SSH into Jenkins EC2
ssh -i <key-pair>.pem ubuntu@<jenkins-public-ip>

# Configure AWS CLI for Jenkins user
sudo su - jenkins
aws configure
# Enter AWS credentials
```

## Verification

### 1. Test Pipeline

```bash
# Make a change and push
echo "# Test" >> README.md
git add README.md
git commit -m "Test pipeline trigger"
git push origin main
```

### 2. Monitor Pipeline

1. Go to Jenkins Dashboard
2. Click on your pipeline job
3. Watch the build progress
4. Check console output for each stage

### 3. Verify Deployment

```bash
# Check staging deployment
kubectl get pods -n staging
kubectl get svc -n staging

# Check production deployment (after approval)
kubectl get pods -n prod
kubectl get svc -n prod

# Get application URL
kubectl get svc fastapi -n prod -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# Test application
curl http://<loadbalancer-url>/health
```

### 4. Access Application

```bash
# Get LoadBalancer URL
LB_URL=$(kubectl get svc fastapi -n prod -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Test endpoints
curl http://$LB_URL/
curl http://$LB_URL/health
curl http://$LB_URL/info
```

## Troubleshooting

### Jenkins Cannot Connect to EKS

```bash
# On Jenkins server, verify AWS credentials
aws sts get-caller-identity

# Update kubeconfig
aws eks update-kubeconfig --region eu-west-2 --name cicd-eks

# Test connection
kubectl get nodes
```

### Docker Permission Denied

```bash
# Add jenkins user to docker group
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins
```

### ECR Authentication Failed

```bash
# Re-authenticate
aws ecr get-login-password --region eu-west-2 | \
  docker login --username AWS --password-stdin <account-id>.dkr.ecr.eu-west-2.amazonaws.com
```

### Helm Deployment Failed

```bash
# Check Helm release
helm list -n staging
helm status fastapi -n staging

# Debug
kubectl describe pod <pod-name> -n staging
kubectl logs <pod-name> -n staging
```

## Next Steps

1. Configure monitoring with Prometheus/Grafana
2. Set up log aggregation with ELK stack
3. Implement blue-green or canary deployments
4. Add SonarQube for code quality
5. Configure Slack notifications
6. Implement automated rollback strategies
7. Add performance testing stage
8. Configure backup and disaster recovery

## Security Best Practices

1. Use IAM roles instead of access keys where possible
2. Enable MFA for AWS console access
3. Rotate credentials regularly
4. Use AWS Secrets Manager for sensitive data
5. Enable audit logging (CloudTrail)
6. Implement network policies in Kubernetes
7. Use Pod Security Policies
8. Regular security scanning with Trivy
9. Keep all tools and dependencies updated
10. Implement least privilege access

## Cost Optimization

1. Use spot instances for non-production workloads
2. Enable cluster autoscaling
3. Right-size your EC2 instances
4. Use ECR lifecycle policies
5. Delete unused resources
6. Monitor costs with AWS Cost Explorer
7. Use reserved instances for production

## Support

For issues or questions:
- GitHub Issues: https://github.com/SrinathMLOps/DevOpsCICD/issues
- Documentation: See README.md
- AWS Support: https://aws.amazon.com/support/

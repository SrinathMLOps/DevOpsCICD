# Quick Start Guide

Get your Jenkins-to-EKS CI/CD pipeline up and running in minutes!

## Prerequisites

- AWS Account with appropriate permissions
- GitHub account
- Basic knowledge of Docker, Kubernetes, and AWS

## 5-Minute Local Setup

### 1. Clone and Setup

```bash
# Clone the repository
git clone https://github.com/SrinathMLOps/DevOpsCICD.git
cd DevOpsCICD

# Run local setup script
chmod +x scripts/setup-local.sh
./scripts/setup-local.sh

# Start the application
cd app
source .venv/bin/activate
python main.py
```

Visit http://localhost:8000 to see your app running!

## 30-Minute AWS Setup

### Step 1: Create ECR Repository (2 minutes)

```bash
aws ecr create-repository \
  --repository-name fastapi-cicd \
  --region eu-west-2
```

### Step 2: Create EKS Cluster (15 minutes)

```bash
eksctl create cluster \
  --name cicd-eks \
  --region eu-west-2 \
  --nodes 2 \
  --node-type t3.medium

# Create namespaces
kubectl create namespace staging
kubectl create namespace prod
```

### Step 3: Launch Jenkins (10 minutes)

```bash
# Launch EC2 instance (Ubuntu 22.04, t3.medium)
# Security Group: Allow 8080, 22

# SSH into instance
ssh -i your-key.pem ubuntu@<ec2-ip>

# Install Jenkins
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key | sudo tee \
  /usr/share/keyrings/jenkins-keyring.asc > /dev/null
echo deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] \
  https://pkg.jenkins.io/debian-stable binary/ | sudo tee \
  /etc/apt/sources.list.d/jenkins.list > /dev/null
sudo apt update
sudo apt install -y openjdk-17-jre jenkins docker.io
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins

# Get initial password
sudo cat /var/lib/jenkins/secrets/initialAdminPassword
```

### Step 4: Configure Jenkins (3 minutes)

1. Access Jenkins at http://<ec2-ip>:8080
2. Install suggested plugins
3. Add AWS credentials (Manage Jenkins → Credentials)
4. Create pipeline job pointing to your GitHub repo

### Step 5: Configure GitHub Webhook (1 minute)

1. Go to your GitHub repo → Settings → Webhooks
2. Add webhook: http://<jenkins-ip>:8080/github-webhook/
3. Select "Just the push event"

### Step 6: Deploy! (1 minute)

```bash
# Push code to trigger pipeline
git add .
git commit -m "Trigger deployment"
git push origin main
```

Watch your pipeline run in Jenkins!

## Verify Deployment

```bash
# Check staging
kubectl get pods -n staging
kubectl get svc -n staging

# Check production (after approval)
kubectl get pods -n prod
kubectl get svc -n prod

# Get application URL
kubectl get svc fastapi -n prod -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

## Test Your Application

```bash
# Get LoadBalancer URL
LB_URL=$(kubectl get svc fastapi -n prod -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Test endpoints
curl http://$LB_URL/
curl http://$LB_URL/health
curl http://$LB_URL/info
```

## Common Commands

### Jenkins
```bash
# Restart Jenkins
sudo systemctl restart jenkins

# View logs
sudo journalctl -u jenkins -f
```

### Kubernetes
```bash
# View pods
kubectl get pods -n prod

# View logs
kubectl logs -f <pod-name> -n prod

# Describe pod
kubectl describe pod <pod-name> -n prod
```

### Rollback
```bash
# Rollback deployment
kubectl rollout undo deployment/fastapi -n prod

# Using Helm
helm rollback fastapi -n prod
```

## Troubleshooting

### Pipeline fails at Docker stage
```bash
sudo usermod -aG docker jenkins
sudo systemctl restart jenkins
```

### Cannot connect to EKS
```bash
aws eks update-kubeconfig --region eu-west-2 --name cicd-eks
kubectl get nodes
```

### Pods stuck in Pending
```bash
kubectl describe pod <pod-name> -n <namespace>
kubectl get nodes
```

## Next Steps

1. ✅ Review [Complete Setup Guide](docs/SETUP.md)
2. ✅ Read [Architecture Documentation](docs/ARCHITECTURE.md)
3. ✅ Implement [Security Best Practices](docs/SECURITY.md)
4. ✅ Set up monitoring and alerting
5. ✅ Configure automated backups

## Need Help?

- 📖 [Full Documentation](README.md)
- 🔧 [Troubleshooting Guide](docs/TROUBLESHOOTING.md)
- 🐛 [Report Issues](https://github.com/SrinathMLOps/DevOpsCICD/issues)
- 💬 [Discussions](https://github.com/SrinathMLOps/DevOpsCICD/discussions)

## Estimated Costs

- Jenkins EC2 (t3.medium): ~$30/month
- EKS Control Plane: $73/month
- EKS Nodes (2x t3.medium): ~$60/month
- Load Balancer: ~$20/month
- **Total: ~$183/month**

Use AWS Free Tier where applicable to reduce costs!

---

**Ready to deploy?** Let's go! 🚀

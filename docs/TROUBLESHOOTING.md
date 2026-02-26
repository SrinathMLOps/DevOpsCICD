# Troubleshooting Guide

## Common Issues and Solutions

### Jenkins Issues

#### Issue: Jenkins Cannot Start

**Symptoms:**
- Jenkins service fails to start
- Port 8080 not accessible

**Solutions:**

```bash
# Check Jenkins status
sudo systemctl status jenkins

# Check logs
sudo journalctl -u jenkins -n 50

# Check if port is already in use
sudo netstat -tulpn | grep 8080

# Restart Jenkins
sudo systemctl restart jenkins

# Check Java version
java -version  # Should be Java 11 or 17
```

#### Issue: Jenkins Build Fails at Docker Stage

**Symptoms:**
- "Permission denied" when running Docker commands
- "Cannot connect to Docker daemon"

**Solutions:**

```bash
# Add jenkins user to docker group
sudo usermod -aG docker jenkins

# Restart Jenkins
sudo systemctl restart jenkins

# Verify docker group membership
groups jenkins

# Test Docker access
sudo -u jenkins docker ps
```

#### Issue: AWS Credentials Not Working

**Symptoms:**
- "Unable to locate credentials"
- "Access Denied" errors

**Solutions:**

```bash
# Verify AWS credentials in Jenkins
# Manage Jenkins → Manage Credentials → Check aws-creds

# Test AWS CLI as jenkins user
sudo -u jenkins aws sts get-caller-identity

# Configure AWS CLI for jenkins user
sudo su - jenkins
aws configure
```

### EKS Issues

#### Issue: Cannot Connect to EKS Cluster

**Symptoms:**
- "error: You must be logged in to the server"
- "Unable to connect to the server"

**Solutions:**

```bash
# Update kubeconfig
aws eks update-kubeconfig --region eu-west-2 --name cicd-eks

# Verify AWS credentials
aws sts get-caller-identity

# Check cluster status
aws eks describe-cluster --name cicd-eks --region eu-west-2

# Test connection
kubectl get nodes

# Check kubeconfig
cat ~/.kube/config
```

#### Issue: Pods Stuck in Pending State

**Symptoms:**
- Pods remain in "Pending" status
- No nodes available

**Solutions:**

```bash
# Check pod events
kubectl describe pod <pod-name> -n <namespace>

# Check node status
kubectl get nodes

# Check node resources
kubectl top nodes

# Check pod resource requests
kubectl describe pod <pod-name> -n <namespace> | grep -A 5 "Requests"

# Scale node group if needed
eksctl scale nodegroup \
  --cluster=cicd-eks \
  --name=<nodegroup-name> \
  --nodes=3 \
  --nodes-min=2 \
  --nodes-max=5
```

#### Issue: Pods CrashLoopBackOff

**Symptoms:**
- Pods continuously restarting
- Status shows "CrashLoopBackOff"

**Solutions:**

```bash
# Check pod logs
kubectl logs <pod-name> -n <namespace>

# Check previous logs
kubectl logs <pod-name> -n <namespace> --previous

# Describe pod for events
kubectl describe pod <pod-name> -n <namespace>

# Check resource limits
kubectl describe pod <pod-name> -n <namespace> | grep -A 10 "Limits"

# Common fixes:
# 1. Fix application errors in code
# 2. Adjust resource limits
# 3. Fix environment variables
# 4. Check image availability
```

### ECR Issues

#### Issue: Cannot Push to ECR

**Symptoms:**
- "denied: Your authorization token has expired"
- "no basic auth credentials"

**Solutions:**

```bash
# Re-authenticate to ECR
aws ecr get-login-password --region eu-west-2 | \
  docker login --username AWS --password-stdin <account-id>.dkr.ecr.eu-west-2.amazonaws.com

# Verify repository exists
aws ecr describe-repositories --repository-names fastapi-cicd --region eu-west-2

# Check IAM permissions
aws iam get-user
aws iam list-attached-user-policies --user-name <username>

# Test push with a simple image
docker pull alpine
docker tag alpine <account-id>.dkr.ecr.eu-west-2.amazonaws.com/fastapi-cicd:test
docker push <account-id>.dkr.ecr.eu-west-2.amazonaws.com/fastapi-cicd:test
```

#### Issue: Image Not Found in ECR

**Symptoms:**
- "ImagePullBackOff" in Kubernetes
- "repository does not exist"

**Solutions:**

```bash
# List images in repository
aws ecr list-images --repository-name fastapi-cicd --region eu-west-2

# Check image tag
aws ecr describe-images \
  --repository-name fastapi-cicd \
  --image-ids imageTag=<tag> \
  --region eu-west-2

# Verify image URI in deployment
kubectl get deployment <deployment-name> -n <namespace> -o yaml | grep image:

# Pull image manually to test
docker pull <ecr-repo>:<tag>
```

### Helm Issues

#### Issue: Helm Deployment Fails

**Symptoms:**
- "Error: INSTALLATION FAILED"
- "Error: UPGRADE FAILED"

**Solutions:**

```bash
# Check Helm release status
helm list -n <namespace>
helm status <release-name> -n <namespace>

# Get detailed error
helm get manifest <release-name> -n <namespace>

# Validate chart
helm lint ./helm/fastapi

# Dry run to test
helm upgrade --install <release-name> ./helm/fastapi \
  -n <namespace> \
  --dry-run --debug

# Check values
helm get values <release-name> -n <namespace>

# Uninstall and reinstall if needed
helm uninstall <release-name> -n <namespace>
helm install <release-name> ./helm/fastapi -n <namespace>
```

#### Issue: Helm Rollback Fails

**Symptoms:**
- "Error: ROLLBACK FAILED"
- Previous revision not found

**Solutions:**

```bash
# Check release history
helm history <release-name> -n <namespace>

# Verify revision exists
helm history <release-name> -n <namespace> | grep <revision>

# Force rollback
helm rollback <release-name> <revision> -n <namespace> --force

# If all else fails, redeploy
helm uninstall <release-name> -n <namespace>
helm install <release-name> ./helm/fastapi -n <namespace>
```

### Networking Issues

#### Issue: LoadBalancer Stuck in Pending

**Symptoms:**
- Service type LoadBalancer shows "Pending" for EXTERNAL-IP
- Cannot access application

**Solutions:**

```bash
# Check service status
kubectl describe svc <service-name> -n <namespace>

# Check events
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# Verify AWS Load Balancer Controller
kubectl get pods -n kube-system | grep aws-load-balancer

# Check service annotations
kubectl get svc <service-name> -n <namespace> -o yaml

# Check security groups
aws ec2 describe-security-groups --filters "Name=tag:kubernetes.io/cluster/cicd-eks,Values=owned"

# Manually create load balancer (if needed)
# Or change service type to NodePort temporarily
kubectl patch svc <service-name> -n <namespace> -p '{"spec":{"type":"NodePort"}}'
```

#### Issue: Cannot Access Application

**Symptoms:**
- LoadBalancer URL returns timeout
- Connection refused

**Solutions:**

```bash
# Get LoadBalancer URL
kubectl get svc <service-name> -n <namespace>

# Test from within cluster
kubectl run -it --rm debug --image=alpine --restart=Never -- sh
# Inside pod:
apk add curl
curl http://<service-name>.<namespace>.svc.cluster.local:8000/health

# Check pod logs
kubectl logs -l app=<app-name> -n <namespace>

# Check security groups
# Ensure LoadBalancer security group allows inbound traffic

# Check target group health
aws elbv2 describe-target-health --target-group-arn <tg-arn>

# Verify service endpoints
kubectl get endpoints <service-name> -n <namespace>
```

### Pipeline Issues

#### Issue: Pipeline Fails at Checkout Stage

**Symptoms:**
- "Failed to connect to repository"
- "Authentication failed"

**Solutions:**

```bash
# Verify GitHub webhook
# GitHub → Settings → Webhooks → Check recent deliveries

# Check Jenkins credentials
# Manage Jenkins → Manage Credentials → Verify github-token

# Test git access from Jenkins
sudo -u jenkins git ls-remote https://github.com/SrinathMLOps/DevOpsCICD.git

# Check Jenkins logs
sudo tail -f /var/log/jenkins/jenkins.log
```

#### Issue: Pipeline Fails at Test Stage

**Symptoms:**
- Tests fail unexpectedly
- Import errors

**Solutions:**

```bash
# Run tests locally
cd app
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
pip install pytest
pytest tests/ -v

# Check Python version
python --version

# Check dependencies
pip list

# Update requirements.txt if needed
pip freeze > requirements.txt
```

#### Issue: Pipeline Timeout

**Symptoms:**
- Pipeline exceeds time limit
- Stages hang indefinitely

**Solutions:**

```groovy
// Add timeout to pipeline
options {
  timeout(time: 1, unit: 'HOURS')
}

// Add timeout to specific stage
stage('Deploy') {
  options {
    timeout(time: 10, unit: 'MINUTES')
  }
  steps {
    // ...
  }
}
```

```bash
# Check for hanging processes
ps aux | grep jenkins

# Check system resources
top
df -h
free -m

# Restart Jenkins if needed
sudo systemctl restart jenkins
```

### Security Scanning Issues

#### Issue: Trivy Scan Fails

**Symptoms:**
- "command not found: trivy"
- Scan timeout

**Solutions:**

```bash
# Install Trivy
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
echo "deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee -a /etc/apt/sources.list.d/trivy.list
sudo apt-get update
sudo apt-get install trivy

# Verify installation
trivy --version

# Update Trivy database
trivy image --download-db-only

# Test scan
trivy image alpine:latest

# Increase timeout in Jenkinsfile
sh """
  trivy image --timeout 10m ${env.ECR_REPO}:${env.IMAGE_TAG}
"""
```

### Resource Issues

#### Issue: Out of Disk Space

**Symptoms:**
- "No space left on device"
- Build fails with disk errors

**Solutions:**

```bash
# Check disk usage
df -h

# Find large files
du -sh /* | sort -rh | head -10

# Clean Docker images
docker system prune -a -f

# Clean Jenkins workspace
sudo rm -rf /var/lib/jenkins/workspace/*

# Clean old logs
sudo find /var/log -type f -name "*.log" -mtime +30 -delete

# Increase EBS volume size
aws ec2 modify-volume --volume-id <vol-id> --size 50
# Then resize filesystem
sudo growpart /dev/xvda 1
sudo resize2fs /dev/xvda1
```

#### Issue: Out of Memory

**Symptoms:**
- "Out of memory" errors
- Pods evicted
- Jenkins crashes

**Solutions:**

```bash
# Check memory usage
free -m
kubectl top nodes
kubectl top pods -n <namespace>

# Increase Jenkins heap size
sudo vi /etc/default/jenkins
# Add: JAVA_ARGS="-Xmx2048m"
sudo systemctl restart jenkins

# Adjust pod resource limits
kubectl edit deployment <deployment-name> -n <namespace>
# Increase memory limits

# Scale up EC2 instance
# Stop instance, change instance type, start instance

# Add more nodes to EKS
eksctl scale nodegroup \
  --cluster=cicd-eks \
  --name=<nodegroup-name> \
  --nodes=3
```

## Debugging Commands

### Kubernetes Debugging

```bash
# Get all resources
kubectl get all -n <namespace>

# Describe resource
kubectl describe <resource-type> <resource-name> -n <namespace>

# Get logs
kubectl logs <pod-name> -n <namespace>
kubectl logs <pod-name> -n <namespace> --previous
kubectl logs -f <pod-name> -n <namespace>  # Follow logs

# Execute command in pod
kubectl exec -it <pod-name> -n <namespace> -- /bin/sh

# Port forward
kubectl port-forward <pod-name> 8000:8000 -n <namespace>

# Get events
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# Check resource usage
kubectl top nodes
kubectl top pods -n <namespace>

# Get YAML
kubectl get <resource-type> <resource-name> -n <namespace> -o yaml
```

### Docker Debugging

```bash
# List images
docker images

# List containers
docker ps -a

# View logs
docker logs <container-id>

# Execute command
docker exec -it <container-id> /bin/sh

# Inspect image
docker inspect <image-name>

# Check disk usage
docker system df

# Clean up
docker system prune -a
```

### AWS Debugging

```bash
# Check AWS credentials
aws sts get-caller-identity

# List EKS clusters
aws eks list-clusters --region eu-west-2

# Describe cluster
aws eks describe-cluster --name cicd-eks --region eu-west-2

# List ECR repositories
aws ecr describe-repositories --region eu-west-2

# List EC2 instances
aws ec2 describe-instances --region eu-west-2

# Check CloudWatch logs
aws logs tail /aws/eks/cicd-eks/cluster --follow
```

## Getting Help

### Log Locations

- Jenkins: `/var/log/jenkins/jenkins.log`
- Kubernetes: `kubectl logs <pod-name> -n <namespace>`
- Docker: `docker logs <container-id>`
- System: `/var/log/syslog`

### Useful Resources

- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [AWS EKS Troubleshooting](https://docs.aws.amazon.com/eks/latest/userguide/troubleshooting.html)
- [Jenkins Documentation](https://www.jenkins.io/doc/)
- [Docker Documentation](https://docs.docker.com/)
- [Helm Documentation](https://helm.sh/docs/)

### Support Channels

- GitHub Issues: https://github.com/SrinathMLOps/DevOpsCICD/issues
- AWS Support: https://aws.amazon.com/support/
- Kubernetes Slack: https://kubernetes.slack.com/
- Stack Overflow: Tag questions with relevant tags

## Preventive Measures

1. **Regular Monitoring**
   - Set up CloudWatch alarms
   - Monitor resource usage
   - Review logs regularly

2. **Automated Testing**
   - Run tests before deployment
   - Use staging environment
   - Implement smoke tests

3. **Documentation**
   - Keep runbooks updated
   - Document changes
   - Maintain architecture diagrams

4. **Backups**
   - Regular backups of configurations
   - Version control everything
   - Test restore procedures

5. **Updates**
   - Keep tools updated
   - Patch security vulnerabilities
   - Update dependencies regularly

# Security Guide

## Overview

This document outlines security best practices, configurations, and procedures for the Jenkins-to-EKS CI/CD pipeline.

## Security Principles

1. **Least Privilege Access**: Grant minimum necessary permissions
2. **Defense in Depth**: Multiple layers of security controls
3. **Zero Trust**: Verify every request
4. **Encryption Everywhere**: Data in transit and at rest
5. **Regular Audits**: Continuous security monitoring

## AWS Security

### IAM Best Practices

#### Jenkins EC2 IAM Role

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:GetAuthorizationToken",
        "ecr:BatchCheckLayerAvailability",
        "ecr:GetDownloadUrlForLayer",
        "ecr:PutImage",
        "ecr:InitiateLayerUpload",
        "ecr:UploadLayerPart",
        "ecr:CompleteLayerUpload"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "eks:DescribeCluster",
        "eks:ListClusters"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "secretsmanager:GetSecretValue"
      ],
      "Resource": "arn:aws:secretsmanager:*:*:secret:fastapi/*"
    }
  ]
}
```

#### EKS Cluster Role

```bash
# Create EKS cluster role
aws iam create-role \
  --role-name EKSClusterRole \
  --assume-role-policy-document file://eks-cluster-trust-policy.json

# Attach required policies
aws iam attach-role-policy \
  --role-name EKSClusterRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonEKSClusterPolicy
```

### Security Groups

#### Jenkins EC2 Security Group

```bash
# Create security group
aws ec2 create-security-group \
  --group-name jenkins-sg \
  --description "Jenkins server security group"

# Allow SSH from specific IP only
aws ec2 authorize-security-group-ingress \
  --group-id <sg-id> \
  --protocol tcp \
  --port 22 \
  --cidr <your-ip>/32

# Allow Jenkins UI from VPN/office network
aws ec2 authorize-security-group-ingress \
  --group-id <sg-id> \
  --protocol tcp \
  --port 8080 \
  --cidr <office-network>/24
```

#### EKS Node Security Group

```bash
# Managed by EKS, but verify:
# - Allow traffic from Load Balancer
# - Allow inter-node communication
# - Deny all other inbound traffic
```

### Secrets Management

#### AWS Secrets Manager

```bash
# Store database password
aws secretsmanager create-secret \
  --name fastapi/db-password \
  --description "Database password for FastAPI" \
  --secret-string "your-secure-password"

# Store API keys
aws secretsmanager create-secret \
  --name fastapi/api-key \
  --secret-string "your-api-key"

# Rotate secrets regularly
aws secretsmanager rotate-secret \
  --secret-id fastapi/db-password \
  --rotation-lambda-arn <lambda-arn>
```

#### AWS Systems Manager Parameter Store

```bash
# Store configuration parameters
aws ssm put-parameter \
  --name /fastapi/config/db-host \
  --value "db.example.com" \
  --type String

# Store secure strings
aws ssm put-parameter \
  --name /fastapi/config/db-password \
  --value "secure-password" \
  --type SecureString
```

### Encryption

#### ECR Encryption

```bash
# Enable encryption at rest (default)
aws ecr put-image-scanning-configuration \
  --repository-name fastapi-cicd \
  --image-scanning-configuration scanOnPush=true

# Use KMS for encryption
aws ecr create-repository \
  --repository-name fastapi-cicd \
  --encryption-configuration encryptionType=KMS,kmsKey=<kms-key-id>
```

#### EKS Encryption

```bash
# Enable secrets encryption
eksctl create cluster \
  --name cicd-eks \
  --region eu-west-2 \
  --encryption-config \
    --key-arn=<kms-key-arn> \
    --resources=secrets
```

## Container Security

### Image Scanning with Trivy

#### Scan Configuration

```bash
# Install Trivy
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
echo "deb https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee -a /etc/apt/sources.list.d/trivy.list
sudo apt-get update
sudo apt-get install trivy

# Scan image
trivy image --severity HIGH,CRITICAL <image-name>

# Generate report
trivy image --format json --output report.json <image-name>

# Fail on critical vulnerabilities
trivy image --severity CRITICAL --exit-code 1 <image-name>
```

#### Automated Scanning in Pipeline

Already integrated in Jenkinsfile:

```groovy
stage("Security Scan - Trivy") {
  steps {
    sh """
      trivy image --severity HIGH,CRITICAL --format table ${env.ECR_REPO}:${env.IMAGE_TAG}
      trivy image --severity CRITICAL --exit-code 1 ${env.ECR_REPO}:${env.IMAGE_TAG}
    """
  }
}
```

### Dockerfile Security

#### Secure Dockerfile Practices

```dockerfile
# Use specific version tags, not 'latest'
FROM python:3.9-slim

# Run as non-root user
RUN useradd -m -u 1000 appuser
USER appuser

# Don't include secrets in image
# Use build args for non-sensitive config only

# Minimize attack surface
RUN apt-get update && \
    apt-get install -y --no-install-recommends <packages> && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Use COPY instead of ADD
COPY requirements.txt .

# Set read-only root filesystem (if possible)
# Configure in Kubernetes deployment
```

### Image Signing

```bash
# Install Cosign
wget https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64
sudo mv cosign-linux-amd64 /usr/local/bin/cosign
sudo chmod +x /usr/local/bin/cosign

# Generate key pair
cosign generate-key-pair

# Sign image
cosign sign --key cosign.key <image-name>

# Verify signature
cosign verify --key cosign.pub <image-name>
```

## Kubernetes Security

### Pod Security

#### Pod Security Context

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: fastapi
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: fastapi
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
        - ALL
```

#### Network Policies

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: fastapi-network-policy
  namespace: prod
spec:
  podSelector:
    matchLabels:
      app: fastapi
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          name: prod
    ports:
    - protocol: TCP
      port: 8000
  egress:
  - to:
    - namespaceSelector: {}
    ports:
    - protocol: TCP
      port: 443  # HTTPS
    - protocol: TCP
      port: 5432  # PostgreSQL (if needed)
```

### RBAC Configuration

#### Service Account

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: fastapi-sa
  namespace: prod
```

#### Role

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: fastapi-role
  namespace: prod
rules:
- apiGroups: [""]
  resources: ["configmaps", "secrets"]
  verbs: ["get", "list"]
```

#### RoleBinding

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: fastapi-rolebinding
  namespace: prod
subjects:
- kind: ServiceAccount
  name: fastapi-sa
  namespace: prod
roleRef:
  kind: Role
  name: fastapi-role
  apiGroup: rbac.authorization.k8s.io
```

### Secrets in Kubernetes

#### Create Secret from AWS Secrets Manager

```bash
# Fetch secret from AWS
SECRET_VALUE=$(aws secretsmanager get-secret-value \
  --secret-id fastapi/db-password \
  --query SecretString \
  --output text)

# Create Kubernetes secret
kubectl create secret generic db-credentials \
  --from-literal=password=$SECRET_VALUE \
  -n prod

# Use in deployment
```

```yaml
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      containers:
      - name: fastapi
        env:
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: password
```

#### External Secrets Operator

```bash
# Install External Secrets Operator
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets \
  external-secrets/external-secrets \
  -n external-secrets-system \
  --create-namespace

# Create SecretStore
kubectl apply -f - <<EOF
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets-manager
  namespace: prod
spec:
  provider:
    aws:
      service: SecretsManager
      region: eu-west-2
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
EOF

# Create ExternalSecret
kubectl apply -f - <<EOF
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: fastapi-secrets
  namespace: prod
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secrets-manager
    kind: SecretStore
  target:
    name: fastapi-secrets
    creationPolicy: Owner
  data:
  - secretKey: db-password
    remoteRef:
      key: fastapi/db-password
EOF
```

## Jenkins Security

### Jenkins Hardening

#### Security Configuration

1. **Enable CSRF Protection**
   - Manage Jenkins → Configure Global Security
   - ✅ Prevent Cross Site Request Forgery exploits

2. **Configure Authentication**
   - Use Jenkins' own user database
   - Or integrate with LDAP/Active Directory
   - Enable "Matrix-based security"

3. **Disable Unnecessary Features**
   - Disable CLI over remoting
   - Disable JNLP protocols
   - Remove unused plugins

4. **Enable Audit Logging**
   - Install "Audit Trail" plugin
   - Configure log location
   - Monitor user actions

#### Credentials Management

```groovy
// Use credentials binding in pipeline
withCredentials([
  [$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-creds']
]) {
  sh 'aws s3 ls'
}

// Never print credentials
// BAD: sh "echo $AWS_SECRET_ACCESS_KEY"
// GOOD: Use credentials binding
```

### Jenkins Plugins Security

```bash
# Keep plugins updated
# Manage Jenkins → Manage Plugins → Updates

# Remove unused plugins
# Manage Jenkins → Manage Plugins → Installed

# Review plugin security advisories
# https://www.jenkins.io/security/advisories/
```

## Network Security

### TLS/SSL Configuration

#### Load Balancer SSL

```yaml
apiVersion: v1
kind: Service
metadata:
  name: fastapi
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-ssl-cert: <acm-cert-arn>
    service.beta.kubernetes.io/aws-load-balancer-backend-protocol: http
    service.beta.kubernetes.io/aws-load-balancer-ssl-ports: "443"
spec:
  type: LoadBalancer
  ports:
  - port: 443
    targetPort: 8000
    protocol: TCP
```

#### Ingress with TLS

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: fastapi-ingress
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  tls:
  - hosts:
    - api.example.com
    secretName: fastapi-tls
  rules:
  - host: api.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: fastapi
            port:
              number: 80
```

### VPC Configuration

```bash
# Create VPC with public and private subnets
eksctl create cluster \
  --name cicd-eks \
  --region eu-west-2 \
  --vpc-public-subnets subnet-xxx,subnet-yyy \
  --vpc-private-subnets subnet-aaa,subnet-bbb

# Enable VPC Flow Logs
aws ec2 create-flow-logs \
  --resource-type VPC \
  --resource-ids <vpc-id> \
  --traffic-type ALL \
  --log-destination-type cloud-watch-logs \
  --log-group-name /aws/vpc/flowlogs
```

## Compliance and Auditing

### AWS CloudTrail

```bash
# Enable CloudTrail
aws cloudtrail create-trail \
  --name fastapi-cicd-trail \
  --s3-bucket-name <bucket-name>

# Start logging
aws cloudtrail start-logging \
  --name fastapi-cicd-trail

# Enable log file validation
aws cloudtrail update-trail \
  --name fastapi-cicd-trail \
  --enable-log-file-validation
```

### Kubernetes Audit Logging

```bash
# Enable audit logging in EKS
# Create audit policy
cat > audit-policy.yaml <<EOF
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
- level: Metadata
  resources:
  - group: ""
    resources: ["secrets", "configmaps"]
- level: RequestResponse
  resources:
  - group: ""
    resources: ["pods"]
EOF

# Apply to cluster (requires cluster recreation with eksctl)
```

### Security Scanning Schedule

```bash
# Daily vulnerability scan
0 2 * * * trivy image --severity HIGH,CRITICAL <image> > /var/log/trivy/scan-$(date +\%Y\%m\%d).log

# Weekly compliance check
0 3 * * 0 kube-bench run --targets master,node > /var/log/kube-bench/scan-$(date +\%Y\%m\%d).log
```

## Incident Response

### Security Incident Procedure

1. **Detection**
   - Monitor alerts
   - Review logs
   - Investigate anomalies

2. **Containment**
   - Isolate affected resources
   - Block malicious traffic
   - Revoke compromised credentials

3. **Eradication**
   - Remove malware
   - Patch vulnerabilities
   - Update security controls

4. **Recovery**
   - Restore from backups
   - Verify system integrity
   - Resume normal operations

5. **Lessons Learned**
   - Document incident
   - Update procedures
   - Improve defenses

### Emergency Contacts

```yaml
Security Team:
  - Primary: security@example.com
  - On-call: +1-xxx-xxx-xxxx

AWS Support:
  - Account: xxx-xxx-xxxx
  - Support Plan: Enterprise

Incident Response:
  - Runbook: /docs/incident-response.md
  - Escalation: /docs/escalation-matrix.md
```

## Security Checklist

### Pre-Deployment

- [ ] All secrets stored securely
- [ ] IAM roles follow least privilege
- [ ] Security groups properly configured
- [ ] Images scanned for vulnerabilities
- [ ] TLS/SSL certificates valid
- [ ] Network policies applied
- [ ] RBAC configured correctly
- [ ] Audit logging enabled

### Post-Deployment

- [ ] Verify no secrets in logs
- [ ] Check security group rules
- [ ] Review IAM permissions
- [ ] Test authentication
- [ ] Verify encryption
- [ ] Check network policies
- [ ] Review audit logs
- [ ] Scan running containers

### Regular Maintenance

- [ ] Rotate credentials monthly
- [ ] Update dependencies weekly
- [ ] Review access logs daily
- [ ] Scan images daily
- [ ] Update security policies quarterly
- [ ] Conduct security training quarterly
- [ ] Perform penetration testing annually
- [ ] Review and update documentation

## Security Tools

### Recommended Tools

1. **Trivy** - Container vulnerability scanning
2. **kube-bench** - CIS Kubernetes benchmark
3. **Falco** - Runtime security monitoring
4. **OPA** - Policy enforcement
5. **Vault** - Secrets management
6. **Cert-manager** - Certificate management
7. **Istio** - Service mesh security
8. **Aqua Security** - Container security platform

## References

- [AWS Security Best Practices](https://aws.amazon.com/security/best-practices/)
- [Kubernetes Security](https://kubernetes.io/docs/concepts/security/)
- [OWASP Top 10](https://owasp.org/www-project-top-ten/)
- [CIS Benchmarks](https://www.cisecurity.org/cis-benchmarks/)
- [NIST Cybersecurity Framework](https://www.nist.gov/cyberframework)

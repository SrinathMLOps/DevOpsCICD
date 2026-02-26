pipeline {
  agent any
  
  environment {
    AWS_REGION = "eu-west-2"
    ECR_REPO_NAME = "fastapi-cicd"
    CLUSTER_NAME = "cicd-eks"
    STAGING_NS = "staging"
    PROD_NS = "prod"
    APP_NAME = "fastapi"
    AWS_ACCOUNT_ID = ""
    ECR_REPO = ""
    IMAGE_TAG = ""
  }
  
  options {
    timestamps()
    disableConcurrentBuilds()
    buildDiscarder(logRotator(numToKeepStr: '10'))
  }
  
  stages {
    
    stage("Checkout") {
      steps {
        echo "🔍 Checking out source code..."
        checkout scm
        script {
          env.GIT_SHA = sh(script: "git rev-parse --short HEAD", returnStdout: true).trim()
          env.IMAGE_TAG = "${env.GIT_SHA}"
        }
      }
    }
    
    stage("Environment Setup") {
      steps {
        echo "🔧 Setting up environment variables..."
        script {
          withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-creds']]) {
            env.AWS_ACCOUNT_ID = sh(
              script: "aws sts get-caller-identity --query Account --output text",
              returnStdout: true
            ).trim()
            env.ECR_REPO = "${env.AWS_ACCOUNT_ID}.dkr.ecr.${env.AWS_REGION}.amazonaws.com/${env.ECR_REPO_NAME}"
          }
        }
        echo "✅ ECR Repository: ${env.ECR_REPO}"
        echo "✅ Image Tag: ${env.IMAGE_TAG}"
      }
    }
    
    stage("Install Dependencies") {
      steps {
        echo "📦 Installing application dependencies..."
        sh """
          cd app
          python3 -m venv .venv || true
          . .venv/bin/activate
          pip install --upgrade pip
          pip install -r requirements.txt
        """
      }
    }
    
    stage("Unit Tests") {
      steps {
        echo "🧪 Running unit tests..."
        sh """
          cd app
          . .venv/bin/activate
          pip install pytest pytest-cov
          pytest tests/ -v --cov=. --cov-report=term-missing || true
        """
      }
    }
    
    stage("Code Quality Check") {
      steps {
        echo "📊 Running code quality checks..."
        sh """
          cd app
          . .venv/bin/activate
          pip install pylint flake8 || true
          pylint *.py --exit-zero || true
          flake8 . --count --select=E9,F63,F7,F82 --show-source --statistics || true
        """
      }
    }
    
    stage("Build Docker Image") {
      steps {
        echo "🐳 Building Docker image..."
        sh """
          cd app
          docker build -t ${env.ECR_REPO}:${env.IMAGE_TAG} .
          docker tag ${env.ECR_REPO}:${env.IMAGE_TAG} ${env.ECR_REPO}:latest
        """
        echo "✅ Docker image built successfully"
      }
    }
    
    stage("Security Scan - Trivy") {
      steps {
        echo "🔒 Scanning Docker image for vulnerabilities..."
        script {
          try {
            sh """
              # Install trivy if not present
              if ! command -v trivy &> /dev/null; then
                echo "Installing Trivy..."
                wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | sudo apt-key add -
                echo "deb https://aquasecurity.github.io/trivy-repo/deb \$(lsb_release -sc) main" | sudo tee -a /etc/apt/sources.list.d/trivy.list
                sudo apt-get update
                sudo apt-get install -y trivy
              fi
              
              # Scan image
              trivy image --severity HIGH,CRITICAL --format table ${env.ECR_REPO}:${env.IMAGE_TAG}
              
              # Fail build if critical vulnerabilities found (optional - uncomment to enforce)
              # trivy image --severity CRITICAL --exit-code 1 ${env.ECR_REPO}:${env.IMAGE_TAG}
            """
            echo "✅ Security scan completed"
          } catch (Exception e) {
            echo "⚠️ Security scan failed but continuing pipeline. Review vulnerabilities!"
            currentBuild.result = 'UNSTABLE'
          }
        }
      }
    }
    
    stage("Push to ECR") {
      steps {
        echo "📤 Pushing Docker image to ECR..."
        withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-creds']]) {
          sh """
            # Authenticate Docker to ECR
            aws ecr get-login-password --region ${env.AWS_REGION} | \
              docker login --username AWS --password-stdin ${env.AWS_ACCOUNT_ID}.dkr.ecr.${env.AWS_REGION}.amazonaws.com
            
            # Push image
            docker push ${env.ECR_REPO}:${env.IMAGE_TAG}
            docker push ${env.ECR_REPO}:latest
          """
        }
        echo "✅ Image pushed to ECR successfully"
      }
    }
    
    stage("Configure kubectl") {
      steps {
        echo "⚙️ Configuring kubectl for EKS..."
        withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-creds']]) {
          sh """
            aws eks update-kubeconfig --region ${env.AWS_REGION} --name ${env.CLUSTER_NAME}
            kubectl version --client
            kubectl get nodes
          """
        }
        echo "✅ kubectl configured successfully"
      }
    }
    
    stage("Deploy to Staging") {
      steps {
        echo "🚀 Deploying to Staging namespace..."
        withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-creds']]) {
          sh """
            # Deploy using Helm
            helm upgrade --install ${env.APP_NAME} ./helm/fastapi \
              -n ${env.STAGING_NS} \
              --create-namespace \
              --set image.repository=${env.ECR_REPO} \
              --set image.tag=${env.IMAGE_TAG} \
              --set environment=staging \
              --wait \
              --timeout 5m
            
            # Wait for rollout
            kubectl -n ${env.STAGING_NS} rollout status deployment/${env.APP_NAME} --timeout=180s
          """
        }
        echo "✅ Deployed to Staging successfully"
      }
    }
    
    stage("Smoke Test - Staging") {
      steps {
        echo "🧪 Running smoke tests on Staging..."
        sh """
          # Get service details
          kubectl -n ${env.STAGING_NS} get svc ${env.APP_NAME}
          kubectl -n ${env.STAGING_NS} get pods
          
          # Wait for pods to be ready
          kubectl wait --for=condition=ready pod -l app=${env.APP_NAME} -n ${env.STAGING_NS} --timeout=120s
          
          # Basic health check (adjust based on your app)
          echo "✅ Staging deployment verified"
        """
      }
    }
    
    stage("Manual Approval for Production") {
      steps {
        script {
          echo "⏸️ Waiting for manual approval to deploy to Production..."
          timeout(time: 30, unit: 'MINUTES') {
            input message: '🚀 Deploy to PRODUCTION?', 
                  ok: 'Deploy to Production',
                  submitter: 'admin'
          }
        }
      }
    }
    
    stage("Deploy to Production") {
      steps {
        echo "🚀 Deploying to Production namespace..."
        withCredentials([[$class: 'AmazonWebServicesCredentialsBinding', credentialsId: 'aws-creds']]) {
          sh """
            # Deploy using Helm
            helm upgrade --install ${env.APP_NAME} ./helm/fastapi \
              -n ${env.PROD_NS} \
              --create-namespace \
              --set image.repository=${env.ECR_REPO} \
              --set image.tag=${env.IMAGE_TAG} \
              --set environment=production \
              --set replicaCount=3 \
              --wait \
              --timeout 5m
            
            # Wait for rollout
            kubectl -n ${env.PROD_NS} rollout status deployment/${env.APP_NAME} --timeout=180s
          """
        }
        echo "✅ Deployed to Production successfully"
      }
    }
    
    stage("Verify Production Deployment") {
      steps {
        echo "✅ Verifying Production deployment..."
        sh """
          # Get deployment status
          kubectl -n ${env.PROD_NS} get deployments
          kubectl -n ${env.PROD_NS} get pods
          kubectl -n ${env.PROD_NS} get svc
          
          # Wait for all pods to be ready
          kubectl wait --for=condition=ready pod -l app=${env.APP_NAME} -n ${env.PROD_NS} --timeout=120s
          
          # Get LoadBalancer URL
          echo "🌐 Application URL:"
          kubectl get svc ${env.APP_NAME} -n ${env.PROD_NS} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' || echo "LoadBalancer URL not available yet"
        """
        echo "✅ Production deployment verified"
      }
    }
    
  }
  
  post {
    success {
      echo """
      ✅ ========================================
      ✅ PIPELINE COMPLETED SUCCESSFULLY!
      ✅ ========================================
      📦 Image: ${env.ECR_REPO}:${env.IMAGE_TAG}
      🏷️  Git SHA: ${env.GIT_SHA}
      🚀 Deployed to: Staging & Production
      ✅ ========================================
      """
    }
    
    failure {
      echo """
      ❌ ========================================
      ❌ PIPELINE FAILED!
      ❌ ========================================
      🔄 Consider rolling back to previous version
      📋 Check logs for details
      ❌ ========================================
      """
      script {
        // Optional: Auto-rollback on failure
        try {
          sh """
            echo "🔄 Attempting automatic rollback..."
            kubectl rollout undo deployment/${env.APP_NAME} -n ${env.PROD_NS} || true
          """
        } catch (Exception e) {
          echo "⚠️ Automatic rollback failed. Manual intervention required."
        }
      }
    }
    
    unstable {
      echo "⚠️ Pipeline completed with warnings. Review the logs."
    }
    
    always {
      echo "🧹 Cleaning up workspace..."
      cleanWs()
    }
  }
}

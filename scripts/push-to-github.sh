#!/bin/bash

# Script to initialize git repository and push to GitHub
# Usage: ./scripts/push-to-github.sh

set -e

echo "========================================="
echo "  Jenkins-to-EKS CI/CD Pipeline Setup"
echo "========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Check if git is installed
if ! command -v git &> /dev/null; then
    echo -e "${RED}Error: git is not installed${NC}"
    echo "Please install git first: sudo apt-get install git"
    exit 1
fi

# Repository URL
REPO_URL="https://github.com/SrinathMLOps/DevOpsCICD.git"

echo -e "${YELLOW}Step 1: Initializing git repository...${NC}"
if [ -d ".git" ]; then
    echo -e "${YELLOW}Git repository already initialized${NC}"
else
    git init
    echo -e "${GREEN}✓ Git repository initialized${NC}"
fi

echo ""
echo -e "${YELLOW}Step 2: Adding files to git...${NC}"
git add .
echo -e "${GREEN}✓ Files added to staging${NC}"

echo ""
echo -e "${YELLOW}Step 3: Creating initial commit...${NC}"
git commit -m "Initial commit: Complete Jenkins-to-EKS CI/CD pipeline

Features:
- Complete CI/CD pipeline with Jenkins
- Docker containerization
- AWS ECR integration
- EKS deployment with Helm
- Security scanning with Trivy
- Automated testing
- Manual approval gates
- Automatic rollback
- Comprehensive documentation

Components:
- FastAPI application
- Jenkinsfile with full pipeline
- Helm charts for Kubernetes
- Complete documentation
- Setup and troubleshooting guides
- Security best practices
- Architecture diagrams
"
echo -e "${GREEN}✓ Initial commit created${NC}"

echo ""
echo -e "${YELLOW}Step 4: Setting main branch...${NC}"
git branch -M main
echo -e "${GREEN}✓ Branch set to main${NC}"

echo ""
echo -e "${YELLOW}Step 5: Adding remote repository...${NC}"
if git remote | grep -q "origin"; then
    echo -e "${YELLOW}Remote 'origin' already exists, updating URL...${NC}"
    git remote set-url origin $REPO_URL
else
    git remote add origin $REPO_URL
fi
echo -e "${GREEN}✓ Remote repository added${NC}"

echo ""
echo -e "${YELLOW}Step 6: Pushing to GitHub...${NC}"
echo -e "${YELLOW}You may be prompted for GitHub credentials${NC}"
echo ""

# Try to push
if git push -u origin main; then
    echo ""
    echo -e "${GREEN}=========================================${NC}"
    echo -e "${GREEN}  ✓ Successfully pushed to GitHub!${NC}"
    echo -e "${GREEN}=========================================${NC}"
    echo ""
    echo -e "Repository URL: ${GREEN}$REPO_URL${NC}"
    echo ""
    echo "Next steps:"
    echo "1. Configure GitHub webhook for Jenkins"
    echo "2. Set up AWS infrastructure (EKS, ECR)"
    echo "3. Configure Jenkins pipeline"
    echo "4. Run your first deployment!"
    echo ""
    echo "See docs/SETUP.md for detailed instructions"
else
    echo ""
    echo -e "${RED}=========================================${NC}"
    echo -e "${RED}  ✗ Failed to push to GitHub${NC}"
    echo -e "${RED}=========================================${NC}"
    echo ""
    echo "Possible issues:"
    echo "1. Authentication failed - check your GitHub credentials"
    echo "2. Repository doesn't exist - create it on GitHub first"
    echo "3. No internet connection"
    echo ""
    echo "To retry manually:"
    echo "  git push -u origin main"
    echo ""
    echo "To use SSH instead of HTTPS:"
    echo "  git remote set-url origin git@github.com:SrinathMLOps/DevOpsCICD.git"
    echo "  git push -u origin main"
    exit 1
fi

#!/bin/bash

# Script to set up local development environment
# Usage: ./scripts/setup-local.sh

set -e

echo "========================================="
echo "  Local Development Setup"
echo "========================================="
echo ""

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check Python
echo -e "${YELLOW}Checking Python installation...${NC}"
if ! command -v python3 &> /dev/null; then
    echo "Python 3 is not installed. Please install Python 3.9 or higher."
    exit 1
fi
PYTHON_VERSION=$(python3 --version)
echo -e "${GREEN}✓ $PYTHON_VERSION${NC}"

# Create virtual environment
echo ""
echo -e "${YELLOW}Creating virtual environment...${NC}"
cd app
if [ -d ".venv" ]; then
    echo "Virtual environment already exists"
else
    python3 -m venv .venv
    echo -e "${GREEN}✓ Virtual environment created${NC}"
fi

# Activate virtual environment
echo ""
echo -e "${YELLOW}Activating virtual environment...${NC}"
source .venv/bin/activate
echo -e "${GREEN}✓ Virtual environment activated${NC}"

# Install dependencies
echo ""
echo -e "${YELLOW}Installing dependencies...${NC}"
pip install --upgrade pip
pip install -r requirements.txt
pip install pytest pytest-cov
echo -e "${GREEN}✓ Dependencies installed${NC}"

# Run tests
echo ""
echo -e "${YELLOW}Running tests...${NC}"
pytest tests/ -v
echo -e "${GREEN}✓ Tests passed${NC}"

# Run application
echo ""
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}  Setup Complete!${NC}"
echo -e "${GREEN}=========================================${NC}"
echo ""
echo "To run the application:"
echo "  cd app"
echo "  source .venv/bin/activate"
echo "  python main.py"
echo ""
echo "Or with uvicorn:"
echo "  uvicorn main:app --reload"
echo ""
echo "Access the application at: http://localhost:8000"
echo "API documentation at: http://localhost:8000/docs"

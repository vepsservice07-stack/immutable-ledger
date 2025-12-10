#!/bin/bash
# ImmutableLedger Environment Setup Script
# Run this before working on the ImmutableLedger project

set -e

# Color output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== ImmutableLedger Environment Setup ===${NC}"

# Project Configuration
export PROJECT_ID="immutable-ledger"
export REGION="us-east1"
export CLUSTER_NAME="immutable-ledger-autopilot"
export NAMESPACE="immutable-ledger"
export REQUIRED_ACCOUNT="vepsservice07@gmail.com"

# Check and switch to correct account
CURRENT_ACCOUNT=$(gcloud config get-value account 2>/dev/null)

if [ "$CURRENT_ACCOUNT" != "$REQUIRED_ACCOUNT" ]; then
    echo -e "${YELLOW}Current account: ${CURRENT_ACCOUNT}${NC}"
    echo -e "${YELLOW}Switching to required account: ${REQUIRED_ACCOUNT}${NC}"
    
    # Check if the required account exists
    if gcloud auth list --format="value(account)" | grep -q "^${REQUIRED_ACCOUNT}$"; then
        gcloud config set account ${REQUIRED_ACCOUNT}
        echo -e "${GREEN}✓ Switched to ${REQUIRED_ACCOUNT}${NC}"
    else
        echo -e "${YELLOW}Account ${REQUIRED_ACCOUNT} not found. Please login:${NC}"
        gcloud auth login ${REQUIRED_ACCOUNT}
    fi
else
    echo -e "${GREEN}✓ Using correct account: ${CURRENT_ACCOUNT}${NC}"
fi

# Set gcloud configuration
echo -e "${GREEN}Setting gcloud project to: ${PROJECT_ID}${NC}"
gcloud config set project ${PROJECT_ID}

echo -e "${GREEN}Setting default region to: ${REGION}${NC}"
gcloud config set compute/region ${REGION}

# Get cluster credentials (Autopilot uses region, not zone)
echo -e "${GREEN}Configuring kubectl for cluster: ${CLUSTER_NAME}${NC}"
gcloud container clusters get-credentials ${CLUSTER_NAME} --region ${REGION}

# Set kubectl default namespace
echo -e "${GREEN}Setting kubectl default namespace to: ${NAMESPACE}${NC}"
kubectl config set-context --current --namespace=${NAMESPACE}

# Display current configuration
echo ""
echo -e "${BLUE}=== Current Configuration ===${NC}"
echo "Account: ${REQUIRED_ACCOUNT}"
echo "Project ID: ${PROJECT_ID}"
echo "Region: ${REGION}"
echo "Cluster: ${CLUSTER_NAME} (Autopilot)"
echo "Namespace: ${NAMESPACE}"
echo ""
echo -e "${GREEN}Cluster nodes:${NC}"
kubectl get nodes

echo ""
echo -e "${GREEN}✓ Environment setup complete!${NC}"
echo -e "Run ${BLUE}source setup-env.sh${NC} whenever you start working on ImmutableLedger"
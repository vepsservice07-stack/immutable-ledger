#!/bin/bash
# ImmutableLedger Environment Setup Script
# Run this before working on the ImmutableLedger project

set -e

# Color output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== ImmutableLedger Environment Setup ===${NC}"

# Project Configuration
export PROJECT_ID="immutable-ledger"
export REGION="us-east1"
export ZONE="us-east1-b"
export CLUSTER_NAME="immutable-ledger-cluster"
export NAMESPACE="immutable-ledger"

# Set gcloud configuration
echo -e "${GREEN}Setting gcloud project to: ${PROJECT_ID}${NC}"
gcloud config set project ${PROJECT_ID}

echo -e "${GREEN}Setting default region to: ${REGION}${NC}"
gcloud config set compute/region ${REGION}

echo -e "${GREEN}Setting default zone to: ${ZONE}${NC}"
gcloud config set compute/zone ${ZONE}

# Get cluster credentials
echo -e "${GREEN}Configuring kubectl for cluster: ${CLUSTER_NAME}${NC}"
gcloud container clusters get-credentials ${CLUSTER_NAME} --zone ${ZONE}

# Set kubectl default namespace
echo -e "${GREEN}Setting kubectl default namespace to: ${NAMESPACE}${NC}"
kubectl config set-context --current --namespace=${NAMESPACE}

# Display current configuration
echo ""
echo -e "${BLUE}=== Current Configuration ===${NC}"
echo "Project ID: ${PROJECT_ID}"
echo "Region: ${REGION}"
echo "Zone: ${ZONE}"
echo "Cluster: ${CLUSTER_NAME}"
echo "Namespace: ${NAMESPACE}"
echo ""
echo -e "${GREEN}Cluster nodes:${NC}"
kubectl get nodes

echo ""
echo -e "${GREEN}✓ Environment setup complete!${NC}"
echo -e "Run ${BLUE}source immutable-ledger.sh${NC} whenever you start working on ImmutableLedger"
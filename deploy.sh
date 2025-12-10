#!/bin/bash
# Environment toggle script for ImmutableLedger
# Usage: ./deploy.sh [dev|prod]

set -e

# Color output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ENVIRONMENT=${1:-dev}

if [[ "$ENVIRONMENT" != "dev" && "$ENVIRONMENT" != "prod" ]]; then
    echo -e "${RED}Error: Environment must be 'dev' or 'prod'${NC}"
    echo "Usage: ./deploy.sh [dev|prod]"
    exit 1
fi

echo -e "${BLUE}=== Deploying ImmutableLedger (${ENVIRONMENT}) ===${NC}"

PROJECT_ID="immutable-ledger"
NAMESPACE="immutable-ledger"

if [ "$ENVIRONMENT" == "dev" ]; then
    echo -e "${GREEN}Dev Environment: Autopilot cluster (~\$5-10/month)${NC}"
    CLUSTER_NAME="immutable-ledger-autopilot"
    REGION="us-east1"
    ETCD_REPLICAS=1
    LEDGER_REPLICAS=1
    ETCD_CPU_REQUEST="100m"
    ETCD_MEM_REQUEST="256Mi"
    ETCD_CPU_LIMIT="500m"
    ETCD_MEM_LIMIT="1Gi"
    LEDGER_CPU_REQUEST="100m"
    LEDGER_MEM_REQUEST="128Mi"
    LEDGER_CPU_LIMIT="500m"
    LEDGER_MEM_LIMIT="512Mi"
else
    echo -e "${YELLOW}Production Environment: Standard GKE (~\$150-200/month)${NC}"
    CLUSTER_NAME="immutable-ledger-prod"
    ZONE="us-east1-b"
    ETCD_REPLICAS=3
    LEDGER_REPLICAS=3
    ETCD_CPU_REQUEST="500m"
    ETCD_MEM_REQUEST="1Gi"
    ETCD_CPU_LIMIT="2000m"
    ETCD_MEM_LIMIT="4Gi"
    LEDGER_CPU_REQUEST="250m"
    LEDGER_MEM_REQUEST="512Mi"
    LEDGER_CPU_LIMIT="1000m"
    LEDGER_MEM_LIMIT="2Gi"
fi

echo ""
echo "Configuration:"
echo "  Cluster: ${CLUSTER_NAME}"
echo "  etcd replicas: ${ETCD_REPLICAS}"
echo "  Ledger replicas: ${LEDGER_REPLICAS}"
echo ""

read -p "Continue deployment? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Deployment cancelled."
    exit 0
fi

# Set gcloud context
gcloud config set project ${PROJECT_ID}

# Get cluster credentials
if [ "$ENVIRONMENT" == "dev" ]; then
    gcloud container clusters get-credentials ${CLUSTER_NAME} --region ${REGION}
else
    gcloud container clusters get-credentials ${CLUSTER_NAME} --zone ${ZONE}
fi

# Set namespace
kubectl config set-context --current --namespace=${NAMESPACE}

# Apply configurations with environment-specific values
echo -e "${GREEN}[1/3] Deploying certificates...${NC}"
kubectl apply -f k8s/etcd/etcd-certificates.yaml

echo -e "${GREEN}[2/3] Deploying etcd...${NC}"
# Generate etcd manifest with environment-specific resources
cat k8s/etcd/etcd-statefulset.yaml | \
  sed "s/replicas: .*/replicas: ${ETCD_REPLICAS}/" | \
  sed "s/cpu: 100m/cpu: ${ETCD_CPU_REQUEST}/" | \
  sed "s/memory: 256Mi/memory: ${ETCD_MEM_REQUEST}/" | \
  sed "s/cpu: 500m/cpu: ${ETCD_CPU_LIMIT}/" | \
  sed "s/memory: 1Gi/memory: ${ETCD_MEM_LIMIT}/" | \
  kubectl apply -f -

echo -e "${GREEN}[3/3] Deploying Ledger service...${NC}"
# Generate ledger manifest with environment-specific resources
cat k8s/ledger-service/ledger-deployment.yaml | \
  sed "s/replicas: .*/replicas: ${LEDGER_REPLICAS}/" | \
  sed "s/cpu: 100m/cpu: ${LEDGER_CPU_REQUEST}/" | \
  sed "s/memory: 128Mi/memory: ${LEDGER_MEM_REQUEST}/" | \
  sed "s/cpu: 500m/cpu: ${LEDGER_CPU_LIMIT}/" | \
  sed "s/memory: 512Mi/memory: ${LEDGER_MEM_LIMIT}/" | \
  kubectl apply -f -

echo ""
echo -e "${GREEN}✓ Deployment complete!${NC}"
echo ""
echo "Verify deployment:"
echo "  kubectl get pods"
echo "  kubectl get svc"
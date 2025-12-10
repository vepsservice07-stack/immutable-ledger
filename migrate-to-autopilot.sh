#!/bin/bash
# Migration script to GKE Autopilot for cost savings
# This will migrate from standard GKE to Autopilot (~$150/mo → ~$5-10/mo)

set -e

# Color output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Configuration
PROJECT_ID="immutable-ledger"
REGION="us-east1"
OLD_CLUSTER="immutable-ledger-cluster"
OLD_ZONE="us-east1-b"
NEW_CLUSTER="immutable-ledger-autopilot"
NAMESPACE="immutable-ledger"

echo -e "${BLUE}=== ImmutableLedger Migration to Autopilot ===${NC}"
echo -e "${YELLOW}This will:"
echo "  1. Create new Autopilot cluster"
echo "  2. Install cert-manager"
echo "  3. Redeploy etcd cluster"
echo "  4. Redeploy Ledger service"
echo "  5. Delete old expensive cluster"
echo ""
echo "Estimated time: 15-20 minutes"
echo "Cost after migration: ~\$5-10/month${NC}"
echo ""
read -p "Continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Migration cancelled."
    exit 0
fi

# Step 1: Create Autopilot cluster
echo -e "${GREEN}[1/6] Creating Autopilot cluster...${NC}"
gcloud container clusters create-auto ${NEW_CLUSTER} \
    --region=${REGION} \
    --project=${PROJECT_ID}

# Get credentials for new cluster
gcloud container clusters get-credentials ${NEW_CLUSTER} --region=${REGION}

echo -e "${GREEN}✓ Autopilot cluster created${NC}"

# Step 2: Create namespace
echo -e "${GREEN}[2/6] Creating namespace...${NC}"
kubectl create namespace ${NAMESPACE}
kubectl config set-context --current --namespace=${NAMESPACE}

echo -e "${GREEN}✓ Namespace created${NC}"

# Step 3: Install cert-manager
echo -e "${GREEN}[3/6] Installing cert-manager...${NC}"
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.14.0/cert-manager.yaml

echo "Waiting for cert-manager to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager -n cert-manager --timeout=120s

echo -e "${GREEN}✓ cert-manager installed${NC}"

# Step 4: Deploy certificates
echo -e "${GREEN}[4/6] Creating TLS certificates...${NC}"
kubectl apply -f k8s/etcd/etcd-certificates.yaml

echo "Waiting for certificates to be ready..."
sleep 10
kubectl wait --for=condition=ready certificate --all -n ${NAMESPACE} --timeout=120s

echo -e "${GREEN}✓ Certificates ready${NC}"

# Step 5: Deploy etcd
echo -e "${GREEN}[5/6] Deploying etcd cluster...${NC}"
kubectl apply -f k8s/etcd/etcd-statefulset.yaml

echo "Waiting for etcd pods to be ready..."
kubectl wait --for=condition=ready pod -l app=etcd -n ${NAMESPACE} --timeout=300s

echo -e "${GREEN}✓ etcd cluster deployed${NC}"

# Step 6: Deploy Ledger service
echo -e "${GREEN}[6/6] Deploying Ledger service...${NC}"
kubectl apply -f k8s/ledger-service/ledger-deployment.yaml

echo "Waiting for Ledger service pods to be ready..."
kubectl wait --for=condition=ready pod -l app=ledger-service -n ${NAMESPACE} --timeout=300s

echo -e "${GREEN}✓ Ledger service deployed${NC}"

# Verify everything is running
echo ""
echo -e "${BLUE}=== Verification ===${NC}"
echo -e "${GREEN}etcd pods:${NC}"
kubectl get pods -l app=etcd

echo ""
echo -e "${GREEN}Ledger service pods:${NC}"
kubectl get pods -l app=ledger-service

echo ""
echo -e "${GREEN}Services:${NC}"
kubectl get svc

# Test etcd health
echo ""
echo -e "${GREEN}Testing etcd health...${NC}"
kubectl exec -it etcd-0 -n ${NAMESPACE} -- /usr/local/bin/etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/etcd/peer-tls/ca.crt \
  --cert=/etc/etcd/peer-tls/tls.crt \
  --key=/etc/etcd/peer-tls/tls.key \
  endpoint health

echo ""
echo -e "${YELLOW}=== Migration Complete! ===${NC}"
echo ""
echo -e "${GREEN}Next steps:${NC}"
echo "1. Verify everything is working"
echo "2. Update your local setup: ${BLUE}source setup-env.sh${NC}"
echo "3. Delete old cluster to stop charges:"
echo "   ${BLUE}gcloud container clusters delete ${OLD_CLUSTER} --zone=${OLD_ZONE}${NC}"
echo ""
echo -e "${YELLOW}⚠️  IMPORTANT: Delete the old cluster to stop the \$150/month charges!${NC}"
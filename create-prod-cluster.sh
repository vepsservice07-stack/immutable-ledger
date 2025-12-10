#!/bin/bash
# Create production-ready GKE cluster
# This is the high-performance, 3-node cluster for when you go to production

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

PROJECT_ID="immutable-ledger"
CLUSTER_NAME="immutable-ledger-prod"
ZONE="us-east1-b"

echo -e "${BLUE}=== Creating Production Cluster ===${NC}"
echo -e "${YELLOW}WARNING: This will cost ~\$150-200/month${NC}"
echo ""
echo "Cluster specs:"
echo "  - 3 × n2-standard-4 nodes (4 vCPU, 16GB RAM each)"
echo "  - SSD persistent disks"
echo "  - High availability configuration"
echo ""
read -p "Continue? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Cancelled."
    exit 0
fi

echo -e "${GREEN}Creating production cluster...${NC}"

gcloud container clusters create ${CLUSTER_NAME} \
    --zone ${ZONE} \
    --num-nodes 3 \
    --machine-type n2-standard-4 \
    --disk-size 50 \
    --disk-type pd-ssd \
    --enable-stackdriver-kubernetes \
    --enable-ip-alias \
    --network "default" \
    --subnetwork "default" \
    --project ${PROJECT_ID}

echo -e "${GREEN}✓ Production cluster created!${NC}"
echo ""
echo "Next steps:"
echo "1. Install components: ${BLUE}./deploy.sh prod${NC}"
echo "2. Build and push container: ${BLUE}docker push gcr.io/${PROJECT_ID}/ledger-service:v1${NC}"
echo ""
echo -e "${YELLOW}⚠️  Remember to downscale dev cluster to stop charges!${NC}"
echo "   ${BLUE}gcloud container clusters delete immutable-ledger-autopilot --region=us-east1${NC}"
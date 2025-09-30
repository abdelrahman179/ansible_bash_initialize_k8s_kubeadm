#!/bin/bash

# Deploy Weave CNI plugin and configure cluster script
# Applies Weave CNI, verifies pods, and removes control-plane taint

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY_FILE="$SCRIPT_DIR/inventory.ini"
PLAYBOOK_FILE="$SCRIPT_DIR/playbooks/deploy-weave.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}    Weave CNI Deployment & Configuration  ${NC}"
echo -e "${BLUE}============================================${NC}"
echo

echo -e "${YELLOW}Deployment Tasks:${NC}"
echo "✅ Deploy Weave CNI plugin from /home/rog/Kubernetes/manifests/weave.yaml"
echo "✅ Verify Weave pods status"
echo "✅ Check kube-system DNS pods (CoreDNS)"
echo "✅ Remove control-plane taint from all nodes"
echo "✅ Verify final cluster status"
echo "✅ Generate deployment summary"
echo

# Check if inventory file exists
if [[ ! -f "$INVENTORY_FILE" ]]; then
    echo -e "${RED}Error: inventory.ini not found!${NC}"
    exit 1
fi

# Check if playbook file exists
if [[ ! -f "$PLAYBOOK_FILE" ]]; then
    echo -e "${RED}Error: deploy-weave.yml not found!${NC}"
    exit 1
fi

# Check if Weave manifest exists
if [[ ! -f "$SCRIPT_DIR/manifests/weave.yaml" ]]; then
    echo -e "${RED}Error: manifests/weave.yaml not found!${NC}"
    echo "Please ensure the Weave manifest is available in the manifests directory."
    exit 1
fi

echo -e "${YELLOW}Deployment Options:${NC}"
echo "1. Complete Weave deployment and configuration (all tasks)"
echo "2. Deploy Weave CNI only"
echo "3. Verify pods status only"
echo "4. Remove control-plane taint only"
echo "5. Generate cluster summary only"
echo "6. Copy admin.conf only"
echo "7. Dry-run (check mode)"
echo "8. Verbose output"
echo

read -p "Select deployment option (1-8): " choice

# Set execution parameters based on choice
EXTRA_ARGS=""
TAGS=""
DESCRIPTION=""

case $choice in
    1)
        DESCRIPTION="Complete Weave deployment and configuration"
        ;;
    2)
        TAGS="--tags weave"
        DESCRIPTION="Deploy Weave CNI only"
        ;;
    3)
        TAGS="--tags verify"
        DESCRIPTION="Verify pods status only"
        ;;
    4)
        TAGS="--tags taint"
        DESCRIPTION="Remove control-plane taint only"
        ;;
    5)
        TAGS="--tags summary"
        DESCRIPTION="Generate cluster summary only"
        ;;
    6)
        TAGS="--tags kubeconfig"
        DESCRIPTION="Copy admin.conf only"
        ;;
    7)
        EXTRA_ARGS="--check --diff"
        DESCRIPTION="Dry-run mode (no actual changes)"
        ;;
    8)
        EXTRA_ARGS="-vv"
        DESCRIPTION="Verbose output (debug mode)"
        ;;
    *)
        echo -e "${RED}Invalid choice. Using complete deployment.${NC}"
        DESCRIPTION="Complete Weave deployment and configuration"
        ;;
esac

echo
echo -e "${YELLOW}Selected: ${NC}$DESCRIPTION"
echo

# Ask for confirmation
read -p "Do you want to proceed with Weave deployment? (y/N): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Weave deployment cancelled."
    exit 0
fi

echo
echo -e "${YELLOW}Starting Weave CNI deployment...${NC}"

# Construct and display the command
CMD="ansible-playbook -i \"$INVENTORY_FILE\" \"$PLAYBOOK_FILE\" $TAGS $EXTRA_ARGS --ask-vault-pass"
echo "Command: $CMD"
echo

# Run the playbook
ansible-playbook -i "$INVENTORY_FILE" "$PLAYBOOK_FILE" $TAGS $EXTRA_ARGS --ask-vault-pass

exit_code=$?

echo
if [[ $exit_code -eq 0 ]]; then
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  Weave CNI deployment completed!        ${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo
    
    echo -e "${YELLOW}What was deployed:${NC}"
    echo "  ✅ Weave CNI plugin applied from manifests/weave.yaml"
    echo "  ✅ Weave pods verified and running"
    echo "  ✅ DNS pods (CoreDNS) verified"
    echo "  ✅ Control-plane taint removed from all nodes"
    echo "  ✅ Cluster status verified"
    echo
    
    echo -e "${YELLOW}Files created:${NC}"
    [[ -f "./admin.conf" ]] && echo "  ✅ admin.conf (cluster admin configuration)"
    [[ -f "./cluster-deployment-summary.txt" ]] && echo "  ✅ cluster-deployment-summary.txt (deployment summary)"
    echo
    
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Test pod connectivity:"
    echo "   kubectl --kubeconfig=admin.conf run test-pod --image=busybox --rm -it -- ping google.com"
    echo
    echo "2. Deploy applications:"
    echo "   kubectl --kubeconfig=admin.conf create deployment nginx --image=nginx --replicas=3"
    echo "   kubectl --kubeconfig=admin.conf expose deployment nginx --port=80 --type=NodePort"
    echo
    echo "3. Check cluster via load balancer:"
    echo "   kubectl --server=https://192.168.100.74:6443 --kubeconfig=admin.conf get nodes"
    echo
    
    echo -e "${BLUE}Verification commands:${NC}"
    echo "  # Check Weave network:"
    echo "  kubectl --kubeconfig=admin.conf get pods -n kube-system -l name=weave-net"
    echo "  # Check node readiness:"
    echo "  kubectl --kubeconfig=admin.conf get nodes -o wide"
    echo "  # Check all system pods:"
    echo "  kubectl --kubeconfig=admin.conf get pods -n kube-system"
    echo "  # Test DNS resolution:"
    echo "  kubectl --kubeconfig=admin.conf exec -it deployment/nginx -- nslookup kubernetes.default"
else
    echo -e "${RED}============================================${NC}"
    echo -e "${RED}  Weave CNI deployment failed!           ${NC}"
    echo -e "${RED}============================================${NC}"
    echo
    echo "Please check the error messages above and try again."
    echo
    echo -e "${YELLOW}Troubleshooting tips:${NC}"
    echo "1. Verify cluster is properly initialized:"
    echo "   kubectl --kubeconfig=/etc/kubernetes/admin.conf get nodes"
    echo "2. Check if master01 is accessible:"
    echo "   ansible master01 -i inventory.ini -m ping --ask-vault-pass"
    echo "3. Verify Weave manifest exists:"
    echo "   ls -la manifests/weave.yaml"
    echo "4. Check cluster connectivity:"
    echo "   ansible master01 -i inventory.ini -m command -a 'kubectl get nodes' --ask-vault-pass"
    echo "5. Run specific tasks only (options 2-6)"
    echo "6. Use verbose output (option 8) for detailed debugging"
fi

exit $exit_code
#!/bin/bash

# Kubernetes Cluster Initialization Script
# Initializes cluster on master01 and joins all other nodes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY_FILE="$SCRIPT_DIR/inventory.ini"
PLAYBOOK_FILE="$SCRIPT_DIR/playbooks/initialize-cluster.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}    Kubernetes Cluster Initialization     ${NC}"
echo -e "${BLUE}============================================${NC}"
echo

# Check if inventory file exists
if [[ ! -f "$INVENTORY_FILE" ]]; then
    echo -e "${RED}Error: inventory.ini not found!${NC}"
    echo "Please run ./setup_cluster.sh first to create the inventory file."
    exit 1
fi

# Check if playbook file exists
if [[ ! -f "$PLAYBOOK_FILE" ]]; then
    echo -e "${RED}Error: initialize-cluster.yml not found!${NC}"
    echo "Expected location: $PLAYBOOK_FILE"
    exit 1
fi

echo -e "${YELLOW}Cluster Initialization Configuration:${NC}"
echo "  - Control Plane Endpoint: 192.168.100.74:6443 (HAProxy Load Balancer)"
echo "  - Pod Network CIDR: 10.244.0.0/16 (Flannel compatible)"
echo "  - Primary Master: master01 (will initialize cluster)"
echo "  - Secondary Master: master02 (will join as control plane)"
echo "  - Workers: worker01, worker02 (will join as workers)"
echo "  - Certificates: Auto-upload for HA setup"
echo

# Display current inventory summary
echo -e "${YELLOW}Target Nodes:${NC}"
if command -v ansible-inventory &> /dev/null; then
    echo "Masters:"
    ansible-inventory -i "$INVENTORY_FILE" --list --yaml 2>/dev/null | grep -A10 "masters:" | grep -E "^\s+[^:]+:" | sed 's/://g' | sed 's/^/  - /' || echo "  Unable to parse masters from inventory"
    echo "Workers:"
    ansible-inventory -i "$INVENTORY_FILE" --list --yaml 2>/dev/null | grep -A10 "workers:" | grep -E "^\s+[^:]+:" | sed 's/://g' | sed 's/^/  - /' || echo "  Unable to parse workers from inventory"
else
    echo "  Masters: $(grep -A10 '\[masters\]' "$INVENTORY_FILE" | grep -v '\[' | grep -v '^$' | wc -l) nodes"
    echo "  Workers: $(grep -A10 '\[workers\]' "$INVENTORY_FILE" | grep -v '\[' | grep -v '^$' | wc -l) nodes"
fi
echo

echo -e "${YELLOW}Initialization Options:${NC}"
echo "1. Full cluster initialization (master01 -> master02 -> workers)"
echo "2. Initialize master01 only (primary control plane)"
echo "3. Join master02 only (secondary control plane)"
echo "4. Join workers only (worker01 and worker02)"
echo "5. Verify cluster status only"
echo "6. Reset cluster (destroy existing cluster)"
echo "7. Dry-run (check mode - no changes)"
echo "8. Verbose output (debug mode)"
echo

read -p "Select initialization option (1-8): " choice

# Set execution parameters based on choice
EXTRA_ARGS=""
LIMIT_HOSTS=""
TAGS=""
DESCRIPTION=""

case $choice in
    1)
        DESCRIPTION="Full cluster initialization (all nodes)"
        ;;
    2)
        TAGS="--tags init_master"
        DESCRIPTION="Initialize master01 only"
        ;;
    3)
        TAGS="--tags join_masters"
        DESCRIPTION="Join master02 to cluster"
        ;;
    4)
        TAGS="--tags join_workers"
        DESCRIPTION="Join workers to cluster"
        ;;
    5)
        TAGS="--tags verify"
        DESCRIPTION="Verify cluster status only"
        ;;
    6)
        echo -e "${RED}WARNING: This will destroy the existing cluster!${NC}"
        read -p "Are you sure you want to reset the cluster? (type 'yes' to confirm): " confirm_reset
        if [[ "$confirm_reset" != "yes" ]]; then
            echo "Reset cancelled."
            exit 0
        fi
        TAGS="--tags reset"
        DESCRIPTION="Reset cluster (destroy existing)"
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
        echo -e "${RED}Invalid choice. Using full cluster initialization.${NC}"
        DESCRIPTION="Full cluster initialization (all nodes)"
        ;;
esac

echo
echo -e "${YELLOW}Selected: ${NC}$DESCRIPTION"
echo

# Pre-flight checks
echo -e "${YELLOW}Pre-flight checks:${NC}"
echo "1. Verifying all nodes are accessible..."

# Check master01
if ! ansible masters[0] -i "$INVENTORY_FILE" -m ping --ask-vault-pass -o &>/dev/null; then
    echo -e "${RED}❌ master01 is not accessible${NC}"
    exit 1
else
    echo -e "${GREEN}✅ master01 is accessible${NC}"
fi

# Check master02 if needed
if [[ "$choice" == "1" || "$choice" == "3" ]]; then
    if ! ansible masters[1] -i "$INVENTORY_FILE" -m ping --ask-vault-pass -o &>/dev/null; then
        echo -e "${RED}❌ master02 is not accessible${NC}"
        exit 1
    else
        echo -e "${GREEN}✅ master02 is accessible${NC}"
    fi
fi

# Check workers if needed
if [[ "$choice" == "1" || "$choice" == "4" ]]; then
    if ! ansible workers -i "$INVENTORY_FILE" -m ping --ask-vault-pass -o &>/dev/null; then
        echo -e "${RED}❌ Some workers are not accessible${NC}"
        exit 1
    else
        echo -e "${GREEN}✅ All workers are accessible${NC}"
    fi
fi

echo "2. Verifying HAProxy load balancer..."
if ! ansible loadbalancers -i "$INVENTORY_FILE" -m command -a 'systemctl is-active haproxy' --ask-vault-pass -o &>/dev/null; then
    echo -e "${YELLOW}⚠️  HAProxy may not be running. Cluster initialization might fail.${NC}"
else
    echo -e "${GREEN}✅ HAProxy is running${NC}"
fi

echo "3. Verifying Kubernetes is installed on all nodes..."
if ! ansible masters:workers -i "$INVENTORY_FILE" -m command -a 'which kubeadm' --ask-vault-pass -o &>/dev/null; then
    echo -e "${RED}❌ Kubernetes is not installed on all nodes${NC}"
    echo "Please run ./install-kubernetes.sh first."
    exit 1
else
    echo -e "${GREEN}✅ Kubernetes is installed on all nodes${NC}"
fi

echo

# Show important information
echo -e "${YELLOW}Important Information:${NC}"
echo "  - Cluster will use HAProxy endpoint: 192.168.100.74:6443"
echo "  - Join tokens will be saved to: cluster-join-commands.txt"
echo "  - Admin config will be saved to: admin.conf"
echo "  - Certificate key is valid for 2 hours only"
echo "  - Process will take 5-10 minutes depending on node count"
echo

# Ask for confirmation
read -p "Do you want to proceed with cluster initialization? (y/N): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Cluster initialization cancelled."
    exit 0
fi

echo
echo -e "${YELLOW}Starting Kubernetes cluster initialization...${NC}"

# Construct and display the command
CMD="ansible-playbook -i \"$INVENTORY_FILE\" \"$PLAYBOOK_FILE\" $LIMIT_HOSTS $TAGS $EXTRA_ARGS --ask-vault-pass"
echo "Command: $CMD"
echo

# Run the playbook
ansible-playbook -i "$INVENTORY_FILE" "$PLAYBOOK_FILE" $LIMIT_HOSTS $TAGS $EXTRA_ARGS --ask-vault-pass

exit_code=$?

echo
if [[ $exit_code -eq 0 ]]; then
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  Cluster initialization completed!       ${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo
    
    if [[ "$choice" == "1" || "$choice" == "2" || "$choice" == "5" ]]; then
        echo -e "${YELLOW}Next steps:${NC}"
        echo "1. Install CNI plugin (Flannel):"
        echo "   kubectl --kubeconfig=admin.conf apply -f https://github.com/flannel-io/flannel/releases/latest/download/kustomization.yaml"
        echo "2. Verify all nodes are ready:"
        echo "   kubectl --kubeconfig=admin.conf get nodes"
        echo "3. Access cluster via load balancer:"
        echo "   kubectl --server=https://192.168.100.74:6443 --kubeconfig=admin.conf get nodes"
        echo "4. Deploy workloads:"
        echo "   kubectl --kubeconfig=admin.conf create deployment nginx --image=nginx"
        echo
        echo -e "${BLUE}Files created:${NC}"
        [[ -f "./admin.conf" ]] && echo "  - admin.conf (cluster admin configuration)"
        [[ -f "./cluster-join-commands.txt" ]] && echo "  - cluster-join-commands.txt (join commands for reference)"
    fi
    
    echo
    echo -e "${BLUE}Useful verification commands:${NC}"
    echo "  # Check cluster status:"
    echo "  kubectl --kubeconfig=admin.conf get nodes -o wide"
    echo "  kubectl --kubeconfig=admin.conf get pods --all-namespaces"
    echo "  # Check via load balancer:"
    echo "  kubectl --server=https://192.168.100.74:6443 --kubeconfig=admin.conf cluster-info"
else
    echo -e "${RED}============================================${NC}"
    echo -e "${RED}  Cluster initialization failed!          ${NC}"
    echo -e "${RED}============================================${NC}"
    echo
    echo "Please check the error messages above and try again."
    echo
    echo -e "${YELLOW}Troubleshooting tips:${NC}"
    echo "1. Verify vault password is correct"
    echo "2. Check network connectivity to all nodes"
    echo "3. Ensure HAProxy is running: ./install-haproxy.sh"
    echo "4. Verify Kubernetes is installed: ./install-kubernetes.sh"
    echo "5. Check firewall settings on all nodes"
    echo "6. Run with verbose output (option 8) for detailed debugging"
    echo "7. Try initializing master01 only first (option 2)"
fi

exit $exit_code

#!/bin/bash

# Kubernetes Installation Script
# Runs the Kubernetes installation playbook on your cluster nodes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY_FILE="$SCRIPT_DIR/inventory.ini"
PLAYBOOK_FILE="$SCRIPT_DIR/playbooks/install-kubernetes.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}    Kubernetes Installation Playbook      ${NC}"
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
    echo -e "${RED}Error: install-kubernetes.yml not found!${NC}"
    echo "Expected location: $PLAYBOOK_FILE"
    exit 1
fi

echo -e "${YELLOW}Kubernetes Installation Configuration:${NC}"
echo "  - Playbook: install-kubernetes.yml"
echo "  - Version: Kubernetes v1.34 (latest stable)"
echo "  - Components: kubelet, kubeadm, kubectl"
echo "  - Container Runtime: containerd (configured)"
echo "  - Default scope: Masters and Workers only (excludes load balancers)"
echo

# Display current inventory summary
echo -e "${YELLOW}Target Nodes:${NC}"
if command -v ansible-inventory &> /dev/null; then
    ansible-inventory -i "$INVENTORY_FILE" --list --yaml 2>/dev/null | grep -E "(masters|workers|loadbalancers):" || echo "  Unable to parse inventory automatically"
else
    echo "  Masters: $(grep -A10 '\[masters\]' "$INVENTORY_FILE" | grep -v '\[' | grep -v '^$' | wc -l) nodes"
    echo "  Workers: $(grep -A10 '\[workers\]' "$INVENTORY_FILE" | grep -v '\[' | grep -v '^$' | wc -l) nodes"
    echo "  Load Balancers: $(grep -A10 '\[loadbalancers\]' "$INVENTORY_FILE" | grep -v '\[' | grep -v '^$' | wc -l) nodes (excluded by default)"
fi
echo

echo -e "${YELLOW}Installation Options:${NC}"
echo "1. Install on Kubernetes nodes (masters + workers, excludes load balancers)"
echo "2. Install on masters only"
echo "3. Install on workers only"
echo "4. Install on all nodes (including load balancers)"
echo "5. Preparation tasks only (system setup)"
echo "6. Repository setup only (Kubernetes repo)"
echo "7. Package installation only"
echo "8. System configuration only (swap, sysctl, etc.)"
echo "9. Container runtime configuration only"
echo "10. Verification only (check existing installation)"
echo "11. Dry-run (check mode - no changes)"
echo "12. Verbose output (debug mode)"
echo

read -p "Select installation option (1-12): " choice

# Set execution parameters based on choice
EXTRA_ARGS=""
LIMIT_HOSTS=""
TAGS=""
DESCRIPTION=""

case $choice in
    1)
        LIMIT_HOSTS="--limit masters:workers"
        DESCRIPTION="Kubernetes installation on Kubernetes nodes (masters + workers)"
        ;;
    2)
        LIMIT_HOSTS="--limit masters"
        DESCRIPTION="Kubernetes installation on masters only"
        ;;
    3)
        LIMIT_HOSTS="--limit workers"
        DESCRIPTION="Kubernetes installation on workers only"
        ;;
    4)
        DESCRIPTION="Kubernetes installation on all nodes (including load balancers)"
        ;;
    5)
        TAGS="--tags preparation"
        DESCRIPTION="Preparation tasks only (system setup)"
        ;;
    6)
        TAGS="--tags repository"
        DESCRIPTION="Repository setup only"
        ;;
    7)
        TAGS="--tags installation"
        DESCRIPTION="Package installation only"
        ;;
    8)
        TAGS="--tags system_config,network_config"
        DESCRIPTION="System configuration only (swap, sysctl, firewall)"
        ;;
    9)
        TAGS="--tags container_runtime"
        DESCRIPTION="Container runtime configuration only"
        ;;
    10)
        TAGS="--tags verification"
        DESCRIPTION="Verification tasks only"
        ;;
    11)
        EXTRA_ARGS="--check --diff"
        DESCRIPTION="Dry-run mode (no actual changes)"
        ;;
    12)
        EXTRA_ARGS="-vv"
        DESCRIPTION="Verbose output (debug mode)"
        ;;
    *)
        echo -e "${RED}Invalid choice. Using Kubernetes nodes installation.${NC}"
        LIMIT_HOSTS="--limit masters:workers"
        DESCRIPTION="Kubernetes installation on Kubernetes nodes (masters + workers)"
        ;;
esac

echo
echo -e "${YELLOW}Selected: ${NC}$DESCRIPTION"
echo

# Show configuration options
echo -e "${YELLOW}Current Configuration:${NC}"
echo "  - Kubernetes Version: v1.34"
echo "  - Container Runtime: containerd"
echo "  - CNI: Not installed (will be configured after cluster init)"
echo "  - Firewall: Will be disabled (UFW)"
echo "  - Swap: Will be disabled"
echo

# Ask for confirmation
read -p "Do you want to proceed with Kubernetes installation? (y/N): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Installation cancelled."
    exit 0
fi

echo
echo -e "${YELLOW}Running Kubernetes installation playbook...${NC}"

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
    echo -e "${GREEN}  Kubernetes installation completed!      ${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo
    echo -e "${YELLOW}Next steps:${NC}"
    if [[ "$choice" == "1" || "$choice" == "2" || "$choice" == "3" || "$choice" == "4" ]]; then
        echo "1. Initialize Kubernetes cluster on master node:"
        echo "   kubeadm init --pod-network-cidr=10.244.0.0/16"
        echo "2. Configure kubectl for root user:"
        echo "   mkdir -p \$HOME/.kube"
        echo "   cp -i /etc/kubernetes/admin.conf \$HOME/.kube/config"
        echo "   chown \$(id -u):\$(id -g) \$HOME/.kube/config"
        echo "3. Install CNI plugin (e.g., Flannel):"
        echo "   kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kustomization.yaml"
        echo "4. Join worker nodes to the cluster (get join command from master)"
        echo "5. Verify cluster status: kubectl get nodes"
    elif [[ "$choice" == "10" ]]; then
        echo "1. Review verification output above"
        echo "2. If issues found, run complete installation (option 1)"
    else
        echo "1. Continue with remaining installation steps if needed"
        echo "2. Run verification (option 10) to check status"
    fi
    echo
    echo -e "${BLUE}Useful verification commands:${NC}"
    echo "  # Verify on Kubernetes nodes only:"
    echo "  ansible masters:workers -i inventory.ini -m command -a 'kubelet --version' --ask-vault-pass"
    echo "  ansible masters:workers -i inventory.ini -m command -a 'kubeadm version' --ask-vault-pass"
    echo "  ansible masters:workers -i inventory.ini -m command -a 'kubectl version --client' --ask-vault-pass"
    echo "  # Check system configuration:"
    echo "  ansible masters:workers -i inventory.ini -m command -a 'systemctl status kubelet' --ask-vault-pass"
    echo "  ansible masters:workers -i inventory.ini -m command -a 'free -h' --ask-vault-pass"
else
    echo -e "${RED}============================================${NC}"
    echo -e "${RED}  Kubernetes installation failed!         ${NC}"
    echo -e "${RED}============================================${NC}"
    echo
    echo "Please check the error messages above and try again."
    echo
    echo -e "${YELLOW}Troubleshooting tips:${NC}"
    echo "1. Verify vault password is correct"
    echo "2. Check network connectivity to target nodes"
    echo "3. Ensure sudo privileges on target nodes"
    echo "4. Run with verbose output (option 12) for detailed debugging"
    echo "5. Try running preparation tasks only (option 5) first"
    echo "6. Check if Docker is installed and running"
    echo "7. Verify system resources (RAM, disk space)"
fi

exit $exit_code

#!/bin/bash

# Docker Installation Playbook Runner
# Runs the comprehensive Docker installation playbook on your Kubernetes cluster

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY_FILE="$SCRIPT_DIR/inventory.ini"
PLAYBOOK_FILE="$SCRIPT_DIR/playbooks/install-docker.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Comprehensive Docker Installation       ${NC}"
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
    echo -e "${RED}Error: install-docker.yml not found!${NC}"
    echo "Expected location: $PLAYBOOK_FILE"
    exit 1
fi

echo -e "${YELLOW}Docker Installation Configuration:${NC}"
echo "  - Playbook: install-docker.yml (Enterprise-grade)"
echo "  - Features: Full Ansible best practices, comprehensive error handling"
echo "  - User management: Optional (configurable)"
echo "  - Testing: Optional (configurable)"
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
echo "6. Repository setup only (Docker repo)"
echo "7. Package installation only"
echo "8. Service configuration only"
echo "9. Verification only (check existing installation)"
echo "10. Dry-run (check mode - no changes)"
echo "11. Verbose output (debug mode)"
echo

read -p "Select installation option (1-11): " choice

# Set execution parameters based on choice
EXTRA_ARGS=""
LIMIT_HOSTS=""
TAGS=""
DESCRIPTION=""

case $choice in
    1)
        LIMIT_HOSTS="--limit masters:workers"
        DESCRIPTION="Docker installation on Kubernetes nodes (masters + workers)"
        ;;
    2)
        LIMIT_HOSTS="--limit masters"
        DESCRIPTION="Docker installation on masters only"
        ;;
    3)
        LIMIT_HOSTS="--limit workers"
        DESCRIPTION="Docker installation on workers only"
        ;;
    4)
        DESCRIPTION="Docker installation on all nodes (including load balancers)"
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
        TAGS="--tags service"
        DESCRIPTION="Service configuration only"
        ;;
    9)
        TAGS="--tags verification"
        DESCRIPTION="Verification tasks only"
        ;;
    10)
        EXTRA_ARGS="--check --diff"
        DESCRIPTION="Dry-run mode (no actual changes)"
        ;;
    11)
        EXTRA_ARGS="-vv"
        DESCRIPTION="Verbose output (debug mode)"
        ;;
    *)
        echo -e "${RED}Invalid choice. Using Kubernetes nodes installation.${NC}"
        LIMIT_HOSTS="--limit masters:workers"
        DESCRIPTION="Docker installation on Kubernetes nodes (masters + workers)"
        ;;
esac

echo
echo -e "${YELLOW}Selected: ${NC}$DESCRIPTION"
echo

# Show configuration options
echo -e "${YELLOW}Current Configuration (group_vars/all/docker.yml):${NC}"
if [[ -f "$SCRIPT_DIR/group_vars/all/docker.yml" ]]; then
    grep -E "^(add_user_to_docker_group|test_docker_installation):" "$SCRIPT_DIR/group_vars/all/docker.yml" 2>/dev/null || echo "  Default configuration will be used"
else
    echo "  Default configuration will be used"
fi
echo

# Ask for confirmation
read -p "Do you want to proceed with Docker installation? (y/N): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Installation cancelled."
    exit 0
fi

echo
echo -e "${YELLOW}Running Docker installation playbook...${NC}"

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
    echo -e "${GREEN}  Docker installation completed!          ${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo
    echo -e "${YELLOW}Next steps:${NC}"
    if [[ "$choice" == "1" || "$choice" == "2" || "$choice" == "3" || "$choice" == "4" ]]; then
        echo "1. Verify Docker installation: docker --version"
        echo "2. Check Docker service: systemctl status docker"
        echo "3. Test Docker: docker run hello-world"
        echo "4. If users were added to docker group, log out and back in"
        echo "5. Continue with Kubernetes installation"
    elif [[ "$choice" == "9" ]]; then
        echo "1. Review verification output above"
        echo "2. If issues found, run complete installation (option 1)"
    else
        echo "1. Continue with remaining installation steps if needed"
        echo "2. Run verification (option 9) to check status"
    fi
    echo
    echo -e "${BLUE}Useful verification commands:${NC}"
    echo "  # Verify on Kubernetes nodes only (excludes load balancers):"
    echo "  ansible masters:workers -i inventory.ini -m command -a 'docker --version' --ask-vault-pass"
    echo "  ansible masters:workers -i inventory.ini -m command -a 'systemctl status docker' --ask-vault-pass"
    echo "  # Verify on all nodes (including load balancers if Docker was installed):"
    echo "  ansible all -i inventory.ini -m command -a 'docker --version' --ask-vault-pass"
else
    echo -e "${RED}============================================${NC}"
    echo -e "${RED}  Docker installation failed!             ${NC}"
    echo -e "${RED}============================================${NC}"
    echo
    echo "Please check the error messages above and try again."
    echo
    echo -e "${YELLOW}Troubleshooting tips:${NC}"
    echo "1. Verify vault password is correct"
    echo "2. Check network connectivity to target nodes"
    echo "3. Ensure sudo privileges on target nodes"
    echo "4. Run with verbose output (option 10) for detailed debugging"
    echo "5. Try running preparation tasks only (option 4) first"
fi

exit $exit_code
#!/bin/bash

# Network Configuration Playbook Runner
# Runs the network configuration playbook on your Kubernetes cluster

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY_FILE="$SCRIPT_DIR/inventory.ini"
PLAYBOOK_FILE="$SCRIPT_DIR/playbooks/configure-network.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}     Network Configuration Playbook       ${NC}"
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
    echo -e "${RED}Error: configure-network.yml not found in playbooks directory!${NC}"
    echo "Expected location: $PLAYBOOK_FILE"
    exit 1
fi

echo -e "${YELLOW}Configuration Details:${NC}"
echo "  - Inventory: $INVENTORY_FILE"
echo "  - Playbook: $PLAYBOOK_FILE"
echo

# Display current inventory summary
echo -e "${YELLOW}Current Inventory Summary:${NC}"
if command -v ansible-inventory &> /dev/null; then
    ansible-inventory -i "$INVENTORY_FILE" --list --yaml 2>/dev/null | grep -E "(masters|workers|loadbalancers):" || echo "  Unable to parse inventory automatically"
else
    echo "  Masters: $(grep -A10 '\[masters\]' "$INVENTORY_FILE" | grep -v '\[' | grep -v '^$' | wc -l) nodes"
    echo "  Workers: $(grep -A10 '\[workers\]' "$INVENTORY_FILE" | grep -v '\[' | grep -v '^$' | wc -l) nodes"
fi
echo

# Options for execution
echo -e "${YELLOW}Execution Options:${NC}"
echo "1. Run on all nodes"
echo "2. Run on masters only"
echo "3. Run on workers only"
echo "4. Run with dry-run (check mode)"
echo "5. Run with verbose output"
echo

read -p "Select option (1-5): " option

# Set execution parameters based on choice
EXTRA_ARGS=""
LIMIT_HOSTS=""
DESCRIPTION=""

case $option in
    1)
        DESCRIPTION="all nodes"
        ;;
    2)
        LIMIT_HOSTS="--limit masters"
        DESCRIPTION="masters only"
        ;;
    3)
        LIMIT_HOSTS="--limit workers"
        DESCRIPTION="workers only"
        ;;
    4)
        EXTRA_ARGS="--check --diff"
        DESCRIPTION="all nodes (dry-run)"
        ;;
    5)
        EXTRA_ARGS="-vv"
        DESCRIPTION="all nodes (verbose)"
        ;;
    *)
        echo -e "${RED}Invalid choice. Using default: all nodes${NC}"
        DESCRIPTION="all nodes"
        ;;
esac

echo
echo -e "${YELLOW}Selected: ${NC}$DESCRIPTION"
echo

# Ask for confirmation
read -p "Do you want to proceed with network configuration? (y/N): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Network configuration cancelled."
    exit 0
fi

echo
echo -e "${YELLOW}Running network configuration playbook...${NC}"

# Construct the command
CMD="ansible-playbook -i \"$INVENTORY_FILE\" \"$PLAYBOOK_FILE\" $LIMIT_HOSTS $EXTRA_ARGS --ask-vault-pass"
echo "Command: $CMD"
echo

# Run the playbook
ansible-playbook -i "$INVENTORY_FILE" "$PLAYBOOK_FILE" $LIMIT_HOSTS $EXTRA_ARGS --ask-vault-pass

exit_code=$?

echo
if [[ $exit_code -eq 0 ]]; then
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  Network configuration completed!        ${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Verify network connectivity between nodes"
    echo "2. Test SSH access to all nodes"
    echo "3. Proceed with Docker or Kubernetes installation"
    echo "4. Check network interfaces: ip addr show"
else
    echo -e "${RED}============================================${NC}"
    echo -e "${RED}  Network configuration failed!           ${NC}"
    echo -e "${RED}============================================${NC}"
    echo
    echo "Please check the error messages above and try again."
    echo "Common issues:"
    echo "  - Incorrect vault password"
    echo "  - Network connectivity problems"
    echo "  - Permission issues on target nodes"
fi

exit $exit_code
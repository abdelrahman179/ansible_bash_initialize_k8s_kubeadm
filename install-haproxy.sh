#!/bin/bash

# HAProxy Installation Script
# Installs and configures HAProxy for Kubernetes API server load balancing

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY_FILE="$SCRIPT_DIR/inventory.ini"
PLAYBOOK_FILE="$SCRIPT_DIR/playbooks/install-haproxy.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}      HAProxy Load Balancer Setup         ${NC}"
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
    echo -e "${RED}Error: install-haproxy.yml not found!${NC}"
    echo "Expected location: $PLAYBOOK_FILE"
    exit 1
fi

# Check if template file exists
TEMPLATE_FILE="$SCRIPT_DIR/templates/haproxy.cfg.j2"
if [[ ! -f "$TEMPLATE_FILE" ]]; then
    echo -e "${RED}Error: haproxy.cfg.j2 template not found!${NC}"
    echo "Expected location: $TEMPLATE_FILE"
    exit 1
fi

echo -e "${YELLOW}HAProxy Load Balancer Configuration:${NC}"
echo "  - Target: Load balancers only"
echo "  - Purpose: Kubernetes API server load balancing"
echo "  - Backend: Master nodes (port 6443)"
echo "  - Algorithm: Round-robin with health checks"
echo "  - Stats Interface: Port 8404 (admin/admin123)"
echo "  - Health Check: Port 8080 (/health endpoint)"
echo

# Display current inventory summary
echo -e "${YELLOW}Target Nodes:${NC}"
if command -v ansible-inventory &> /dev/null; then
    echo "Load Balancers:"
    ansible-inventory -i "$INVENTORY_FILE" --list --yaml 2>/dev/null | grep -A10 "loadbalancers:" | grep -E "^\s+[^:]+:" | sed 's/://g' | sed 's/^/  - /' || echo "  Unable to parse load balancers from inventory"
    echo "Master Nodes (backends):"
    ansible-inventory -i "$INVENTORY_FILE" --list --yaml 2>/dev/null | grep -A10 "masters:" | grep -E "^\s+[^:]+:" | sed 's/://g' | sed 's/^/  - /' || echo "  Unable to parse masters from inventory"
else
    echo "  Load Balancers: $(grep -A10 '\[loadbalancers\]' "$INVENTORY_FILE" | grep -v '\[' | grep -v '^$' | wc -l) nodes"
    echo "  Masters (backends): $(grep -A10 '\[masters\]' "$INVENTORY_FILE" | grep -v '\[' | grep -v '^$' | wc -l) nodes"
fi
echo

echo -e "${YELLOW}Installation Options:${NC}"
echo "1. Complete HAProxy installation and configuration"
echo "2. Installation only (packages and service)"
echo "3. Configuration only (update HAProxy config)"
echo "4. Verification only (check existing installation)"
echo "5. Service management (restart/reload HAProxy)"
echo "6. Firewall configuration only"
echo "7. Health check and connectivity test"
echo "8. Dry-run (check mode - no changes)"
echo "9. Verbose output (debug mode)"
echo "10. Show HAProxy stats and status"
echo

read -p "Select installation option (1-10): " choice

# Set execution parameters based on choice
EXTRA_ARGS=""
LIMIT_HOSTS="--limit loadbalancers"
TAGS=""
DESCRIPTION=""

case $choice in
    1)
        DESCRIPTION="Complete HAProxy installation and configuration"
        ;;
    2)
        TAGS="--tags installation,service"
        DESCRIPTION="HAProxy installation and service setup only"
        ;;
    3)
        TAGS="--tags configuration"
        DESCRIPTION="HAProxy configuration update only"
        ;;
    4)
        TAGS="--tags verification"
        DESCRIPTION="HAProxy verification and health checks"
        ;;
    5)
        TAGS="--tags service"
        DESCRIPTION="HAProxy service management"
        ;;
    6)
        TAGS="--tags firewall"
        DESCRIPTION="Firewall configuration for HAProxy"
        ;;
    7)
        TAGS="--tags verification,health_check"
        DESCRIPTION="Health check and connectivity tests"
        ;;
    8)
        EXTRA_ARGS="--check --diff"
        DESCRIPTION="Dry-run mode (no actual changes)"
        ;;
    9)
        EXTRA_ARGS="-vv"
        DESCRIPTION="Verbose output (debug mode)"
        ;;
    10)
        TAGS="--tags detailed_status"
        DESCRIPTION="Show HAProxy detailed status and statistics"
        ;;
    *)
        echo -e "${RED}Invalid choice. Using complete installation.${NC}"
        DESCRIPTION="Complete HAProxy installation and configuration"
        ;;
esac

echo
echo -e "${YELLOW}Selected: ${NC}$DESCRIPTION"
echo

# Show configuration details
echo -e "${YELLOW}HAProxy Configuration Details:${NC}"
echo "  - Load Balancer Algorithm: Round-robin"
echo "  - Kubernetes API Port: 6443"
echo "  - Health Check Interval: 10 seconds"
echo "  - Stats Interface: http://loadbalancer:8404/stats"
echo "  - Health Endpoint: http://loadbalancer:8080/health"
echo "  - Log Level: Info with health check logging"
echo

# Ask for confirmation
read -p "Do you want to proceed with HAProxy installation? (y/N): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "Installation cancelled."
    exit 0
fi

echo
echo -e "${YELLOW}Running HAProxy installation playbook...${NC}"

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
    echo -e "${GREEN}     HAProxy installation completed!      ${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo
    echo -e "${YELLOW}Next steps:${NC}"
    if [[ "$choice" == "1" || "$choice" == "2" || "$choice" == "3" ]]; then
        echo "1. Verify HAProxy is running:"
        echo "   systemctl status haproxy"
        echo "2. Check HAProxy stats interface:"
        echo "   Open http://YOUR_LOADBALANCER_IP:8404/stats"
        echo "   (Username: admin, Password: admin123)"
        echo "3. Test Kubernetes API load balancing:"
        echo "   curl -k https://YOUR_LOADBALANCER_IP:6443/version"
        echo "4. Update your kubeconfig to use the load balancer:"
        echo "   Replace master IP with load balancer IP in ~/.kube/config"
        echo "5. Test health check endpoint:"
        echo "   curl http://YOUR_LOADBALANCER_IP:8080/health"
    elif [[ "$choice" == "4" || "$choice" == "7" ]]; then
        echo "1. Review verification results above"
        echo "2. Check HAProxy logs: journalctl -u haproxy -f"
        echo "3. If issues found, run complete installation (option 1)"
    elif [[ "$choice" == "10" ]]; then
        echo "1. Review detailed status information above"
        echo "2. Access stats interface for real-time monitoring"
    else
        echo "1. Continue with remaining setup steps if needed"
        echo "2. Run verification (option 4) to check status"
    fi
    echo
    echo -e "${BLUE}Useful verification commands:${NC}"
    echo "  # Check HAProxy on load balancers:"
    echo "  ansible loadbalancers -i inventory.ini -m command -a 'systemctl status haproxy' --ask-vault-pass"
    echo "  ansible loadbalancers -i inventory.ini -m command -a 'netstat -tlnp | grep haproxy' --ask-vault-pass"
    echo "  # Test load balancer functionality:"
    echo "  ansible loadbalancers -i inventory.ini -m uri -a 'url=http://{{ ansible_default_ipv4.address }}:8080/health' --ask-vault-pass"
    echo "  # Check configuration syntax:"
    echo "  ansible loadbalancers -i inventory.ini -m command -a 'haproxy -c -f /etc/haproxy/haproxy.cfg' --ask-vault-pass"
else
    echo -e "${RED}============================================${NC}"
    echo -e "${RED}      HAProxy installation failed!        ${NC}"
    echo -e "${RED}============================================${NC}"
    echo
    echo "Please check the error messages above and try again."
    echo
    echo -e "${YELLOW}Troubleshooting tips:${NC}"
    echo "1. Verify vault password is correct"
    echo "2. Check network connectivity to load balancer nodes"
    echo "3. Ensure sudo privileges on load balancer nodes"
    echo "4. Run with verbose output (option 9) for detailed debugging"
    echo "5. Try installation only (option 2) first"
    echo "6. Check if load balancer nodes are accessible"
    echo "7. Verify master nodes are running Kubernetes API server"
    echo "8. Check firewall settings on all nodes"
fi

exit $exit_code

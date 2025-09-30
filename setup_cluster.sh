#!/bin/bash

# Kubernetes Ansible Setup Script
# Entry point for configuring Kubernetes cluster inventory

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY_FILE="$SCRIPT_DIR/inventory.ini"
VAULT_FILE="$SCRIPT_DIR/group_vars/all/vault.yml"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}  Kubernetes Cluster Setup Configuration  ${NC}"
echo -e "${BLUE}============================================${NC}"
echo

# Function to validate IP address
validate_ip() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        IFS='.' read -ra ADDR <<< "$ip"
        for i in "${ADDR[@]}"; do
            if [[ $i -gt 255 ]]; then
                return 1
            fi
        done
        return 0
    else
        return 1
    fi
}

# Function to read and validate IP
read_ip() {
    local prompt="$1"
    local ip
    while true; do
        read -p "$prompt" ip
        if validate_ip "$ip"; then
            echo "$ip"
            break
        else
            echo -e "${RED}Invalid IP address format. Please try again.${NC}" >&2
        fi
    done
}

# Get cluster configuration
echo -e "${YELLOW}Enter cluster configuration:${NC}"
echo

# Get number of master nodes
while true; do
    read -p "Number of master nodes (1-10): " MASTER_COUNT
    if [[ "$MASTER_COUNT" =~ ^[1-9]$|^10$ ]]; then
        break
    else
        echo -e "${RED}Please enter a number between 1 and 10${NC}"
    fi
done

# Get number of worker nodes
while true; do
    read -p "Number of worker nodes (0-50): " WORKER_COUNT
    if [[ "$WORKER_COUNT" =~ ^[0-9]$|^[1-4][0-9]$|^50$ ]]; then
        break
    else
        echo -e "${RED}Please enter a number between 0 and 50${NC}"
    fi
done

# Get load balancer configuration based on master count
INCLUDE_LB=""
LB_IP=""
LB_USER=""

if [[ $MASTER_COUNT -eq 1 ]]; then
    echo -e "\n${YELLOW}Single Master Configuration:${NC}"
    echo "With a single master, you have two options:"
    echo "1. Use master node's API directly (${MASTER_IPS[0]}:6443)"
    echo "2. Use a dedicated load balancer for future scalability"
    echo
    read -p "Do you want to include a load balancer? (y/N): " INCLUDE_LB
    INCLUDE_LB=${INCLUDE_LB,,} # Convert to lowercase
    
    if [[ "$INCLUDE_LB" == "y" || "$INCLUDE_LB" == "yes" ]]; then
        echo -e "${GREEN}✅ Load balancer will be configured for future scalability${NC}"
    else
        echo -e "${BLUE}ℹ️  Using master node API directly (simpler setup)${NC}"
    fi
else
    echo -e "\n${YELLOW}Multi-Master Configuration:${NC}"
    echo "Multiple masters detected - load balancer is ${GREEN}REQUIRED${NC} for high availability"
    INCLUDE_LB="yes"
fi

# Get password securely
echo
read -s -p "Password for all nodes: " PASSWORD
echo
if [[ -z "$PASSWORD" ]]; then
    echo -e "${RED}Password cannot be empty${NC}"
    exit 1
fi

# Get gateway IP
echo
GATEWAY_IP=$(read_ip "Gateway IP address: ")

echo
echo -e "${YELLOW}Collecting node details (IP and username):${NC}"

# Collect master node IPs and usernames
declare -a MASTER_IPS
declare -a MASTER_USERS
for ((i=1; i<=MASTER_COUNT; i++)); do
    echo -e "\n${BLUE}Master node $i:${NC}"
    ip=$(read_ip "  IP address: ")
    read -p "  Username: " username
    if [[ -z "$username" ]]; then
        echo -e "${RED}Username cannot be empty${NC}"
        exit 1
    fi
    MASTER_IPS+=("$ip")
    MASTER_USERS+=("$username")
done

# Collect worker node IPs and usernames
declare -a WORKER_IPS
declare -a WORKER_USERS
if [[ $WORKER_COUNT -gt 0 ]]; then
    for ((i=1; i<=WORKER_COUNT; i++)); do
        echo -e "\n${BLUE}Worker node $i:${NC}"
        ip=$(read_ip "  IP address: ")
        read -p "  Username: " username
        if [[ -z "$username" ]]; then
            echo -e "${RED}Username cannot be empty${NC}"
            exit 1
        fi
        WORKER_IPS+=("$ip")
        WORKER_USERS+=("$username")
    done
fi

# Collect load balancer IP and username if needed
LB_IP=""
LB_USER=""
if [[ "$INCLUDE_LB" == "y" || "$INCLUDE_LB" == "yes" ]]; then
    echo -e "\n${BLUE}Load balancer:${NC}"
    LB_IP=$(read_ip "  IP address: ")
    read -p "  Username: " LB_USER
    if [[ -z "$LB_USER" ]]; then
        echo -e "${RED}Username cannot be empty${NC}"
        exit 1
    fi
fi

echo
echo -e "${YELLOW}Generating configuration files...${NC}"

# Backup existing files
if [[ -f "$INVENTORY_FILE" ]]; then
    cp "$INVENTORY_FILE" "$INVENTORY_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    echo -e "${GREEN}Backed up existing inventory.ini${NC}"
fi

if [[ -f "$VAULT_FILE" ]]; then
    cp "$VAULT_FILE" "$VAULT_FILE.backup.$(date +%Y%m%d_%H%M%S)"
    echo -e "${GREEN}Backed up existing vault.yml${NC}"
fi

# Generate inventory.ini
cat > "$INVENTORY_FILE" << INVENTORY_EOF
[all]
INVENTORY_EOF

# Add master nodes
for ((i=1; i<=MASTER_COUNT; i++)); do
    node_name=$(printf "master%02d" $i)
    echo "$node_name ansible_host=${MASTER_IPS[$((i-1))]} ansible_user=${MASTER_USERS[$((i-1))]}" >> "$INVENTORY_FILE"
done

# Add worker nodes
if [[ $WORKER_COUNT -gt 0 ]]; then
    for ((i=1; i<=WORKER_COUNT; i++)); do
        node_name=$(printf "worker%02d" $i)
        echo "$node_name ansible_host=${WORKER_IPS[$((i-1))]} ansible_user=${WORKER_USERS[$((i-1))]}" >> "$INVENTORY_FILE"
    done
fi

# Add load balancer if included
if [[ -n "$LB_IP" ]]; then
    echo "loadbalancer ansible_host=$LB_IP ansible_user=$LB_USER" >> "$INVENTORY_FILE"
fi

# Add group definitions
echo -e "\n[masters]" >> "$INVENTORY_FILE"
for ((i=1; i<=MASTER_COUNT; i++)); do
    node_name=$(printf "master%02d" $i)
    echo "$node_name" >> "$INVENTORY_FILE"
done

if [[ $WORKER_COUNT -gt 0 ]]; then
    echo -e "\n[workers]" >> "$INVENTORY_FILE"
    for ((i=1; i<=WORKER_COUNT; i++)); do
        node_name=$(printf "worker%02d" $i)
        echo "$node_name" >> "$INVENTORY_FILE"
    done
fi

if [[ -n "$LB_IP" ]]; then
    echo -e "\n[loadbalancers]" >> "$INVENTORY_FILE"
    echo "loadbalancer" >> "$INVENTORY_FILE"
fi

# Add group variables
cat >> "$INVENTORY_FILE" << INVENTORY_EOF

[all:vars]
gateway=$GATEWAY_IP
ansible_ssh_pass={{ vault_password }}
ansible_become_pass={{ vault_password }}
INVENTORY_EOF

# Ensure group_vars/all directory exists
mkdir -p "$(dirname "$VAULT_FILE")"

# Generate vault.yml
cat > "$VAULT_FILE" << VAULT_EOF
# This file should be encrypted with ansible-vault
# Run: ansible-vault encrypt group_vars/all/vault.yml
# Example content (replace with your actual passwords):

vault_password: "$PASSWORD"
vault_become_password: "$PASSWORD"
VAULT_EOF

echo
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}  Configuration completed successfully!    ${NC}"
echo -e "${GREEN}============================================${NC}"
echo
echo -e "${YELLOW}Files updated:${NC}"
echo "  - $INVENTORY_FILE"
echo "  - $VAULT_FILE"
echo
echo -e "${YELLOW}Summary:${NC}"
echo "  - Master nodes: $MASTER_COUNT"
echo "  - Worker nodes: $WORKER_COUNT"
echo "  - Load balancer: $([ -n "$LB_IP" ] && echo "Yes" || echo "No")"
echo "  - Gateway: $GATEWAY_IP"
echo
echo -e "${YELLOW}Node Details:${NC}"
for ((i=1; i<=MASTER_COUNT; i++)); do
    echo "  - Master $i: ${MASTER_IPS[$((i-1))]} (${MASTER_USERS[$((i-1))]})"
done
if [[ $WORKER_COUNT -gt 0 ]]; then
    for ((i=1; i<=WORKER_COUNT; i++)); do
        echo "  - Worker $i: ${WORKER_IPS[$((i-1))]} (${WORKER_USERS[$((i-1))]})"
    done
fi
if [[ -n "$LB_IP" ]]; then
    echo "  - Load Balancer: $LB_IP ($LB_USER)"
fi
echo
echo -e "${RED}IMPORTANT SECURITY NOTE:${NC}"
echo "The vault.yml file contains unencrypted passwords."
echo "To encrypt it, run:"
echo "  ansible-vault encrypt $VAULT_FILE"
echo

# Ask if user wants to run full cluster setup automatically
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}    Automatic Cluster Setup Option        ${NC}"
echo -e "${BLUE}============================================${NC}"
echo
echo -e "${YELLOW}Would you like to run the complete cluster setup automatically?${NC}"
echo "This will execute the following scripts in order:"
echo "  1. 🌐 configure-network.sh"
echo "  2. 🐳 install-docker.sh"
echo "  3. ☸️  install-kubernetes.sh"
if [[ -n "$LB_IP" ]]; then
    echo "  4. ⚖️  install-haproxy.sh (Load Balancer detected)"
    echo "  5. 🚀 initialize-cluster.sh"
    echo "  6. 🕸️  deploy-weave.sh"
    echo "  7. 💾 setup-nfs-storage.sh"
else
    echo "  4. 🚀 initialize-cluster.sh"
    echo "  5. 🕸️  deploy-weave.sh"
    echo "  6. 💾 setup-nfs-storage.sh"
fi
echo

read -p "Run automatic setup? (y/N): " AUTO_SETUP
AUTO_SETUP=${AUTO_SETUP,,} # Convert to lowercase

if [[ "$AUTO_SETUP" == "y" || "$AUTO_SETUP" == "yes" ]]; then
    echo
    echo -e "${YELLOW}Gathering additional configuration for automatic setup...${NC}"
    
    # Get NFS configuration
    echo
    echo -e "${YELLOW}NFS Storage Configuration:${NC}"
    echo "Available nodes for NFS server:"
    for ((i=1; i<=MASTER_COUNT; i++)); do
        echo "  $i. master$(printf "%02d" $i) (${MASTER_IPS[$((i-1))]})"
    done
    if [[ $WORKER_COUNT -gt 0 ]]; then
        for ((i=1; i<=WORKER_COUNT; i++)); do
            echo "  $((MASTER_COUNT + i)). worker$(printf "%02d" $i) (${WORKER_IPS[$((i-1))]})"
        done
    fi
    if [[ -n "$LB_IP" ]]; then
        echo "  $((MASTER_COUNT + WORKER_COUNT + 1)). loadbalancer ($LB_IP)"
    fi
    echo
    
    while true; do
        if [[ -n "$LB_IP" ]]; then
            total_nodes=$((MASTER_COUNT + WORKER_COUNT + 1))
        else
            total_nodes=$((MASTER_COUNT + WORKER_COUNT))
        fi
        read -p "Select NFS server node (1-$total_nodes) [1]: " nfs_choice
        nfs_choice=${nfs_choice:-1}
        if [[ "$nfs_choice" =~ ^[1-9][0-9]*$ ]] && [[ $nfs_choice -le $total_nodes ]]; then
            if [[ $nfs_choice -le $MASTER_COUNT ]]; then
                NFS_SERVER="master$(printf "%02d" $nfs_choice)"
            elif [[ $nfs_choice -le $((MASTER_COUNT + WORKER_COUNT)) ]]; then
                worker_num=$((nfs_choice - MASTER_COUNT))
                NFS_SERVER="worker$(printf "%02d" $worker_num)"
            else
                NFS_SERVER="loadbalancer"
            fi
            break
        else
            echo -e "${RED}Please enter a number between 1 and $total_nodes${NC}"
        fi
    done
    
    read -p "NFS share directory [/kubernetes]: " NFS_SHARE_DIR
    NFS_SHARE_DIR=${NFS_SHARE_DIR:-/kubernetes}
    
    # Get control plane endpoint for cluster initialization
    echo
    echo -e "${YELLOW}Cluster Initialization Configuration:${NC}"
    if [[ -n "$LB_IP" ]]; then
        CONTROL_PLANE_ENDPOINT="$LB_IP:6443"
        echo "Control plane endpoint: $CONTROL_PLANE_ENDPOINT (Load Balancer)"
    else
        CONTROL_PLANE_ENDPOINT="${MASTER_IPS[0]}:6443"
        echo "Control plane endpoint: $CONTROL_PLANE_ENDPOINT (First Master)"
    fi
    
    # Display configuration summary
    echo
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}    Automatic Setup Configuration         ${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo -e "${YELLOW}Cluster Configuration:${NC}"
    echo "  - Masters: $MASTER_COUNT nodes"
    echo "  - Workers: $WORKER_COUNT nodes"
    echo "  - Load Balancer: $([ -n "$LB_IP" ] && echo "Yes ($LB_IP)" || echo "No")"
    echo "  - Control Plane: $CONTROL_PLANE_ENDPOINT"
    echo
    echo -e "${YELLOW}NFS Storage Configuration:${NC}"
    echo "  - NFS Server: $NFS_SERVER"
    echo "  - Share Directory: $NFS_SHARE_DIR"
    echo
    echo -e "${YELLOW}Execution Order:${NC}"
    echo "  1. Network configuration"
    echo "  2. Docker installation"
    echo "  3. Kubernetes installation"
    if [[ -n "$LB_IP" ]]; then
        echo "  4. HAProxy installation (Load Balancer)"
        echo "  5. Cluster initialization"
        echo "  6. Weave CNI deployment"
        echo "  7. NFS storage setup"
    else
        echo "  4. Cluster initialization (Single Master)"
        echo "  5. Weave CNI deployment"
        echo "  6. NFS storage setup"
    fi
    echo
    
    read -p "Proceed with automatic setup? (y/N): " CONFIRM_AUTO
    CONFIRM_AUTO=${CONFIRM_AUTO,,}
    
    if [[ "$CONFIRM_AUTO" == "y" || "$CONFIRM_AUTO" == "yes" ]]; then
        echo
        echo -e "${GREEN}============================================${NC}"
        echo -e "${GREEN}  Starting Automatic Cluster Setup...     ${NC}"
        echo -e "${GREEN}============================================${NC}"
        
        # Store variables for scripts
        export CLUSTER_CONTROL_PLANE_ENDPOINT="$CONTROL_PLANE_ENDPOINT"
        export CLUSTER_NFS_SERVER="$NFS_SERVER"
        export CLUSTER_NFS_SHARE_DIR="$NFS_SHARE_DIR"
        
        # Function to run script with error handling
        run_script() {
            local script_name="$1"
            local description="$2"
            echo
            echo -e "${YELLOW}Running $description...${NC}"
            if [[ -f "$SCRIPT_DIR/$script_name" ]]; then
                if ./"$script_name"; then
                    echo -e "${GREEN}✅ $description completed successfully${NC}"
                else
                    echo -e "${RED}❌ $description failed${NC}"
                    echo -e "${RED}Please check the error above and run manually: ./$script_name${NC}"
                    exit 1
                fi
            else
                echo -e "${RED}❌ Script $script_name not found${NC}"
                exit 1
            fi
        }
        
        # Run scripts in sequence
        run_script "configure-network.sh" "Network Configuration"
        run_script "install-docker.sh" "Docker Installation"
        run_script "install-kubernetes.sh" "Kubernetes Installation"
        
        if [[ -n "$LB_IP" ]]; then
            run_script "install-haproxy.sh" "HAProxy Installation"
        fi
        
        run_script "initialize-cluster.sh" "Cluster Initialization"
        run_script "deploy-weave.sh" "Weave CNI Deployment"
        
        # Run NFS setup with parameters
        echo
        echo -e "${YELLOW}Running NFS Storage Setup...${NC}"
        if [[ -f "$SCRIPT_DIR/setup-nfs-storage.sh" ]]; then
            # Create automated NFS setup script
            cat > /tmp/nfs-auto-setup.sh << 'NFS_AUTO_EOF'
#!/bin/bash
echo "1"           # Select master01 as default
echo ""            # Use default /kubernetes directory
echo "y"           # Confirm setup
echo "y"           # Proceed with setup
NFS_AUTO_EOF
            
            if ./"setup-nfs-storage.sh" < /tmp/nfs-auto-setup.sh; then
                echo -e "${GREEN}✅ NFS Storage Setup completed successfully${NC}"
                rm -f /tmp/nfs-auto-setup.sh
            else
                echo -e "${RED}❌ NFS Storage Setup failed${NC}"
                echo -e "${RED}Please run manually: ./setup-nfs-storage.sh${NC}"
                rm -f /tmp/nfs-auto-setup.sh
                exit 1
            fi
        else
            echo -e "${RED}❌ Script setup-nfs-storage.sh not found${NC}"
            exit 1
        fi
        
        echo
        echo -e "${GREEN}============================================${NC}"
        echo -e "${GREEN}  🎉 Cluster Setup Completed Successfully! ${NC}"
        echo -e "${GREEN}============================================${NC}"
        echo
        echo -e "${YELLOW}Your Kubernetes cluster is ready!${NC}"
        echo
        echo -e "${YELLOW}Cluster Information:${NC}"
        echo "  - Control Plane: $CONTROL_PLANE_ENDPOINT"
        echo "  - NFS Storage: $NFS_SERVER:$NFS_SHARE_DIR"
        echo "  - Default Storage Class: local-path"
        echo
        echo -e "${YELLOW}Next steps:${NC}"
        echo "  1. Verify cluster: kubectl get nodes"
        echo "  2. Test storage: kubectl get storageclass"
        echo "  3. Deploy applications with persistent storage"
        echo
        
    else
        echo -e "${YELLOW}Automatic setup cancelled.${NC}"
        print_manual_steps
    fi
else
    print_manual_steps
fi

# Function to print manual steps
print_manual_steps() {
    echo
    echo -e "${BLUE}============================================${NC}"
    echo -e "${BLUE}      Manual Setup Instructions            ${NC}"
    echo -e "${BLUE}============================================${NC}"
    echo
    echo -e "${YELLOW}Run the following scripts in order:${NC}"
    echo
    echo -e "${YELLOW}1. Configure Network Settings:${NC}"
    echo "   ./configure-network.sh"
    echo "   ${GREEN}Purpose:${NC} Updates /etc/hosts and configures network settings"
    echo
    echo -e "${YELLOW}2. Install Docker:${NC}"
    echo "   ./install-docker.sh"
    echo "   ${GREEN}Purpose:${NC} Installs Docker and containerd on all nodes"
    echo
    echo -e "${YELLOW}3. Install Kubernetes:${NC}"
    echo "   ./install-kubernetes.sh"
    echo "   ${GREEN}Purpose:${NC} Installs kubeadm, kubelet, and kubectl"
    echo
    if [[ -n "$LB_IP" ]]; then
        echo -e "${YELLOW}4. Install HAProxy (Load Balancer):${NC}"
        echo "   ./install-haproxy.sh"
        echo "   ${GREEN}Purpose:${NC} Configures load balancer for cluster API"
        echo
        echo -e "${YELLOW}5. Initialize Cluster:${NC}"
        echo "   ./initialize-cluster.sh"
        echo "   ${GREEN}Purpose:${NC} Initializes the cluster and joins nodes"
        echo
        echo -e "${YELLOW}6. Deploy Weave CNI:${NC}"
        echo "   ./deploy-weave.sh"
        echo "   ${GREEN}Purpose:${NC} Installs network plugin for pod communication"
        echo
        echo -e "${YELLOW}7. Setup NFS Storage:${NC}"
        echo "   ./setup-nfs-storage.sh"
        echo "   ${GREEN}Purpose:${NC} Configures NFS and local-path-provisioner"
    else
        echo -e "${YELLOW}4. Initialize Cluster:${NC}"
        echo "   ./initialize-cluster.sh"
        echo "   ${GREEN}Purpose:${NC} Initializes the cluster and joins nodes"
        echo
        echo -e "${YELLOW}5. Deploy Weave CNI:${NC}"
        echo "   ./deploy-weave.sh"
        echo "   ${GREEN}Purpose:${NC} Installs network plugin for pod communication"
        echo
        echo -e "${YELLOW}6. Setup NFS Storage:${NC}"
        echo "   ./setup-nfs-storage.sh"
        echo "   ${GREEN}Purpose:${NC} Configures NFS and local-path-provisioner"
    fi
    echo
    echo -e "${YELLOW}Important Notes:${NC}"
    echo "  • Run scripts in the exact order shown above"
    echo "  • Wait for each script to complete successfully"
    echo "  • Check for any error messages before proceeding"
    echo "  • Use the same vault password for all scripts"
    echo
    echo -e "${YELLOW}Troubleshooting:${NC}"
    echo "  • If a script fails, fix the issue and re-run"
    echo "  • Check log files in /var/log/ for detailed errors"
    echo "  • Verify network connectivity between all nodes"
    echo "  • Ensure sufficient resources on all nodes"
    echo
}

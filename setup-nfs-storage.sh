#!/bin/bash

# NFS Storage Configuration for Kubernetes Cluster
# Sets up NFS server on one node and mounts on all others

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY_FILE="$SCRIPT_DIR/inventory.ini"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}    NFS Storage Configuration Setup       ${NC}"
echo -e "${BLUE}============================================${NC}"
echo

echo -e "${YELLOW}NFS Storage Setup Tasks:${NC}"
echo "1. 📁 Choose NFS server node and share directory"
echo "2. 🔧 Install NFS server on chosen node"
echo "3. 📦 Install NFS client on remaining nodes"
echo "4. 📂 Create shared directory on all nodes"
echo "5. 🔐 Configure permissions and exports"
echo "6. 🔗 Mount NFS share on all client nodes"
echo "7. ✅ Test NFS functionality"
echo "8. 🚀 Deploy local-path-provisioner with NFS path"
echo

# Check if inventory file exists
if [[ ! -f "$INVENTORY_FILE" ]]; then
    echo -e "${RED}Error: inventory.ini not found!${NC}"
    exit 1
fi

# Get available nodes
echo -e "${YELLOW}Available nodes in your cluster:${NC}"
echo "Masters:"
grep -A 10 '\[masters\]' "$INVENTORY_FILE" | grep -v '\[' | grep -v '^$' | nl -v1
echo "Workers:"
grep -A 10 '\[workers\]' "$INVENTORY_FILE" | grep -v '\[' | grep -v '^$' | nl -v1
echo "Load Balancer:"
grep -A 10 '\[loadbalancers\]' "$INVENTORY_FILE" | grep -v '\[' | grep -v '^$' | nl -v1
echo

# Ask user to choose NFS server node
echo -e "${YELLOW}NFS Server Node Selection:${NC}"
echo "Which node should act as the NFS server?"
echo "1. master01 (recommended for small clusters)"
echo "2. master02"
echo "3. worker01"
echo "4. worker02"
echo "5. loadbalancer (not recommended)"
echo

read -p "Select NFS server node (1-5): " server_choice

case $server_choice in
    1) NFS_SERVER="master01" ;;
    2) NFS_SERVER="master02" ;;
    3) NFS_SERVER="worker01" ;;
    4) NFS_SERVER="worker02" ;;
    5) NFS_SERVER="loadbalancer" ;;
    *)
        echo -e "${RED}Invalid choice. Using master01 as default.${NC}"
        NFS_SERVER="master01"
        ;;
esac

echo -e "${GREEN}Selected NFS server: ${NFS_SERVER}${NC}"
echo

# Ask user for share directory
echo -e "${YELLOW}NFS Share Directory Configuration:${NC}"
echo "What directory should be shared via NFS?"
echo "Examples:"
echo "  /kubernetes (default)"
echo "  /nfs-storage"
echo "  /shared-storage"
echo "  /data"
echo

read -p "Enter share directory path [/kubernetes]: " share_dir
share_dir=${share_dir:-/kubernetes}

echo -e "${GREEN}NFS share directory: ${share_dir}${NC}"
echo

# Ask for confirmation
echo -e "${YELLOW}Configuration Summary:${NC}"
echo "  🖥️  NFS Server: ${NFS_SERVER}"
echo "  📁 Share Directory: ${share_dir}"
echo "  🔗 Clients: All other nodes will mount this share"
echo

read -p "Do you want to proceed with NFS setup? (y/N): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "NFS setup cancelled."
    exit 0
fi

echo
echo -e "${YELLOW}Starting NFS configuration...${NC}"

# Export variables for use in Ansible
export NFS_SERVER
export NFS_SHARE_DIR="$share_dir"

# Use external playbook
NFS_PLAYBOOK="$SCRIPT_DIR/playbooks/nfs-setup.yml"

if [[ ! -f "$NFS_PLAYBOOK" ]]; then
    echo -e "${RED}Error: NFS playbook not found at $NFS_PLAYBOOK${NC}"
    exit 1
fi

echo "Running NFS setup playbook..."
ansible-playbook -i "$INVENTORY_FILE" "$NFS_PLAYBOOK" \
    --ask-vault-pass \
    --extra-vars "ansible_nfs_server=${NFS_SERVER} ansible_nfs_share_dir=${share_dir}"

exit_code=$?

if [[ $exit_code -eq 0 ]]; then
    echo
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}  NFS Storage Setup Completed!            ${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo
    
    echo -e "${YELLOW}NFS Configuration Summary:${NC}"
    echo "  🖥️  NFS Server: ${NFS_SERVER}"
    echo "  📁 Share Directory: ${share_dir}"
    echo "  📦 Server Package: nfs-kernel-server"
    echo "  📦 Client Package: nfs-common (on other nodes)"
    echo "  🔗 Mount Point: ${share_dir} on all nodes"
    echo
    
    # Update local-path-provisioner.yaml
    echo -e "${YELLOW}Updating local-path-provisioner configuration...${NC}"
    
    # Create backup
    cp "${SCRIPT_DIR}/manifests/local-path-provisioner.yaml" "${SCRIPT_DIR}/manifests/local-path-provisioner.yaml.backup"
    
    # Update the path in the configuration
    sed -i "s|/kubernetes|${share_dir}|g" "${SCRIPT_DIR}/manifests/local-path-provisioner.yaml"
    
    echo -e "${GREEN}✅ Updated local-path-provisioner to use: ${share_dir}${NC}"
    echo
    
    echo -e "${YELLOW}Deploying local-path-provisioner...${NC}"
    
    # Deploy the local-path-provisioner
    ansible master01 -i "$INVENTORY_FILE" -m shell -a "kubectl apply -f /tmp/k8s-manifests/local-path-provisioner.yaml" --ask-vault-pass > /dev/null 2>&1 || {
        # Copy manifest and apply
        ansible master01 -i "$INVENTORY_FILE" -m copy -a "src=${SCRIPT_DIR}/manifests/local-path-provisioner.yaml dest=/tmp/local-path-provisioner.yaml" --ask-vault-pass
        ansible master01 -i "$INVENTORY_FILE" -m shell -a "kubectl apply -f /tmp/local-path-provisioner.yaml" --ask-vault-pass
    }
    
    echo
    echo -e "${YELLOW}Verifying deployment...${NC}"
    sleep 5
    
    # Check local-path-provisioner status
    ansible master01 -i "$INVENTORY_FILE" -m shell -a "kubectl get pods -n local-path-storage" --ask-vault-pass
    
    echo
    echo -e "${YELLOW}Verifying storage class...${NC}"
    ansible master01 -i "$INVENTORY_FILE" -m shell -a "kubectl get storageclass" --ask-vault-pass
    
    echo
    echo -e "${BLUE}Next steps:${NC}"
    echo "1. Test persistent storage:"
    echo "   kubectl create -f - <<EOF"
    echo "   apiVersion: v1"
    echo "   kind: PersistentVolumeClaim"
    echo "   metadata:"
    echo "     name: test-pvc"
    echo "   spec:"
    echo "     accessModes: [ReadWriteOnce]"
    echo "     storageClassName: local-path"
    echo "     resources:"
    echo "       requests:"
    echo "         storage: 1Gi"
    echo "   EOF"
    echo
    echo "2. Use in deployments:"
    echo "   volumes:"
    echo "   - name: storage"
    echo "     persistentVolumeClaim:"
    echo "       claimName: test-pvc"
    echo
else
    echo
    echo -e "${RED}============================================${NC}"
    echo -e "${RED}  NFS Storage Setup Failed!               ${NC}"
    echo -e "${RED}============================================${NC}"
    echo
    echo "Please check the error messages above and try again."
    echo
    echo -e "${YELLOW}Troubleshooting tips:${NC}"
    echo "1. Verify all nodes are accessible"
    echo "2. Check if ports 111, 2049 are open"
    echo "3. Ensure sufficient disk space on ${NFS_SERVER}"
    echo "4. Check network connectivity between nodes"
    echo "5. Verify sudo privileges on all nodes"
fi

exit $exit_code
#!/bin/bash

# Default values
DEFAULT_DOMAIN="k8s.dev"
DEFAULT_WORKER_COUNT=3
PRIVATE_KEY_PATH="./locals/private_key"
HOST_FILE_PATH="./locals/hosts"
SSH_USER="root"
LOCAL_HOSTS_FILE="/etc/hosts"

# Function to display usage
usage() {
    echo "Usage: $0 {build|destroy} [--domain DOMAIN] [--auth_token AUTH_TOKEN] [--org_id ORG_ID] [--worker_count WORKER_COUNT]"
    exit 1
}

# Function to parse arguments
parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --domain) DOMAIN="$2"; shift ;;
            --auth_token) AUTH_TOKEN="$2"; shift ;;
            --org_id) ORG_ID="$2"; shift ;;
            --worker_count) WORKER_COUNT="$2"; shift ;;
            *) echo "Unknown parameter passed: $1"; usage ;;
        esac
        shift
    done

    # Check environment variables if flags are not provided
    DOMAIN="${DOMAIN:-${DOMAIN_ENV:-$DEFAULT_DOMAIN}}"
    AUTH_TOKEN="${AUTH_TOKEN:-$AUTH_TOKEN_ENV}"
    ORG_ID="${ORG_ID:-$ORG_ID_ENV}"
    WORKER_COUNT="${WORKER_COUNT:-${WORKER_COUNT_ENV:-$DEFAULT_WORKER_COUNT}}"
}

# Function to validate required parameters
validate_params() {
    if [[ -z "$AUTH_TOKEN" ]]; then
        echo "Error: auth_token is required"
        usage
    fi

    if [[ -z "$ORG_ID" ]]; then
        echo "Error: org_id is required"
        usage
    fi
}

# Function to append hosts file entries to local hosts file
append_to_local_hosts() {
    echo "Appending hosts file entries to local hosts file..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        LOCAL_HOSTS_FILE="/etc/hosts"
    elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
        LOCAL_HOSTS_FILE="C:\Windows\System32\drivers\etc\hosts"
    fi

    sudo cat "$HOST_FILE_PATH" >> "$LOCAL_HOSTS_FILE"
    if [[ $? -ne 0 ]]; then
        echo "Failed to append entries to local hosts file.  Please complete this step manually."
    fi
    echo "Entries appended to local hosts file successfully."
}

# Function to remove hosts file entries from local hosts file
remove_from_local_hosts() {
    echo "Removing hosts file entries from local hosts file..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        LOCAL_HOSTS_FILE="/etc/hosts"
    elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "win32" ]]; then
        LOCAL_HOSTS_FILE="C:\Windows\System32\drivers\etc\hosts"
    fi

    while read -r line; do
        sudo sed -i.bak "/$line/d" "$LOCAL_HOSTS_FILE"
    done < "$HOST_FILE_PATH"
    if [[ $? -ne 0 ]]; then
        echo "Failed to remove entries from local hosts file.  Please remove them manually."
    fi
    echo "Entries removed from local hosts file successfully."
}

# Function to check for and apply Portworx config if it exists
apply_portworx_config() {
    PORTWORX_CONFIG=$(find ./locals -type f -name "*.yaml" ! -name "kubelet.yaml")
    if [[ -n "$PORTWORX_CONFIG" ]]; then
        echo "Portworx config found: $PORTWORX_CONFIG"
        scp -o "StrictHostKeyChecking=no" -i "$PRIVATE_KEY_PATH" "$PORTWORX_CONFIG" "$SSH_USER@$MASTER_IP:/etc/kubernetes/portworx.yaml"
        if [[ $? -ne 0 ]]; then
            echo "Failed to copy Portworx config to the master node. Exiting."
            exit 1
        fi
        # Install Portworx CRDs
        ssh -o "StrictHostKeyChecking=no" -i "$PRIVATE_KEY_PATH" "$SSH_USER@$MASTER_IP" "KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f 'https://install.portworx.com/3.1?comp=pxoperator&kbver=1.28.1&ns=portworx'"
        if [[ $? -ne 0 ]]; then
            echo "Failed to install Portworx CRDs on the master node. Exiting."
            exit 1
        fi
        # Apply Portworx config
        ssh -o "StrictHostKeyChecking=no" -i "$PRIVATE_KEY_PATH" "$SSH_USER@$MASTER_IP" "KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f /etc/kubernetes/portworx.yaml"
        if [[ $? -ne 0 ]]; then
            echo "Failed to apply Portworx config on the master node. Exiting."
            exit 1
        fi
        echo "Portworx config applied successfully on the cluster."
    else
        echo "No Portworx config found. Skipping Portworx installation."
    fi
}

# Function to update /etc/hosts on all nodes
update_hosts_file() {
    for HOST_ENTRY in "${HOST_ENTRIES[@]}"; do
        IP=$(echo "$HOST_ENTRY" | awk '{print $1}')
        ssh -o "StrictHostKeyChecking=no" -i "$PRIVATE_KEY_PATH" "$SSH_USER@$IP" "sudo sh -c 'cat >> /etc/hosts'" < "$HOST_FILE_PATH"
        if [[ $? -ne 0 ]]; then
            echo "Failed to update /etc/hosts on $IP"
            exit 1
        fi
    done
    echo "Hosts file updated successfully on all nodes."
}

# Function to wait for cloud-init to complete on the master node
wait_for_cloud_init() {
    CLOUD_INIT_MARKER="/var/lib/cloud/instance/boot-finished"
    while true; do
        ssh -o "StrictHostKeyChecking=no" -i "$PRIVATE_KEY_PATH" "$SSH_USER@$MASTER_IP" "sudo test -f $CLOUD_INIT_MARKER" && break
        echo "Waiting for cloud-init to complete on the master node..."
        sleep 10
    done
}

# Function to copy the kubelet configuration file to the master node
copy_kubelet_config() {
    scp -o "StrictHostKeyChecking=no" -i "$PRIVATE_KEY_PATH" ./locals/kubelet.yaml "$SSH_USER@$MASTER_IP:/etc/kubernetes/kubelet.yaml"
    if [[ $? -ne 0 ]]; then
        echo "Failed to copy kubelet.yaml to the master node. Exiting."
        exit 1
    fi
    echo "kubelet.yaml copied to the master node successfully."
}

# Function to initialize the master node
initialize_master_node() {
    # Copy the kubelet configuration file to the master node
    copy_kubelet_config

    # Run kubeadm init on the master node and capture the join command
    KUBEADM_OUTPUT=$(ssh -o "StrictHostKeyChecking=no" -i "$PRIVATE_KEY_PATH" "$SSH_USER@$MASTER_IP" "sudo kubeadm init --config=/etc/kubernetes/kubelet.yaml" 2>&1 | tee >(cat >&2))
    if [[ $? -ne 0 ]]; then
        echo "kubeadm init failed on the master node. Exiting."
        echo "$KUBEADM_OUTPUT"
        exit 1
    fi

    # Extract the second join command for worker nodes
    JOIN_COMMAND=$(echo "$KUBEADM_OUTPUT" | awk '
        BEGIN {count = 0; join_cmd = ""} 
        /kubeadm join/ {count++} 
        count == 2 {join_cmd = join_cmd $0; getline; while($0 ~ /\\$/) {join_cmd = join_cmd $0; getline} join_cmd = join_cmd $0} 
        END {print join_cmd}' | sed 's/\\//g')
    if [[ -z "$JOIN_COMMAND" ]]; then
        echo "Failed to extract the kubeadm join command."
        exit 1
    fi

    echo "Join command extracted: $JOIN_COMMAND"

    # Rename context on the master node
    ssh -o "StrictHostKeyChecking=no" -i "$PRIVATE_KEY_PATH" "$SSH_USER@$MASTER_IP" "KUBECONFIG=/etc/kubernetes/admin.conf kubectl config rename-context kubernetes-admin@kubernetes equinix_k8s"

    # Copy kube config to local file
    copy_kube_config

    # Set KUBECONFIG on the master node
    set_kubeconfig_on_master
}

# Function to set KUBECONFIG on the master node
set_kubeconfig_on_master() {
    ssh -o "StrictHostKeyChecking=no" -i "$PRIVATE_KEY_PATH" "$SSH_USER@$MASTER_IP" "echo 'export KUBECONFIG=/etc/kubernetes/admin.conf' >> /root/.bashrc && source /root/.bashrc"
}

# Function to copy kube config from the master node
copy_kube_config() {
    scp -o "StrictHostKeyChecking=no" -i "$PRIVATE_KEY_PATH" "$SSH_USER@$MASTER_IP:/etc/kubernetes/admin.conf" ./kube_config
    if [[ $? -ne 0 ]]; then
        echo "Failed to copy kube config from the master node. Exiting."
        exit 1
    fi
    echo "Kubernetes master initialized successfully and kube config copied to local file."

    # Set context name in kubeconfig
    kubectl config set-context equinix_k8s --cluster=my-cluster --user=kubernetes-admin --kubeconfig=./kube_config
    kubectl config use-context equinix_k8s --kubeconfig=./kube_config
}

# Function to join worker nodes to the cluster
join_worker_nodes() {
    for WORKER_IP in "${WORKER_IPS[@]}"; do
        ssh -o "StrictHostKeyChecking=no" -i "$PRIVATE_KEY_PATH" "$SSH_USER@$WORKER_IP" "sudo $JOIN_COMMAND"
        if [[ $? -ne 0 ]]; then
            echo "Failed to join worker node $WORKER_IP to the cluster. Exiting."
            exit 1
        fi
    done
    echo "All worker nodes joined the cluster successfully."
}

# Function to install Calico on the master node
install_calico() {
    ssh -o "StrictHostKeyChecking=no" -i "$PRIVATE_KEY_PATH" "$SSH_USER@$MASTER_IP" "KUBECONFIG=/etc/kubernetes/admin.conf kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml"
    if [[ $? -ne 0 ]]; then
        echo "Failed to install Calico on the master node. Exiting."
        exit 1
    fi
    echo "Calico installed successfully on the cluster."
}

# Function to handle the build process
build() {
    parse_args "$@"
    validate_params

    # Initialize Terraform
    terraform init

    # Apply Terraform configuration
    terraform apply -var "domain=$DOMAIN" -var "auth_token=$AUTH_TOKEN" -var "org_id=$ORG_ID" -var "worker_count=$WORKER_COUNT" --auto-approve | tee terraform_apply_output.log
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        echo "Terraform apply failed. Exiting."
        exit 1
    fi
    echo "Terraform apply completed successfully. Proceeding to the next phase..."

    # Parse the hosts file
    if [[ ! -f "$HOST_FILE_PATH" ]]; then
        echo "Error: hosts file not found."
        exit 1
    fi

    HOST_ENTRIES=()
    while IFS= read -r line; do
        HOST_ENTRIES+=("$line")
    done < "$HOST_FILE_PATH"

    MASTER_IP=$(echo "${HOST_ENTRIES[0]}" | awk '{print $1}')
    MASTER_HOSTNAME=$(echo "${HOST_ENTRIES[0]}" | awk '{print $2}')

    WORKER_IPS=()
    WORKER_HOSTNAMES=()
    for i in "${!HOST_ENTRIES[@]}"; do
        if [[ $i -ne 0 ]]; then
            WORKER_IPS+=($(echo "${HOST_ENTRIES[$i]}" | awk '{print $1}'))
            WORKER_HOSTNAMES+=($(echo "${HOST_ENTRIES[$i]}" | awk '{print $2}'))
        fi
    done

    # Update /etc/hosts on all nodes
    update_hosts_file

    # Append hosts file entries to local hosts file
    append_to_local_hosts

    # Wait for cloud init to complete
    wait_for_cloud_init

    # Initialize the master node
    initialize_master_node

    # Join worker nodes to the cluster
    join_worker_nodes

    # Install Calico
    install_calico

    # Apply Portworx config if it exists
    # apply_portworx_config
}

# Function to handle the destroy process
destroy() {
    parse_args "$@"
    validate_params

    # Remove hosts file entries from local hosts file
    # Must be done before terraform destroy because file will be deleted
    remove_from_local_hosts

    # Initiate terraform destroy and capture the output
    terraform destroy -var "auth_token=$AUTH_TOKEN" -var "org_id=$ORG_ID" --auto-approve | tee terraform_destroy_output.log
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        echo "Terraform destroy failed. Exiting."
        exit 1
    fi

    if [[ -f "kube_config" ]]; then
        rm "kube_config"
        echo "Deleted kube_config file."
    fi

    

    echo "Terraform destroy completed successfully."
}

# Check the first argument
if [[ "$1" == "build" ]]; then
    shift
    build "$@"
elif [[ "$1" == "destroy" ]]; then
    shift
    destroy "$@"
else
    usage
fi

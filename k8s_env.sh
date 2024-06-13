#!/bin/bash

# Default values
DEFAULT_DOMAIN="k8s.dev"
DEFAULT_WORKER_COUNT=3
PRIVATE_KEY_PATH="private_key"

# Function to display usage
usage() {
    echo "Usage: $0 {build|destroy} [--domain DOMAIN] [--auth_token AUTH_TOKEN] [--org_id ORG_ID] [--worker_count WORKER_COUNT]"
    exit 1
}

# Function to handle the build process
build() {
    # Parse arguments
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

    # Validate required parameters
    if [[ -z "$AUTH_TOKEN" ]]; then
        echo "Error: auth_token is required"
        usage
    fi

    if [[ -z "$ORG_ID" ]]; then
        echo "Error: org_id is required"
        usage
    fi

    # Initiate terraform apply and capture the output
    terraform apply -var "domain=$DOMAIN" -var "auth_token=$AUTH_TOKEN" -var "org_id=$ORG_ID" -var "worker_count=$WORKER_COUNT" | tee terraform_apply_output.log
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        echo "Terraform apply failed. Exiting."
        exit 1
    fi

    echo "Terraform apply completed successfully. Proceeding to the next phase..."

    # Parse the hosts file
    if [[ ! -f hosts ]]; then
        echo "Error: hosts file not found."
        exit 1
    fi

    # Read the hosts file and identify master and workers
    readarray -t HOST_ENTRIES < hosts
    if [[ ${#HOST_ENTRIES[@]} -eq 0 ]]; then
        echo "Error: hosts file is empty."
        exit 1
    fi

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

    # Append the contents of hosts file to the remote servers' /etc/hosts
    for HOST_ENTRY in "${HOST_ENTRIES[@]}"; do
        IP=$(echo "$HOST_ENTRY" | awk '{print $1}')
        ssh -i $PRIVATE_KEY_PATH "$IP" "sudo sh -c 'cat >> /etc/hosts'" < hosts
        if [[ $? -ne 0 ]]; then
            echo "Failed to update /etc/hosts on $IP"
            exit 1
        fi
    done

    echo "Hosts file updated successfully on all nodes."

    # Run kubeadm init on the master node and capture the join command
    KUBEADM_OUTPUT=$(ssh -i $PRIVATE_KEY_PATH "$MASTER_IP" "sudo kubeadm init --pod-network-cidr=192.168.0.0/16" 2>&1)
    if [[ $? -ne 0 ]]; then
        echo "kubeadm init failed on the master node. Exiting."
        echo "$KUBEADM_OUTPUT"
        exit 1
    fi

    # Extract the join command from the kubeadm output
    JOIN_COMMAND=$(echo "$KUBEADM_OUTPUT" | grep -o "kubeadm join.*--discovery-token-ca-cert-hash sha256:[a-f0-9]*")
    if [[ -z "$JOIN_COMMAND" ]]; then
        echo "Failed to extract the kubeadm join command."
        exit 1
    fi

    echo "Join command extracted: $JOIN_COMMAND"

    # Copy kube config to local file
    ssh -i $PRIVATE_KEY_PATH "$MASTER_IP" "sudo cat /etc/kubernetes/admin.conf" > kube_config
    if [[ $? -ne 0 ]]; then
        echo "Failed to copy kube config from the master node. Exiting."
        exit 1
    fi

    echo "Kubernetes master initialized successfully and kube config copied to local file."

    # Run the join command on each worker node
    for WORKER_IP in "${WORKER_IPS[@]}"; do
        ssh -i $PRIVATE_KEY_PATH "$WORKER_IP" "sudo $JOIN_COMMAND"
        if [[ $? -ne 0 ]]; then
            echo "Failed to join worker node $WORKER_IP to the cluster. Exiting."
            exit 1
        fi
    done

    echo "All worker nodes joined the cluster successfully."

    # Install Calico on the master node
    ssh -i $PRIVATE_KEY_PATH "$MASTER_IP" "kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml"
    if [[ $? -ne 0 ]]; then
        echo "Failed to install Calico on the master node. Exiting."
        exit 1
    fi

    echo "Calico installed successfully on the cluster."
}

# Function to handle the destroy process
destroy() {
    # Parse arguments
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --auth_token) AUTH_TOKEN="$2"; shift ;;
            --org_id) ORG_ID="$2"; shift ;;
            *) echo "Unknown parameter passed: $1"; usage ;;
        esac
        shift
    done

    # Check environment variables if flags are not provided
    AUTH_TOKEN="${AUTH_TOKEN:-$AUTH_TOKEN_ENV}"
    ORG_ID="${ORG_ID:-$ORG_ID_ENV}"

    # Validate required parameters
    if [[ -z "$AUTH_TOKEN" ]]; then
        echo "Error: auth_token is required"
        usage
    fi

    if [[ -z "$ORG_ID" ]]; then
        echo "Error: org_id is required"
        usage
    fi

    # Initiate terraform destroy and capture the output
    terraform destroy -var "auth_token=$AUTH_TOKEN" -var "org_id=$ORG_ID" | tee terraform_destroy_output.log
    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        echo "Terraform destroy failed. Exiting."
        exit 1
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

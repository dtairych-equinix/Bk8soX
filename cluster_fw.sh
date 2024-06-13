#!/bin/bash

# Default values
PRIVATE_KEY_PATH="private_key"

# Essential firewall rules that should never be removed
ESSENTIAL_RULES=(
    "ufw allow ssh"
    "ufw allow 179/tcp"
    "ufw allow 2379:2380/tcp"
    "ufw allow 6443/tcp"
    "ufw allow 10250/tcp"
    "ufw allow 10251/tcp"
    "ufw allow 10252/tcp"
    "ufw allow 10255/tcp"
    "ufw allow 2049/tcp"
    "ufw allow 3000/tcp"
    "ufw allow 3260/tcp"
    "ufw allow 9001/tcp"
)

# Function to display usage
usage() {
    echo "Usage: $0 {add|remove|list} --ports PORTS [--ips IPS]"
    exit 1
}

# Function to add firewall rules
add_rules() {
    PORTS=()
    IPS=()

    # Parse arguments
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --ports) IFS=',' read -r -a PORTS <<< "$2"; shift ;;
            --ips) IFS=',' read -r -a IPS <<< "$2"; shift ;;
            *) echo "Unknown parameter passed: $1"; usage ;;
        esac
        shift
    done

    if [[ ${#PORTS[@]} -eq 0 ]]; then
        echo "Error: Ports must be specified for adding rules."
        usage
    fi

    # Parse the hosts file
    if [[ ! -f hosts ]]; then
        echo "Error: hosts file not found."
        exit 1
    fi

    readarray -t HOST_ENTRIES < hosts
    if [[ ${#HOST_ENTRIES[@]} -eq 0 ]]; then
        echo "Error: hosts file is empty."
        exit 1
    fi

    # Add firewall rules to each host
    for HOST_ENTRY in "${HOST_ENTRIES[@]}"; do
        IP=$(echo "$HOST_ENTRY" | awk '{print $1}')
        for PORT in "${PORTS[@]}"; do
            if [[ ${#IPS[@]} -eq 0 ]]; then
                ssh -i $PRIVATE_KEY_PATH "$IP" "sudo ufw allow $PORT"
                if [[ $? -ne 0 ]]; then
                    echo "Failed to add rule on $IP: ufw allow $PORT"
                    exit 1
                fi
            else
                for DEST_IP in "${IPS[@]}"; do
                    ssh -i $PRIVATE_KEY_PATH "$IP" "sudo ufw allow from $DEST_IP to any port $PORT"
                    if [[ $? -ne 0 ]]; then
                        echo "Failed to add rule on $IP: ufw allow from $DEST_IP to any port $PORT"
                        exit 1
                    fi
                done
            fi
        done
    done

    echo "Firewall rules added successfully on all nodes."
}

# Function to remove firewall rules
remove_rules() {
    PORTS=()
    IPS=()

    # Parse arguments
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --ports) IFS=',' read -r -a PORTS <<< "$2"; shift ;;
            --ips) IFS=',' read -r -a IPS <<< "$2"; shift ;;
            *) echo "Unknown parameter passed: $1"; usage ;;
        esac
        shift
    done

    if [[ ${#PORTS[@]} -eq 0 ]]; then
        echo "Error: Ports must be specified for removing rules."
        usage
    fi

    # Parse the hosts file
    if [[ ! -f hosts ]]; then
        echo "Error: hosts file not found."
        exit 1
    fi

    readarray -t HOST_ENTRIES < hosts
    if [[ ${#HOST_ENTRIES[@]} -eq 0 ]]; then
        echo "Error: hosts file is empty."
        exit 1
    fi

    # Remove firewall rules from each host
    for HOST_ENTRY in "${HOST_ENTRIES[@]}"; do
        IP=$(echo "$HOST_ENTRY" | awk '{print $1}')
        for PORT in "${PORTS[@]}"; do
            if [[ ${#IPS[@]} -eq 0 ]]; then
                RULE="ufw allow $PORT"
                if [[ ! " ${ESSENTIAL_RULES[@]} " =~ " ${RULE} " ]]; then
                    ssh -i $PRIVATE_KEY_PATH "$IP" "sudo ufw delete allow $PORT"
                    if [[ $? -ne 0 ]]; then
                        echo "Failed to remove rule on $IP: ufw allow $PORT"
                        exit 1
                    fi
                else
                    echo "Skipping removal of essential rule: $RULE"
                fi
            else
                for DEST_IP in "${IPS[@]}"; do
                    RULE="ufw allow from $DEST_IP to any port $PORT"
                    if [[ ! " ${ESSENTIAL_RULES[@]} " =~ " ${RULE} " ]]; then
                        ssh -i $PRIVATE_KEY_PATH "$IP" "sudo ufw delete allow from $DEST_IP to any port $PORT"
                        if [[ $? -ne 0 ]]; then
                            echo "Failed to remove rule on $IP: ufw allow from $DEST_IP to any port $PORT"
                            exit 1
                        fi
                    else
                        echo "Skipping removal of essential rule: $RULE"
                    fi
                done
            fi
        done
    done

    echo "Firewall rules removed successfully on all nodes."
}

# Function to list current firewall rules
list_rules() {
    # Parse the hosts file
    if [[ ! -f hosts ]]; then
        echo "Error: hosts file not found."
        exit 1
    fi

    readarray -t HOST_ENTRIES < hosts
    if [[ ${#HOST_ENTRIES[@]} -eq 0 ]]; then
        echo "Error: hosts file is empty."
        exit 1
    fi

    # List firewall rules from the first host
    IP=$(echo "${HOST_ENTRIES[0]}" | awk '{print $1}')
    ssh -i $PRIVATE_KEY_PATH "$IP" "sudo ufw status verbose"
    if [[ $? -ne 0 ]]; then
        echo "Failed to list firewall rules on $IP"
        exit 1
    fi
}

# Main logic
if [[ "$1" == "add" ]]; then
    shift
    add_rules "$@"
elif [[ "$1" == "remove" ]]; then
    shift
    remove_rules "$@"
elif [[ "$1" == "list" ]]; then
    list_rules
else
    usage
fi

#!/bin/bash

LOG_FILE="$0.log"
exec > >(tee -a $LOG_FILE) 2>&1

DELAY_MINUTES=7
echo "Waiting for ${DELAY_MINUTES} minutes for resources to be available."
sleep $((${DELAY_MINUTES}*60))


# Install dependencies
which nmap || sudo dnf install -y nmap
which showmount || sudo dnf install -y nfsutils

# Define the IP range to scan (adjust as needed)
IP_RANGE="10.0.0.0/28"
MOUNT_POINT="/mnt/nfs_share"
SCAN_PORT=2049

echo "Scanning IP range $IP_RANGE for NFS servers..."

# Find hosts with port 2049 open (NFS)
NFS_HOSTS=$(nmap -p $SCAN_PORT --open -oG - $IP_RANGE | awk '/Ports: 2049\/open/ {print $2}')

if [ -z "$NFS_HOSTS" ]; then
    echo "No NFS servers found in range $IP_RANGE."
    exit 1
fi

echo "Found NFS servers: $NFS_HOSTS"

# Try to find a share from the first available host
for HOST in $NFS_HOSTS; do
    echo "Checking NFS shares on $HOST..."
    SHARES=$(showmount -e $HOST 2>/dev/null | awk 'NR>1 {print $1}')
    
    if [ -n "$SHARES" ]; then
        SHARE=$(echo "$SHARES" | head -n 1)
        echo "Found share $SHARE on $HOST"

        # Create mount point if it doesn't exist
        sudo mkdir -p $MOUNT_POINT

        # Mount the share
        echo "Mounting $HOST:$SHARE to $MOUNT_POINT..."
        sudo mount -t nfs $HOST:$SHARE $MOUNT_POINT

        if [ $? -eq 0 ]; then
            echo "Successfully mounted $HOST:$SHARE to $MOUNT_POINT"
            exit 0
        else
            echo "Failed to mount $HOST:$SHARE"
        fi
    fi
done

echo "No mountable NFS shares found."
exit 1

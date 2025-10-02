#!/bin/bash
#
# Copyright (c) Microsoft Corporation.
#
# Licensed for your reference purposes only on an as is basis, without warranty of any kind.
#
# title          : find-and-mount.sh
# description    : This is script to find and mount a single NFS share in a specific subnet.
# author         : phjensen
# usage          : bash find-and-mount.sh
# required para  : None
# optional para  : None
# dependency     : None
# logging        : Metrics/infomation and Error logs are sent to stdout and ${LOG_FILE} as string.
# notes:         : This is a simple script to search a given subnet for an NFS share and then mount it to a specific location for testing.
#====================================================================================

#======================================================
#  Functions
#======================================================
log() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') - $*"
}

#======================================================
#  Setup logging and wait for resources to be ready
#======================================================
LOG_FILE="/tmp/$0.log"
exec > >(tee -a $LOG_FILE) 2>&1
DELAY_MINUTES=7
log "Started execution of $(pwd)/$0"
log "Waiting for ${DELAY_MINUTES} minutes for resources to be available."
sleep $((${DELAY_MINUTES}*60))

#======================================================
#  Install dependencies
#======================================================
which nmap || sudo dnf install -y nmap
which showmount || sudo dnf install -y nfsutils

#======================================================
#  Define the IP range to scan (adjust as needed)
#======================================================
IP_RANGE="10.0.0.0/28"
SCAN_PORT=2049

#======================================================
#  Find hosts with port 2049 open (NFS)
#======================================================
log "Scanning IP range $IP_RANGE for NFS servers..."
NFS_HOSTS=$(nmap -p $SCAN_PORT --open -oG - $IP_RANGE | awk '/Ports: 2049\/open/ {print $2}')

if [ -z "$NFS_HOSTS" ]; then
    log "No NFS servers found in range $IP_RANGE."
    exit 1
fi
log "Found NFS servers: $NFS_HOSTS"

#======================================================
# Try to find and mount all non-root shares from hosts
#======================================================
for HOST in $NFS_HOSTS; do
  log "Checking NFS shares on $HOST..."
  for SHARE in $(showmount -e $HOST 2>/dev/null | awk 'NR>1 {print $1}')
  do
    VOLUME=$(basename ${SHARE})
    if [ "${VOLUME}" != "/" ]; then
      log "Found volume '${VOLUME}' on $HOST"
      MOUNT_POINT="/mnt/$HOST/$VOLUME"
      sudo mkdir -p $MOUNT_POINT
      sudo chmod -R 777 $MOUNT_POINT
      log "Mounting $HOST:$SHARE to $MOUNT_POINT..."
      sudo mount -t nfs -o rw,hard,rsize=262144,wsize=262144,vers=3,tcp $HOST:$SHARE $MOUNT_POINT
      if [ $? -eq 0 ]; then
        log "Successfully mounted $HOST:$SHARE to $MOUNT_POINT"
        sudo mkdir $MOUNT_POINT/target
        sudo chmod 777 $MOUNT_POINT/target
        touch $MOUNT_POINT/target/junk && log "Directory '$MOUNT_POINT/target' is user writable."
      else
        log "Failed to mount $HOST:$SHARE"
      fi
    fi
  done
done

log "Finished execution."
exit 0

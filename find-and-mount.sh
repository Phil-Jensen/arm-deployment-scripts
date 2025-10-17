#!/usr/bin/env bash
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

set -Eeuo pipefail

#---------------------------------------
# Constants / Configuration
#---------------------------------------
IP_RANGE="10.0.0.0/28"            # Subnet to scan
SCAN_PORT=2049                    # NFS port
DELAY_MINUTES=7                   # Wait time for resource readiness
TMPDIR="${TMPDIR:-/tmp}"
LOG_FILE="${TMPDIR}/$(basename "$0").log"

MOUNT_BASE="/mnt"
MOUNT_OPTS=(rw hard rsize=262144 wsize=262144 vers=3 tcp)  # Intentional v3; adjust if needed

#---------------------------------------
# Logging helpers
#---------------------------------------
log() { printf '%s - %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"; }
err() { printf '%s - ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }
die() { err "$*"; exit 1; }

# Redirect all output to both stdout and LOG_FILE
exec > >(tee -a "$LOG_FILE") 2>&1

trap 'err "Unexpected failure at line ${LINENO}. Exiting."; exit 1' ERR

#---------------------------------------
# Dependencies
#---------------------------------------
ensure_dep() {
  local bin="$1" pkg="$2"
  if ! command -v "$bin" >/dev/null 2>&1; then
    log "Installing dependency: $pkg (for $bin)"
    sudo dnf install -y "$pkg"
  fi
}

#---------------------------------------
# NFS scanning & mounting
#---------------------------------------
scan_nfs_hosts() {
  local range="$1" port="$2"
  log "Scanning IP range ${range} for NFS (port ${port})..."
  # Grepable output; extract IP field (column 2)
  nmap -p "$port" --open -oG - "$range" | awk '/Ports: 2049\/open/ {print $2}'
}

list_exports() {
  local host="$1"
  # Skip header line from showmount -e
  showmount -e "$host" 2>/dev/null | awk 'NR>1 {print $1}'
}

mount_share() {
  local host="$1" share="$2"
  local volume
  volume="$(basename "$share")"

  # Skip root export
  if [[ "$volume" == "/" ]]; then
    log "Skipping root export on $host"
    return 0
  fi

  local mount_point="${MOUNT_BASE}/${host}/${volume}"
  log "Preparing mount point: ${mount_point}"
  sudo mkdir -p "$mount_point"
  sudo chmod -R 0777 "$mount_point"

  log "Mounting ${host}:${share} -> ${mount_point}"
  if sudo mount -t nfs -o "$(IFS=,; echo "${MOUNT_OPTS[*]}")" "${host}:${share}" "$mount_point"; then
    log "Successfully mounted ${host}:${share}"
    local target="${mount_point}/target"
    sudo mkdir -p "$target"
    sudo chmod 0777 "$target"
    : > "${target}/junk" && log "Directory '${target}' is user-writable."
  else
    err "Failed to mount ${host}:${share}"
    return 1
  fi
}

#---------------------------------------
# Main
#---------------------------------------
main() {
  log "========================================"
  log "Started: $(pwd)/$(basename "$0")"
  log "Log file: $LOG_FILE"
  log "========================================"

  log "Waiting ${DELAY_MINUTES} minute(s) for resources to be available..."
  sleep "$((DELAY_MINUTES * 60))"

  # Dependencies
  ensure_dep nmap nmap
  ensure_dep showmount nfs-utils

  # Scan
  mapfile -t nfs_hosts < <(scan_nfs_hosts "$IP_RANGE" "$SCAN_PORT")
  if [[ ${#nfs_hosts[@]} -eq 0 ]]; then
    die "No NFS servers found in range ${IP_RANGE}."
  fi
  log "Found NFS servers: ${nfs_hosts[*]}"

  # Enumerate & mount
  for host in "${nfs_hosts[@]}"; do
    log "Checking NFS exports on ${host}..."
    mapfile -t exports < <(list_exports "$host")

    if [[ ${#exports[@]} -eq 0 ]]; then
      log "No exports found on ${host}."
      continue
    fi

    for share in "${exports[@]}"; do
      mount_share "$host" "$share"
    done
  done

  log "Finished execution."
  log "========================================"
}

main "$@"

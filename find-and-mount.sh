#!/usr/bin/env bash
#
# Copyright (c) Microsoft Corporation.
#
# Licensed for your reference purposes only on an as is basis, without warranty of any kind.
#
# title          : find-and-mount.sh
# description    : This script finds and mounts NFS shares in a specific subnet.
# author         : phjensen
# usage          : bash find-and-mount.sh
# required para  : None
# optional para  : None
# dependency     : nmap, nfs-utils (showmount)
# logging        : Metrics/information and error logs are sent to ${LOG_FILE} only.
# notes          : Searches a given subnet for NFS servers, enumerates exports, and mounts them.
#====================================================================================

set -Eeuo pipefail

#---------------------------------------
# Constants / Configuration
#---------------------------------------
IP_RANGE="10.0.0.0/28"
SCAN_PORT="2049"
POLL_TIMEOUT_MINUTES="7"
POLL_INTERVAL_SECONDS="30"
TMP_DIR="/tmp"
LOG_FILE="${TMP_DIR}/$(basename "$0").log"
MOUNT_BASE="/mnt"
MOUNT_OPTS="rw,hard,vers=3,tcp,rsize=1048576,wsize=1048576"


#---------------------------------------
# Logging helpers
#---------------------------------------
log() { printf '%s - %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> ${LOG_FILE}; }
err() { printf '%s - ERROR: %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >&2; }
panic() { err "$*"; exit 1; }

trap 'panic "Unexpected failure at line ${LINENO}. Exiting."' ERR


#---------------------------------------
# Dependencies
#---------------------------------------
ensure_dep() {
  local _BIN="$1" _PKG="$2"
  if ! command -v "$_BIN" >/dev/null 2>&1; then
    log "Installing dependency: ${_PKG} (for ${_BIN})"
    # Using dnf to match original; adjust if your base image differs
    if command -v dnf >/dev/null 2>&1; then
      sudo dnf install -y "$_PKG"
    elif command -v yum >/dev/null 2>&1; then
      sudo yum install -y "$_PKG"
    elif command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update -y && sudo apt-get install -y "$_PKG"
    else
      panic "No supported package manager found to install ${_PKG}."
    fi
  fi
}


#---------------------------------------
# NFS scanning & mounting
#---------------------------------------
scan_nfs_hosts() {
  local _RANGE="$1" _PORT="$2"
  log "Scanning IP range ${_RANGE} for NFS (port ${_PORT})..."
  # Grepable output; extract IP field (column 2)
  nmap -p "$_PORT" --open -oG - "$_RANGE" | awk '/Ports: 2049\/open/ {print $2}'
}

list_exports() {
  local _HOST="$1"
  local _DELAY_SECS=10
  # Skip header line from showmount -e
  log "Checking for exports on $_HOST in $_DELAY_SECS seconds"
  sleep $_DELAY_SECS
  showmount --no-headers -e "$_HOST" 2>/dev/null | awk 'NR>1 {print $1}'
}

mount_share() {
  local _HOST="$1" _SHARE="$2"
  local _VOLUME
  _VOLUME="$(basename "$_SHARE")"

  # Skip root export
  if [[ "$_VOLUME" == "/" ]]; then
    log "Skipping root export on ${_HOST}"
    return 0
  fi

  local _MOUNT_POINT="${MOUNT_BASE}/${_HOST}/${_VOLUME}"
  log "Preparing mount point: ${_MOUNT_POINT}"
  sudo mkdir -p "$_MOUNT_POINT"
  sudo chmod -R 0777 "$_MOUNT_POINT"

  local _OPTS
  _OPTS="$(IFS=,; echo "${MOUNT_OPTS[*]}")"

  log "Mounting ${_HOST}:${_SHARE} -> ${_MOUNT_POINT} (opts: ${_OPTS})"
  if sudo mount -t nfs -o "${_OPTS}" "${_HOST}:${_SHARE}" "$_MOUNT_POINT"; then
    log "Successfully mounted ${_HOST}:${_SHARE}"
    local _TARGET="${_MOUNT_POINT}/target"
    sudo mkdir -p "$_TARGET"
    sudo chmod 0777 "$_TARGET"
    : > "${_TARGET}/junk" && log "Directory '${_TARGET}' is user-writable."
  else
    err "Failed to mount ${_HOST}:${_SHARE}"
    return 1
  fi
}


# Poll until at least one NFS server is detected or timeout
poll_for_nfs() {
  local _RANGE="$1" _PORT="$2" _TIMEOUT_MIN="$3" _INTERVAL_SEC="$4"
  local _DEADLINE=$((SECONDS + (_TIMEOUT_MIN * 60)))
  local _REMAINING=0

  while :; do
    mapfile -t NFS_HOSTS < <(scan_nfs_hosts "$_RANGE" "$_PORT")
    if [[ ${#NFS_HOSTS[@]} -gt 0 ]]; then
      log "NFS servers detected: ${NFS_HOSTS[*]}"
      return 0
    fi

    _REMAINING=$((_DEADLINE - SECONDS))
    if (( _REMAINING <= 0 )); then
      break
    fi

    log "No NFS servers found yet. Polling again in ${_INTERVAL_SEC}s (time left: ${_REMAINING}s)..."
    sleep "$_INTERVAL_SEC"
  done

  return 1
}


#---------------------------------------
# Main
#---------------------------------------
main() {
  log "========================================"
  log "Started: $(pwd)/$(basename "$0")"
  log "Log file: $LOG_FILE"
  log "Config: IP_RANGE=${IP_RANGE}, SCAN_PORT=${SCAN_PORT}, POLL_TIMEOUT_MINUTES=${POLL_TIMEOUT_MINUTES}, POLL_INTERVAL_SECONDS=${POLL_INTERVAL_SECONDS}"
  log "========================================"

  # (1) Ensure dependencies **before** any waiting/polling so we fail fast if missing
  ensure_dep nmap nmap
  ensure_dep showmount nfs-utils

  # (2) Poll for NFS availability instead of a fixed sleep
  if ! poll_for_nfs "$IP_RANGE" "$SCAN_PORT" "$POLL_TIMEOUT_MINUTES" "$POLL_INTERVAL_SECONDS"; then
    panic "No NFS servers became available in range ${IP_RANGE} within ${POLL_TIMEOUT_MINUTES} minute(s)."
  fi

  # Enumerate & mount
  for HOST in "${NFS_HOSTS[@]}"; do
    log "Checking NFS exports on ${HOST}..."
    mapfile -t EXPORTS < <(list_exports "$HOST")

    if [[ ${#EXPORTS[@]} -eq 0 ]]; then
      log "No exports found on ${HOST}."
      continue
    fi

    for SHARE in "${EXPORTS[@]}"; do
      mount_share "$HOST" "$SHARE"
    done
  done

  log "Finished execution."
  log "========================================"
}

main "$@"

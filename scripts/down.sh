#!/usr/bin/env bash
# Stop all lab VMs (they remain in UTM for a later 'make up').
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_config

for entry in "${LAB_VMS[@]}"; do
  parse_vm_entry "$entry"
  name="$(vm_name "$VM_SHORT")"
  log "Stopping ${name}"
  "$UTMCTL" stop "$name" 2>/dev/null \
    || osascript -e "tell application \"UTM\" to stop virtual machine named \"${name}\"" 2>/dev/null \
    || warn "Could not stop ${name} (not running?)"
  # utmctl stop returns before the guest is fully down; only close the window
  # once "stopped", or UTM pops its "keep running?" dialog instead.
  if stop_vm_and_wait "$name" 60; then
    close_vm_window "$name"
  else
    warn "${name} did not stop in time, leaving its window open"
  fi
done
ok "All lab VMs stopped"

#!/usr/bin/env bash
# Stop and delete all lab VMs and remove generated artifacts.
# Prompts once before deleting. Base images in images/ are kept.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_config

echo "This will DELETE these UTM VMs and all their data:"
for entry in "${LAB_VMS[@]}"; do parse_vm_entry "$entry"; echo "  - $(vm_name "$VM_SHORT")"; done
read -r -p "Type 'yes' to continue: " confirm
[[ "$confirm" == "yes" ]] || { warn "Aborted"; exit 1; }

for entry in "${LAB_VMS[@]}"; do
  parse_vm_entry "$entry"
  name="$(vm_name "$VM_SHORT")"
  log "Stopping and deleting ${name}"
  "$UTMCTL" stop "$name" 2>/dev/null || true
  # Wait for the VM to actually stop; a running VM cannot be deleted.
  for _ in 1 2 3 4 5 6; do
    [[ "$("$UTMCTL" status "$name" 2>/dev/null)" == "started" ]] || break
    sleep 1
  done
  "$UTMCTL" delete "$name" 2>/dev/null \
    || osascript -e "tell application \"UTM\" to delete virtual machine named \"${name}\"" 2>/dev/null \
    || warn "Could not delete ${name} (already gone?)"
done

log "Removing generated artifacts"
rm -rf "$GEN_DIR"
rm -f "$INVENTORY_FILE"
ok "Lab destroyed. Base images kept in images/."

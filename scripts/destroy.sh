#!/usr/bin/env bash
# Stop and delete all lab VMs and remove generated artifacts.
# Prompts once before deleting. Base images in images/ are kept.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_config

echo "This will DELETE these UTM VMs and all their data:"
for entry in "${LAB_VMS[@]}"; do echo "  - $(vm_name "${entry%%:*}")"; done
read -r -p "Type 'yes' to continue: " confirm
[[ "$confirm" == "yes" ]] || { warn "Aborted"; exit 1; }

for entry in "${LAB_VMS[@]}"; do
  name="$(vm_name "${entry%%:*}")"
  log "Stopping and deleting ${name}"
  utmctl stop "$name" 2>/dev/null || true
  utmctl delete "$name" 2>/dev/null \
    || osascript -e "tell application \"UTM\" to delete virtual machine named \"${name}\"" 2>/dev/null \
    || warn "Could not delete ${name} (already gone?)"
done

log "Removing generated artifacts"
rm -rf "$GEN_DIR"
rm -f "$INVENTORY_FILE"
ok "Lab destroyed. Base images kept in images/."

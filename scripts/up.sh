#!/usr/bin/env bash
# Orchestrator: preflight -> fetch image -> create VMs -> wait SSH ->
# generate inventory -> Ansible. Fully hands-off.
# Flags: --provision-only (no Ansible), --configure-only (Ansible only)
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
SCRIPTS="$(dirname "${BASH_SOURCE[0]}")"

require_macos
load_config

MODE="all"
case "${1:-}" in
  --provision-only) MODE="provision" ;;
  --configure-only) MODE="configure" ;;
  "") MODE="all" ;;
  *) die "Unknown flag: $1" ;;
esac

run_ansible() {
  log "Installing Ansible Galaxy requirements"
  ansible-galaxy collection install -r "${ANSIBLE_DIR}/requirements.yaml" >/dev/null
  log "Running Ansible playbook"
  ( cd "$REPO_ROOT" && ansible-playbook "${ANSIBLE_DIR}/playbook.yaml" \
      -e "attacker_toolset=${ATTACKER_TOOLSET:-curated}" \
      -e "attacker_gui=${ATTACKER_GUI:-none}" \
      -e "attacker_password=${ATTACKER_PASSWORD:-redteam}" )
  ok "Configuration complete"
}

if [[ "$MODE" == "configure" ]]; then
  [[ -f "$INVENTORY_FILE" ]] || die "No inventory. Run a full 'make up' first."
  run_ansible
  exit 0
fi

"${SCRIPTS}/preflight.sh"
"${SCRIPTS}/fetch-images.sh"

log "Provisioning ${#LAB_VMS[@]} VMs"
provisioned=""   # lines: short role name port lab_ip
idx=0
for entry in "${LAB_VMS[@]}"; do
  idx=$((idx + 1))
  parse_vm_entry "$entry"
  result="$("${SCRIPTS}/create-vm.sh" "$idx" "$VM_SHORT" "$VM_ROLE" \
    "$VM_CPU" "$VM_RAM" "$VM_DISK" | tail -1)"
  read -r name port lab_ip <<<"$result"
  provisioned+="${VM_SHORT} ${VM_ROLE} ${name} ${port} ${lab_ip}"$'\n'
done

log "Waiting for VMs to accept SSH"
while read -r short role name port lab_ip; do
  [[ -z "$short" ]] && continue
  "${SCRIPTS}/wait-ssh.sh" 127.0.0.1 "$port" 420
done <<<"$provisioned"

printf '%s' "$provisioned" | "${SCRIPTS}/gen-inventory.sh"

if [[ "$MODE" == "provision" ]]; then
  ok "Provisioning done. Run 'make configure' to apply Ansible."
  exit 0
fi

run_ansible

echo
ok "Lab is up. Try: make ssh attacker"
log "Lab network (isolated): attacker 10.10.10.11, targets on 10.10.10.0/24"

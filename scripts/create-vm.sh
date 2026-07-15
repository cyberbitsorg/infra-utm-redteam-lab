#!/usr/bin/env bash
# Create, seed and start one lab VM.
# Usage: create-vm.sh <index> <short-name> <role>
# Index (>=1) drives deterministic MAC addresses, lab IP and host SSH port.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

load_config
idx="${1:?index required}"
short="${2:?short name required}"
role="${3:?role required}"

name="$(vm_name "$short")"
mac_nat="$(printf '52:54:00:AA:00:%02X' "$idx")"
mac_lab="$(printf '52:54:00:10:10:%02X' "$idx")"
lab_ip="10.10.10.$((10 + idx))"
ssh_port="$((2200 + idx))"

# Skip if a VM with this name already exists (idempotent re-runs).
if "$UTMCTL" list 2>/dev/null | grep -q " ${name}$"; then
  warn "VM ${name} already exists, skipping creation"
  echo "${name} ${ssh_port} ${lab_ip}"
  exit 0
fi

log "Preparing disk for ${name}"
mkdir -p "$GEN_DIR"
base_img="$(role_image "$role")"
[[ -f "$base_img" ]] || die "Base image for role '${role}' missing (${base_img}). Run scripts/fetch-images.sh first."
QEMU_IMG="$(find_qemu_img)" || die "qemu-img not found"

# Name the working disk by its actual format so UTM/QEMU never guess wrong
# (Ubuntu ships qcow2-in-.img, Kali ships raw-in-.raw).
img_fmt="$("$QEMU_IMG" info "$base_img" | sed -n 's/^file format: //p' | head -1)"
case "$img_fmt" in
  qcow2) vm_disk="${GEN_DIR}/${name}.qcow2" ;;
  raw)   vm_disk="${GEN_DIR}/${name}.raw" ;;
  *)     vm_disk="${GEN_DIR}/${name}.${base_img##*.}" ;;
esac
# APFS clone (instant, space-free, sparse-preserving) with a plain-copy fallback.
cp -c "$base_img" "$vm_disk" 2>/dev/null || cp "$base_img" "$vm_disk"

# Grow to LAB_DISK_GB, but never shrink (the Kali image already exceeds it).
cur_bytes="$("$QEMU_IMG" info "$vm_disk" | sed -n 's/.*(\([0-9][0-9]*\) bytes).*/\1/p' | head -1)"
target_bytes=$(( LAB_DISK_GB * 1024 * 1024 * 1024 ))
if [[ -n "$cur_bytes" && "$target_bytes" -gt "$cur_bytes" ]]; then
  "$QEMU_IMG" resize "$vm_disk" "${LAB_DISK_GB}G" >/dev/null
fi

log "Building cloud-init seed for ${name}"
seed="$(scripts_dir="$(dirname "${BASH_SOURCE[0]}")"; "${scripts_dir}/make-seed.sh" \
  "$short" "$role" "$mac_nat" "$mac_lab" "$lab_ip" | tail -1)"

log "Creating VM ${name} in UTM (mem ${LAB_RAM}MiB, ${LAB_CPU} cpu, ssh->127.0.0.1:${ssh_port})"
vm_id="$(osascript "$(dirname "${BASH_SOURCE[0]}")/create-vm.applescript" \
  "$name" "$vm_disk" "$seed" "$LAB_RAM" "$LAB_CPU" "$mac_nat" "$mac_lab" "$ssh_port")"
ok "Created ${name} (${vm_id})"

log "Starting ${name}"
"$UTMCTL" start "$name" >/dev/null 2>&1 || osascript -e "tell application \"UTM\" to start virtual machine named \"${name}\""

# Emit a line the orchestrator parses: <name> <ssh_port> <lab_ip>
echo "${name} ${ssh_port} ${lab_ip}"

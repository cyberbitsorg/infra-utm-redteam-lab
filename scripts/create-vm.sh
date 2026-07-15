#!/usr/bin/env bash
# Create, seed and start one lab VM, or bring an existing one in line with the
# roster.
# Usage: create-vm.sh <index> <short-name> <role> <cpu> <ram-mib> <disk-gb>
# Index (>=1) drives deterministic MAC addresses, lab IP and host SSH port.
# Resources come from the caller (scripts/up.sh parses them out of LAB_VMS), so
# this script never reads LAB_CPU/LAB_RAM/LAB_DISK_GB itself.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

load_config
idx="${1:?index required}"
short="${2:?short name required}"
role="${3:?role required}"
cpu="${4:?cpu cores required}"
ram="${5:?ram in MiB required}"
disk_gb="${6:?disk size in GB required}"

name="$(vm_name "$short")"
mac_nat="$(printf '52:54:00:AA:00:%02X' "$idx")"
mac_lab="$(printf '52:54:00:10:10:%02X' "$idx")"
lab_ip="10.10.10.$((10 + idx))"
ssh_port="$((2200 + idx))"

# Bring an existing VM in line with the roster: cpu/ram through UTM, disk
# through qemu-img. Only stops and starts the VM when something really differs,
# so a repeat 'make up' on an unchanged lab restarts nothing.
reconcile_existing_vm() {
  local want_cpu="$1" want_ram="$2" want_disk_gb="$3"
  local cur cur_cpu cur_ram disk candidate cur_bytes want_bytes cur_gb
  local change_hw=0 grow_disk=0 msg

  cur="$(osascript "${REPO_ROOT}/scripts/vm-config.applescript" get "$name" 2>/dev/null || true)"
  read -r cur_cpu cur_ram <<<"$cur"
  if [[ -z "${cur_cpu:-}" || -z "${cur_ram:-}" ]]; then
    warn "${name}: could not read its UTM configuration, leaving it untouched"
    return 0
  fi
  if [[ "$cur_cpu" != "$want_cpu" || "$cur_ram" != "$want_ram" ]]; then
    change_hw=1
  fi

  # The working disk is whichever of the two formats create-vm.sh produced.
  disk=""
  for candidate in "${GEN_DIR}/${name}.qcow2" "${GEN_DIR}/${name}.raw"; do
    if [[ -f "$candidate" ]]; then
      disk="$candidate"
      break
    fi
  done
  if [[ -n "$disk" ]]; then
    cur_bytes="$(disk_bytes "$disk")"
    want_bytes=$(( want_disk_gb * 1024 * 1024 * 1024 ))
    if [[ -n "$cur_bytes" ]]; then
      cur_gb=$(( cur_bytes / 1024 / 1024 / 1024 ))
      if [[ "$want_bytes" -gt "$cur_bytes" ]]; then
        grow_disk=1
      elif [[ "$want_bytes" -lt "$cur_bytes" ]]; then
        warn "${name}: disk=${want_disk_gb} is below the current ${cur_gb}G. Disks are never shrunk, leaving it as is."
      fi
    fi
  fi

  if [[ "$change_hw" -eq 0 && "$grow_disk" -eq 0 ]]; then
    ok "${name} unchanged (${cur_cpu} cpu, ${cur_ram} MiB)"
    return 0
  fi

  msg="${name}: ${cur_cpu}->${want_cpu} cpu, ${cur_ram}->${want_ram} MiB"
  if [[ "$grow_disk" -eq 1 ]]; then
    msg="${msg}, disk ${cur_gb}G->${want_disk_gb}G"
  fi
  log "${msg}, restarting"

  if ! stop_vm_and_wait "$name"; then
    warn "${name}: did not stop within 60s, leaving it untouched"
    return 0
  fi
  if [[ "$change_hw" -eq 1 ]]; then
    osascript "${REPO_ROOT}/scripts/vm-config.applescript" set "$name" "$want_cpu" "$want_ram" >/dev/null
  fi
  if [[ "$grow_disk" -eq 1 ]]; then
    QEMU_IMG="$(find_qemu_img)" || die "qemu-img not found"
    "$QEMU_IMG" resize "$disk" "${want_disk_gb}G" >/dev/null
  fi
  "$UTMCTL" start "$name" >/dev/null 2>&1 \
    || osascript -e "tell application \"UTM\" to start virtual machine named \"${name}\""
  ok "${name} updated. cloud-init grows the root filesystem on this boot."
}

# An existing VM is reconciled, not recreated.
if vm_exists "$name"; then
  reconcile_existing_vm "$cpu" "$ram" "$disk_gb"
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

# Grow to the requested size, but never shrink (the Kali image already exceeds
# the usual default).
cur_bytes="$(disk_bytes "$vm_disk")"
target_bytes=$(( disk_gb * 1024 * 1024 * 1024 ))
if [[ -n "$cur_bytes" && "$target_bytes" -gt "$cur_bytes" ]]; then
  "$QEMU_IMG" resize "$vm_disk" "${disk_gb}G" >/dev/null
fi

log "Building cloud-init seed for ${name}"
seed="$(scripts_dir="$(dirname "${BASH_SOURCE[0]}")"; "${scripts_dir}/make-seed.sh" \
  "$short" "$role" "$mac_nat" "$mac_lab" "$lab_ip" | tail -1)"

log "Creating VM ${name} in UTM (mem ${ram}MiB, ${cpu} cpu, disk ${disk_gb}G, ssh->127.0.0.1:${ssh_port})"
vm_id="$(osascript "$(dirname "${BASH_SOURCE[0]}")/create-vm.applescript" \
  "$name" "$vm_disk" "$seed" "$ram" "$cpu" "$mac_nat" "$mac_lab" "$ssh_port")"
ok "Created ${name} (${vm_id})"

log "Starting ${name}"
"$UTMCTL" start "$name" >/dev/null 2>&1 || osascript -e "tell application \"UTM\" to start virtual machine named \"${name}\""

# Emit a line the orchestrator parses: <name> <ssh_port> <lab_ip>
echo "${name} ${ssh_port} ${lab_ip}"

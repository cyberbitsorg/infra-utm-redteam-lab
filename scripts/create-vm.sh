#!/usr/bin/env bash
# Create, seed and start one lab VM, or reconcile an existing one.
# Usage: create-vm.sh <index> <short-name> <role> <cpu> <ram-mib> <disk-gb>
# Index (>=1) fixes MACs, lab IP and SSH port; up.sh passes the parsed
# LAB_VMS resources.
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

# Reconcile cpu/ram through UTM; disk is compare-and-report only (see below).
# Restarts the VM only when cpu/ram really differ.
reconcile_existing_vm() {
  local want_cpu="$1" want_ram="$2" want_disk_gb="$3"
  local cur cur_cpu cur_ram disk candidate cur_bytes want_bytes cur_gb
  local change_hw=0

  cur="$(osascript "${REPO_ROOT}/scripts/vm-config.applescript" get "$name" 2>/dev/null || true)"
  read -r cur_cpu cur_ram <<<"$cur"
  if [[ -z "${cur_cpu:-}" || -z "${cur_ram:-}" ]]; then
    warn "${name}: could not read its UTM configuration, leaving it untouched"
    return 0
  fi
  if [[ "$cur_cpu" != "$want_cpu" || "$cur_ram" != "$want_ram" ]]; then
    change_hw=1
  fi

  # Compare-and-report only: once UTM imported this staging file at creation,
  # it is not the VM's live disk; resizing here would change nothing the VM
  # uses. So the disk never drives the restart decision.
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
        warn "${name}: disk=${want_disk_gb}G is larger than the ${cur_gb}G it was created with. A disk cannot be grown on a VM that already exists in UTM; run 'make destroy' then 'make up' to rebuild it at the new size."
      elif [[ "$want_bytes" -lt "$cur_bytes" ]]; then
        warn "${name}: disk=${want_disk_gb}G is below the current ${cur_gb}G. Disks are never shrunk, leaving it as is."
      fi
    else
      warn "${name}: could not check its disk size (qemu-img could not read ${disk})"
    fi
  else
    warn "${name}: could not check its disk size (no staging file in ${GEN_DIR}, was generated/ cleared after this VM was created?)"
  fi

  # No hardware change, but a stopped VM (reboot, 'make down') must still be
  # started or up.sh would wait on SSH forever. Starting a running VM is a
  # no-op.
  if [[ "$change_hw" -eq 0 ]]; then
    if [[ "$(vm_status "$name")" == "started" ]]; then
      ok "${name} unchanged (${cur_cpu} cpu, ${cur_ram} MiB)"
    else
      log "${name}: unchanged but not running, starting it"
      start_vm "$name"
      ok "${name} started (${cur_cpu} cpu, ${cur_ram} MiB)"
    fi
    return 0
  fi

  log "${name}: ${cur_cpu}->${want_cpu} cpu, ${cur_ram}->${want_ram} MiB, restarting"

  if ! stop_vm_and_wait "$name"; then
    warn "${name}: did not stop within 60s, leaving it untouched"
    return 0
  fi
  osascript "${REPO_ROOT}/scripts/vm-config.applescript" set "$name" "$want_cpu" "$want_ram" >/dev/null
  start_vm "$name"
  ok "${name} updated: cpu and/or ram applied."
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

# Name the disk by its real format so UTM/QEMU never guess (Ubuntu: qcow2
# in .img, Kali: raw).
img_fmt="$("$QEMU_IMG" info "$base_img" | sed -n 's/^file format: //p' | head -1)"
case "$img_fmt" in
  qcow2) vm_disk="${GEN_DIR}/${name}.qcow2" ;;
  raw)   vm_disk="${GEN_DIR}/${name}.raw" ;;
  *)     vm_disk="${GEN_DIR}/${name}.${base_img##*.}" ;;
esac
# APFS clone (instant, sparse-preserving) with plain-copy fallback. Staging
# input only: UTM imports and converts it into its own bundle at creation and
# never reads generated/ again, so any resize must happen here, before
# creation.
cp -c "$base_img" "$vm_disk" 2>/dev/null || cp "$base_img" "$vm_disk"

# Grow to the requested size, never shrink (Kali already exceeds the default).
# Runs before creation so the size lands in the VM UTM builds.
cur_bytes="$(disk_bytes "$vm_disk")"
target_bytes=$(( disk_gb * 1024 * 1024 * 1024 ))
if [[ -n "$cur_bytes" && "$target_bytes" -gt "$cur_bytes" ]]; then
  # Explicit format avoids qemu-img's raw-probe warning on every run.
  "$QEMU_IMG" resize -f "$img_fmt" "$vm_disk" "${disk_gb}G" >/dev/null
fi

log "Building cloud-init seed for ${name}"
seed="$(scripts_dir="$(dirname "${BASH_SOURCE[0]}")"; "${scripts_dir}/make-seed.sh" \
  "$short" "$role" "$mac_nat" "$mac_lab" "$lab_ip" | tail -1)"

log "Creating VM ${name} in UTM (mem ${ram}MiB, ${cpu} cpu, disk ${disk_gb}G, ssh->127.0.0.1:${ssh_port})"
vm_id="$(osascript "$(dirname "${BASH_SOURCE[0]}")/create-vm.applescript" \
  "$name" "$vm_disk" "$seed" "$ram" "$cpu" "$mac_nat" "$mac_lab" "$ssh_port")"
ok "Created ${name} (${vm_id})"

log "Starting ${name}"
start_vm "$name"

# Emit a line the orchestrator parses: <name> <ssh_port> <lab_ip>
echo "${name} ${ssh_port} ${lab_ip}"

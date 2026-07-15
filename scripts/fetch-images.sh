#!/usr/bin/env bash
# Download the base images (Ubuntu for targets, Kali for the attacker) and verify
# their SHA256 checksums. Idempotent: skips work when a verified copy exists.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

load_config
mkdir -p "$IMAGES_DIR"

# Verify <file> against a <sums_file> line matching <basename>. Handles the
# optional "*" binary marker in checksum files.
verify_file() {
  local file=$1 sums=$2 base=$3 expected actual
  [[ -f "$file" && -f "$sums" ]] || return 1
  expected="$(grep " \*\?${base}\$" "$sums" | awk '{print $1}' | head -1)"
  [[ -n "$expected" ]] || return 1
  actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  [[ "$expected" == "$actual" ]]
}

fetch_ubuntu() {
  local img sums base
  img="${IMAGES_DIR}/$(basename "$UBUNTU_IMG_URL")"
  sums="${IMAGES_DIR}/SHA256SUMS"
  base="$(basename "$UBUNTU_IMG_URL")"
  if verify_file "$img" "$sums" "$base"; then
    ok "Ubuntu image present and verified: ${img}"
    return
  fi
  log "Downloading Ubuntu checksums"
  curl -fSL --retry 3 -o "$sums" "$UBUNTU_SHA_URL"
  log "Downloading Ubuntu image (this can take a few minutes)"
  curl -fSL --retry 3 -o "$img" "$UBUNTU_IMG_URL"
  verify_file "$img" "$sums" "$base" || die "Checksum mismatch for ${base}. Delete images/ and retry."
  ok "Ubuntu image verified: ${img}"
}

fetch_kali() {
  local out archive sums base
  out="${IMAGES_DIR}/${KALI_IMG_FILE}"
  if [[ -f "$out" ]]; then
    ok "Kali image present: ${out}"
    return
  fi
  archive="${IMAGES_DIR}/$(basename "$KALI_IMG_URL")"
  sums="${IMAGES_DIR}/kali-SHA256SUMS"
  base="$(basename "$KALI_IMG_URL")"
  if ! verify_file "$archive" "$sums" "$base"; then
    log "Downloading Kali checksums"
    curl -fSL --retry 3 -o "$sums" "$KALI_SHA_URL"
    log "Downloading Kali image (large, this can take a while)"
    curl -fSL --retry 3 -o "$archive" "$KALI_IMG_URL"
    verify_file "$archive" "$sums" "$base" || die "Checksum mismatch for ${base}. Delete images/ and retry."
  fi
  log "Extracting Kali image"
  tar -xf "$archive" -C "$IMAGES_DIR"
  [[ -f "${IMAGES_DIR}/disk.raw" ]] || die "Kali archive did not contain the expected disk.raw"
  mv -f "${IMAGES_DIR}/disk.raw" "$out"
  rm -f "$archive"
  ok "Kali image ready: ${out}"
}

fetch_ubuntu
fetch_kali

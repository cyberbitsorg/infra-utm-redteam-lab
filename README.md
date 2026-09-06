# UTM red team lab

Automated, reproducible red team lab of VMs on UTM for Apple Silicon. One command builds a Kali attacker and a set of vulnerable targets on an isolated network.

ARM64 cloud images run natively (M1 through M5). UTM's AppleScript interface provisions the VMs, cloud-init handles first boot, Ansible does all configuration.

## Architecture

| Phase | Tool | What it sets up | When it runs |
|-------|------|-----------------|--------------|
| Provisioning | UTM AppleScript (`scripts/`) | Creates each VM from a verified ARM64 image, two NICs | `make up` |
| Bootstrap | Cloud-init | Lab user, SSH key, Python, lab IP | First boot only |
| Configuration | Ansible | Kali toolset, vulnerable targets, hosts wiring | Automatic after boot |
| Extension | You | More targets (see `docs/extending.md`) | On demand |

All VMs share an isolated `10.10.10.0/24` segment (a shared vmnet-host switch). The Mac reaches each VM over an SSH port forward, so no guest IP discovery is needed. See `docs/network.md`.

## Requirements

- Apple Silicon Mac with internet access
- Xcode Command Line Tools (`xcode-select --install`), [Homebrew](https://brew.sh/)
- [UTM](https://mac.getutm.app/) (`brew install --cask utm`; `utmctl` is called from the app bundle, no PATH setup needed)
- `qemu` (`brew install qemu`) and `xorriso` (`brew install xorriso`; macOS `hdiutil` works too)
- `ansible` (`brew install ansible`)
- Disk: ~20 GB for the `curated` build (the Kali attacker is ~7 GB); `ATTACKER_TOOLSET=large` needs 40 GB+

`make preflight` checks the tools and generates an SSH key if needed. On the first run macOS asks permission for your terminal to control UTM (Automation prompt); approve it.

## Quick start

### 1. Configure

```bash
cp lab.conf.example lab.conf
```

The defaults define a Kali `attacker` (on) plus five targets (Juice Shop, weak services, WebGoat plus crAPI, k3s, MQTT), all off: a `make up` boots only the attacker, and you flip targets on as you need them.

Each fleet entry is `"name:role [cpu=N] [ram=MiB] [disk=GB] state=on|off"`. The `state=` field is required on every entry; the toggle is always explicit. The resource fields are optional and fall back to `LAB_CPU`, `LAB_RAM` and `LAB_DISK_GB`:

```bash
LAB_VMS=(
  "attacker:attacker cpu=4 ram=4096 disk=60 state=on"
  "vuln-web:vuln-web state=off"
  "vuln-net:vuln-net state=off"
  "vuln-docker:vuln-docker ram=4096 state=off"
  "vuln-k8s:vuln-k8s ram=4096 state=off"
  "vuln-iot:vuln-iot state=off"
)
```

`state=off` pauses a VM without losing its slot: `make up` skips it (and stops it if running), Ansible ignores it, but its lab IP and SSH port stay reserved so the other VMs never shift address. `make status` shows it as `(off)`. Targets default to off to keep RAM/CPU free; flip one to `state=on` and run `make up` when you want to attack it.

### 1. Build the lab

```bash
make up
```

Preflight, image download and verification, VM creation, wait for SSH, Ansible. First run takes several minutes.

### 2. Use it

```bash
make ssh attacker
```

From the attacker, all enabled targets are reachable:

```bash
nmap 10.10.10.12 10.10.10.13 10.10.10.14 10.10.10.15 10.10.10.16
curl http://10.10.10.12          # vuln-web: OWASP Juice Shop
curl http://10.10.10.14:8080     # vuln-docker: WebGoat (WebWolf on :9090)
curl http://10.10.10.14:8888     # vuln-docker: crAPI (MailHog on :8025)
# vuln-net (10.10.10.13): weak SSH/FTP/Samba, leaked keys and sudo privesc
# vuln-k8s (10.10.10.15): k3s API on :6443, kubelet on :10250
# vuln-iot (10.10.10.16): anonymous MQTT broker on :1883
```

`docs/attacking.md` is the operator's guide per target.

### 3. Tear down

```bash
make down       # stop the VMs (and close their console windows), keep them
make destroy    # delete the VMs and generated artifacts
```

Window closing uses UTM's own AppleScript interface; no macOS permissions needed, and the window of a running VM is never touched.

## What you get

- attacker: Kali ARM64, selectable toolset (`ATTACKER_TOOLSET`: `curated` subset with nmap, hydra, sqlmap, ffuf, gobuster, metasploit, SecLists; or `kali-linux-headless` / `kali-linux-large`), `/etc/hosts` prefilled with the lab targets
- vuln-web: OWASP Juice Shop
- vuln-net: weak SSH, FTP and Samba for enumeration and credential attacks, plus privesc breadcrumbs: a leaked SSH key, sudo on a GTFOBins binary, and a plaintext secret in the web root
- vuln-docker: Docker host running WebGoat (guided lessons, WebWolf on 9090) and [crAPI](https://owasp.org/www-project-crapi/) (OWASP API Top 10, MailHog on 8025)
- vuln-k8s: single-node [k3s](https://k3s.io) with a world-readable kubeconfig, a plaintext cluster secret and a privileged hostPath pod
- vuln-iot: anonymous Mosquitto MQTT with simulated devices: a gateway that leaks admin credentials in a status topic, and a smart lock that obeys any command topic message and logs it world-readably

## Making changes

Change the fleet in `lab.conf`, adjust Ansible (`ansible/roles/`, `ansible/playbook.yaml`, `ansible/group_vars/`), re-run `make up`. Ansible is idempotent: existing VMs are updated, never rebuilt.

- `ATTACKER_TOOLSET` picks the toolset; `ATTACKER_GUI=xfce` adds a desktop (turning it back to `none` does not uninstall it; `make destroy` + `make up` for a clean headless box)
- `ATTACKER_PASSWORD` (default `redteam`) sets the console/GUI password; the role removes Kali's auto-login. SSH stays key-only
- `cpu=`/`ram=` changes reconcile on the next `make up` (that VM stops, changes, restarts). `disk=` applies only at creation: UTM imports the disk into its own bundle, so growing an existing VM's disk needs `make destroy` + `make up`. Disks are never shrunk

## Directory layout

Both gitignored, with deliberately opposite lifecycles:

| Directory | Holds | Lifecycle |
|-----------|-------|-----------|
| `images/` | ARM64 base images + `SHA256SUMS` | Reused read-only by every build. Not touched by `make destroy` (multi-GB downloads); delete by hand to force a re-fetch |
| `generated/` | Per-VM staging disks and seed ISOs | Rebuilt every `make up`, wiped by `make destroy`. Throwaway: UTM imports each disk at creation and never reads `generated/` again |

Other gitignored files: `lab.conf` and `ansible/inventory/hosts.generated.yaml` (written by `scripts/gen-inventory.sh`).

## Useful commands

```bash
make help        # list all targets
make preflight   # check tools, generate lab SSH key
make up          # full hands-off build
make provision   # create and boot VMs only, no Ansible
make configure   # run Ansible against running VMs
make status      # VM status (state=off VMs marked "(off)")
make ssh VM=...  # SSH into a VM by short name
make test        # run the shell unit tests
make lint        # syntax-check scripts and Ansible
make down        # stop VMs (and close their console windows)
make destroy     # delete VMs and artifacts
```

## Safety

This project builds intentionally vulnerable machines. The lab segment has no route to your home network; keep it that way and never move a vulnerable VM to bridged networking on an untrusted LAN. The NAT interface only serves first-boot package installs; `docs/network.md` explains removing it for a fully offline target. Authorised, educational use on machines you own only.

## Validate on first run

Two things depend on your UTM version: VM creation in `scripts/create-vm.applescript` (if a property is rejected, adjust it there) and guest-to-guest reachability (see the check in `docs/network.md`).

## License

GNU General Public License v3.0. See [LICENSE](LICENSE).

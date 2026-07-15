# UTM red team lab

Hands-off, reproducible red team lab of virtual machines on UTM for Apple Silicon. One command builds an attacker box and a vulnerable target on an isolated network, ready to attack. Built to be shared and extended.

The lab uses ARM64 cloud images, so it runs natively on Apple Silicon (M1 through M5). Provisioning is driven by UTM's AppleScript interface, first-boot setup by cloud-init, and all configuration by Ansible.

## Deployment architecture

This project splits deployment into four phases, mirroring the pattern used across these infra repos (infrastructure, then bootstrap, then configuration).

| Phase | Tool | What it sets up | When it runs |
|-------|------|-----------------|--------------|
| Provisioning | UTM AppleScript (`scripts/`) | Creates each VM from a verified ARM64 cloud image, two NICs, boots it | `make up` |
| Bootstrap | Cloud-init | Creates the lab user, injects the SSH key, installs Python, sets the lab IP | First boot only |
| Configuration | Ansible | Installs the Kali toolset and the vulnerable targets, wires up hosts | Automatic after boot |
| Extension | You | Add more targets, or a Windows AD phase (see `docs/extending.md`) | On demand |

The attacker and targets share an isolated `10.10.10.0/24` segment (a shared Apple vmnet-host switch, so guests reach each other out of the box). The macOS host reaches each VM over an SSH port forward, so no guest IP discovery is needed. See `docs/network.md` for the full picture.

## Requirements

- Apple Silicon Mac (ARM64)
- [UTM](https://mac.getutm.app/) with `utmctl` available (ships inside UTM.app)
- `qemu` for `qemu-img`: `brew install qemu`
- An ISO builder for cloud-init seeds: `xorriso` (`brew install xorriso`) or the built-in macOS `hdiutil` (used automatically if `xorriso` is absent)
- `ansible`: `brew install ansible`
- Free disk space: roughly **~20 GB** for the default (`curated`) build — the Kali attacker (with two kernels + toolset) is the bulk at ~7 GB, the two targets ~2.5 GB each, plus the base images. Choosing `ATTACKER_TOOLSET=large` needs considerably more (plan for 40 GB+).

`make preflight` checks the tools and generates an SSH key if you do not have one.

## Quick start

### 1. Configure

```bash
cp lab.conf.example lab.conf
```

The defaults build a Kali `attacker`, a `vuln-web` target (Juice Shop) and a `vuln-net` target (weak services). Edit `lab.conf` for different names, sizes, an extra VM, or the attacker toolset (`ATTACKER_TOOLSET`: `curated` / `headless` / `large`).

### 2. Build the lab

```bash
make up
```

This runs preflight, downloads and verifies the ARM64 cloud images (Ubuntu for the targets, Kali for the attacker), creates and boots the VMs, waits for SSH, then applies Ansible. First run downloads images and installs packages (the Kali toolset can be large), so allow several minutes.

### 3. Use it

```bash
make ssh VM=attacker
```

From the attacker box, both targets are reachable on the lab network:

```bash
nmap 10.10.10.12 10.10.10.13     # both targets
curl http://10.10.10.12          # vuln-web: OWASP Juice Shop
# vuln-net (10.10.10.13): weak SSH/FTP/Samba services to enumerate and attack
```

`docs/attacking.md` is a short operator's guide — where to start on each target,
with concrete commands for recon, Juice Shop, and the weak-services box.

### 4. Tear down

```bash
make down       # stop the VMs, keep them
make destroy    # delete the VMs and generated artifacts
```

## What you get

- attacker: Kali Linux ARM64 with a selectable toolset (`ATTACKER_TOOLSET`: a `curated` subset by default — nmap, hydra, sqlmap, ffuf, gobuster, metasploit, SecLists — or the full `kali-linux-headless` / `kali-linux-large` metapackages), and `/etc/hosts` prefilled with the lab targets
- vuln-web: OWASP Juice Shop, an intentionally vulnerable web app, served on the lab network
- vuln-net: a services box with deliberately weak SSH, FTP (vsftpd), and Samba for enumeration and credential attacks

The toolset and targets are starting points. `docs/extending.md` shows how to add VMs and how to grow into a Windows Active Directory (AD) phase.

## Making changes

Change the roster in `lab.conf`, then adjust Ansible:

- pick the attacker toolset with `ATTACKER_TOOLSET` in `lab.conf`, or edit the package sets in `ansible/group_vars/attacker.yaml`
- change the web target in `ansible/group_vars/vuln-web.yaml`, or the weak services in `ansible/group_vars/vuln-net.yaml`
- add a new role under `ansible/roles/` and a play in `ansible/playbook.yaml`

Re-run `make up` to apply. Ansible is idempotent, so existing VMs are only updated, never rebuilt.

## Useful commands

```bash
make help        # list all targets
make up          # full hands-off build
make provision   # create and boot VMs only, no Ansible
make configure   # run Ansible against running VMs
make status      # show VM status
make ssh VM=...  # SSH into a VM by short name
make lint        # syntax-check scripts and Ansible
make down        # stop VMs
make destroy     # delete VMs and artifacts
```

## Safety

This project builds intentionally vulnerable machines. Treat it accordingly.

- The lab segment (`10.10.10.0/24`) has no route to your home network. Keep it that way, and never move a vulnerable VM to bridged networking on an untrusted LAN
- The NAT interface exists only so first-boot can install packages. `docs/network.md` explains how to remove it for a fully offline target
- This lab is for authorised, educational use on machines you own. Do not point these tools at systems you do not have permission to test

### About Windows images

This repo ships no Microsoft images. If you add a Windows or Windows Server phase, you build the ISO yourself and use evaluation licensing. See `docs/extending.md`.

## Validate on first run

Because the provisioning layer talks to UTM's AppleScript interface, a couple of things depend on your exact UTM version and are worth confirming on the first build:

- VM creation in `scripts/create-vm.applescript`, which follows the UTM scripting dictionary. If a property is rejected, adjust it there
- guest-to-guest reachability on the lab segment. The lab NIC uses UTM "host" mode (a shared Apple vmnet switch) so guests reach each other by default; `docs/network.md` shows the check

## License

GNU General Public License v3.0. See [LICENSE](LICENSE) for details.

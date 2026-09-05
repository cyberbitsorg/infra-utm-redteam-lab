# Extending the lab

The lab is designed to grow. Two common directions:

## Add another Linux VM

1. Add a line to `LAB_VMS` in `lab.conf`, for example
   `"vuln-ssh:vuln-ssh state=on"`. `state=` is required on every entry
   (`on` or `off`); to give the VM more than the `LAB_CPU` / `LAB_RAM` /
   `LAB_DISK_GB` defaults, add any of `cpu=`, `ram=` (MiB) or `disk=` (GB):
   `"vuln-ssh:vuln-ssh cpu=4 ram=4096 disk=40 state=on"`. Append new VMs at
   the end: the position of an entry fixes its SSH port and lab IP, so
   inserting one in the middle shifts the addresses of every VM below it.
   `state=off` pauses a VM (skipped by `make up`, stopped if running,
   invisible to Ansible) while keeping its slot — see `lab.conf.example` for
   the details.
2. Create an Ansible role at `ansible/roles/vuln-ssh/tasks/main.yaml`
3. Add a play for it in `ansible/playbook.yaml`. `gen-inventory.sh` names each
   group `role_<role>`, mapping hyphens to underscores, so target
   `hosts: role_vuln_ssh` (not `vuln-ssh`) — the same way the existing plays use
   `role_vuln_web` and `role_vuln_net`
4. Optionally add `ansible/group_vars/role_vuln_ssh.yaml` for its variables. The
   filename must match that group name, like the other `role_*.yaml` files
5. Run `make up` again. The new VM is created and configured. Existing VMs are
   reconciled against the fleet: a changed `cpu=` or `ram=` stops that VM,
   applies it, and starts it again, but a changed `disk=` is not applied to a
   VM that already exists (see "Making changes" in the README)

The index of a VM is its position in `LAB_VMS`, which fixes its SSH port
(`2200 + index`) and lab IP (`10.10.10.{10 + index}`). Existing examples to
copy from: `vuln-docker` (a Docker host running containers) and `vuln-k8s`
(single-node k3s with deliberately weak cluster configuration).

## Phase 2: add a Windows Active Directory target

This is the natural next step for red team practice. Windows cannot use
cloud-init, so it sits outside the hands-off pipeline and is provisioned once,
semi-manually.

1. Build a Windows Server 2025 ARM64 ISO with UUP Dump (needs a Windows host to
   run the conversion), then copy it to the Mac. Windows Server 2025 ARM is a
   preview build, so treat it as lab-only
2. Create the VM in UTM, install Windows, promote it to a Domain Controller
   (AD DS role), and put its lab NIC on `10.10.10.0/24`
3. Add a Windows 11 ARM client and join it to the domain
4. Automate the inside-Windows configuration with Ansible over WinRM: add the
   hosts to a `windows` group with `ansible_connection: winrm` and write roles
   for users, groups, shares, and deliberately weak configurations

A fully Linux-native alternative is a Samba-based AD Domain Controller, which
stays inside the hands-off pipeline but is less faithful to a real Windows
environment. Pick based on whether you want realism or full automation.

## Phase 3: add detection (purple team)

Add a monitoring VM running Wazuh or an ELK stack, install agents (Sysmon on
Windows, auditd/Wazuh agent on Linux) via Ansible, and you can watch your own
attacks generate detections.

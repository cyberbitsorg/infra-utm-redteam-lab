# Extending the lab

The lab is designed to grow. Two common directions:

## Add another Linux VM

1. Add a line to `LAB_VMS` in `lab.conf`, for example `"vuln-ssh:vuln-ssh"`.
   To give it more than the `LAB_CPU` / `LAB_RAM` / `LAB_DISK_GB` defaults, add
   any of `cpu=`, `ram=` (MiB) or `disk=` (GB):
   `"vuln-ssh:vuln-ssh cpu=4 ram=4096 disk=40"`
2. Create an Ansible role at `ansible/roles/vuln-ssh/tasks/main.yaml`
3. Add a play for it in `ansible/playbook.yaml` targeting the `vuln-ssh` group
4. Optionally add `ansible/group_vars/vuln-ssh.yaml` for its variables
5. Run `make up` again. Existing VMs are left untouched; only the new one is
   created and configured

The index of a VM is its position in `LAB_VMS`, which fixes its SSH port
(`2200 + index`) and lab IP (`10.10.10.{10 + index}`).

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

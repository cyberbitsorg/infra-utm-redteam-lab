# Extending the lab

Adding a Linux VM takes four steps:

1. Append a line to `LAB_VMS` in `lab.conf`, for example
   `"vuln-ssh:vuln-ssh state=on"`. `state=` is required on every entry
   (`on` or `off`); to give the VM more than the `LAB_CPU` / `LAB_RAM` /
   `LAB_DISK_GB` defaults, add any of `cpu=`, `ram=` (MiB) or `disk=` (GB):
   `"vuln-ssh:vuln-ssh cpu=4 ram=4096 disk=40 state=on"`.
2. Create an Ansible role at `ansible/roles/vuln-ssh/tasks/main.yaml`.
3. Add a play in `ansible/playbook.yaml` targeting `hosts: role_vuln_ssh`
   (hyphens become underscores, like the existing `role_vuln_web` plays).
4. Optionally add `ansible/group_vars/role_vuln_ssh.yaml` for its variables.

Then run `make up`. Existing VMs are reconciled: a changed `cpu=` or `ram=`
stops that VM, applies it and starts it again; a changed `disk=` is not applied
to an existing VM.

The index of a VM is its position in `LAB_VMS`, which fixes its SSH port
(`2200 + index`) and lab IP (`10.10.10.{10 + index}`). Always append: inserting
a line in the middle shifts the addresses of every VM below it.

Good examples to copy from: `vuln-docker` (Docker containers plus a Compose
stack), `vuln-k8s` (k3s with weak cluster config) and `vuln-iot` (an MQTT
broker with simulated devices).

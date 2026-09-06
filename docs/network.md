# Lab network

Every VM gets two NICs, created by `scripts/create-vm.applescript`.

NAT interface: UTM "emulated" mode (QEMU user/SLIRP)

- Internet for package installs, plus a host-to-guest SSH forward on `127.0.0.1` (`2200 + index`: attacker 2201, vuln-web 2202, and so on). Ansible and `make ssh` use these, so no guest IP discovery is needed
- Must be "emulated": only QEMU `user` networking honours `hostfwd`; UTM "shared" silently drops port forwards
- SLIRP proxies through the host's network stack, so this NIC reaches anything the host can route to, including your real LAN. Only the lab segment below is isolated

Lab interface: UTM "host" mode (Apple vmnet-host)

- The isolated segment where the exercise happens. Static `10.10.10.0/24` addresses assigned by cloud-init, matched by MAC: attacker `.11`, vuln-web `.12`, vuln-net `.13`, vuln-docker `.14`, vuln-k8s `.15`, vuln-iot `.16` (`10 + index`)
- All lab NICs share ONE vmnet-host L2 switch, so guests reach each other out of the box. Two "emulated" NICs would not bridge: each is its own private SLIRP net
- Host-only with no gateway: no route to the internet or your home network

```
        macOS host (Apple Silicon)
        | ssh 127.0.0.1:2201   | ssh :2202   | ssh :2203 ..
        v                      v             v
   +-----------+          +-----------+   +-----------+
   | attacker  |          | vuln-web  |   | vuln-*    |
   | (Kali)    | internet | juice-shop|   | targets   |
   | nat: dhcp |<---       | nat: dhcp |   | nat: dhcp |
   | lab: .11  |          | lab: .12  |   | lab: .13+ |
   +-----+-----+          +-----+-----+   +-----+-----+
         |                      |               |
         +===== 10.10.10.0/24 (vmnet-host, isolated) =====+
```

## Verifying guest-to-guest reachability

```bash
make ssh attacker
ping 10.10.10.12            # vuln-web
ping 10.10.10.{13..16}     # the other targets
```

All should answer (VMs with `state=off` will not, which is expected). If not, confirm each VM's lab NIC is UTM "host" mode, not "emulated".

## Hardening to fully offline

For a target you do not trust, remove the NAT interface once packages are installed: stop the VM, delete the "emulated" NIC in UTM settings. `make ssh` then no longer works; use UTM's console.

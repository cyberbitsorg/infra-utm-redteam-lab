# Lab network

Every VM gets two network interfaces, created by `scripts/create-vm.applescript`.

NAT interface: UTM "emulated" mode (QEMU user/SLIRP)

- Purpose: internet access for package installs, and host-to-guest SSH
- The host reaches each guest through a port forward on `127.0.0.1`: attacker on
  port 2201, vuln-web on 2202, vuln-net on 2203, and so on (`2200 + index`)
- Ansible and `make ssh` use these forwards, so no guest IP discovery is needed
- Must be "emulated": that maps to QEMU `user` networking, the only backend that
  honours the `hostfwd` port forward. UTM "shared" (vmnet-shared) gives internet
  but silently drops port forwards, so SSH-over-forward would never come up

Lab interface: UTM "host" mode (Apple vmnet-host)

- Purpose: the isolated segment where the exercise happens
- Static addresses on `10.10.10.0/24`, assigned by cloud-init and matched by MAC:
  attacker `10.10.10.11`, vuln-web `10.10.10.12`, vuln-net `10.10.10.13`
  (`10 + index`)
- All lab VMs in "host" mode share ONE Apple vmnet L2 switch, so they reach each
  other on `10.10.10.0/24` out of the box. (Two "emulated" NICs would NOT bridge:
  each is its own private SLIRP net, so guest-to-guest traffic never flows.)
- "host" mode is host-only with no gateway, so the segment has no route to the
  internet or your home network, so it stays isolated

```
        macOS host (Apple Silicon)
        | ssh 127.0.0.1:2201   | ssh :2202          | ssh :2203
        v                      v                    v
   +-----------+          +-----------+        +-----------+
   | attacker  |          | vuln-web  |        | vuln-net  |
   | (Kali)    | internet | juice-shop|        | services  |
   | nat: dhcp |<---       | nat: dhcp |        | nat: dhcp |
   | lab: .11  |          | lab: .12  |        | lab: .13  |
   +-----+-----+          +-----+-----+        +-----+-----+
         |                      |                    |
         +===== 10.10.10.0/24 (vmnet-host, isolated) =====+
```

## Verifying guest-to-guest reachability

After `make up`, the attacker should reach the targets on the lab net:

```bash
make ssh attacker
ping 10.10.10.12   # vuln-web (Juice Shop)
ping 10.10.10.13   # vuln-net (services)
```

Both should answer. If they do not, confirm each VM's lab NIC is UTM "host" mode
(the shared Apple vmnet switch) rather than "emulated" (per-VM isolated SLIRP).

## Hardening to fully offline

For a target you do not trust, remove the NAT interface after provisioning so the
VM has no internet at all. Do this once packages are installed: stop the VM, delete
the "emulated" NAT interface in UTM settings, and rely only on the lab interface.
`make ssh` then no longer works; use UTM's console instead.

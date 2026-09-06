# Attacking the lab

Operator's guide per target: how to get on the box, what tooling is available, and what to reach for. No solutions here; `docs/walkthrough.md` holds the full spoilers per target (start there only when stuck). Everything is for your own lab: intentionally vulnerable machines, isolated on `10.10.10.0/24`. Targets default to `state=off` in `lab.conf`; set `state=on` and run `make up` first.

| Host | Lab IP | What it is |
|------|--------|------------|
| `attacker` | `10.10.10.11` | Kali, where you work |
| `vuln-web` | `10.10.10.12` | OWASP Juice Shop |
| `vuln-net` | `10.10.10.13` | Weak SSH / FTP / Samba + privesc breadcrumbs |
| `vuln-docker` | `10.10.10.14` | WebGoat + WebWolf, crAPI + MailHog |
| `vuln-k8s` | `10.10.10.15` | k3s with weak cluster config |
| `vuln-iot` | `10.10.10.16` | Anonymous MQTT broker + simulated devices |

```bash
make ssh attacker             # from the repo on your Mac
```

Targets are already in `/etc/hosts` (`redteam-vuln-web`, etc.), SecLists is at `/usr/share/seclists`. For a GUI (Burp, browser), open the `redteam-attacker` console in UTM; everything below also works over SSH.

## Recon first

```bash
nmap -sn 10.10.10.0/24                                     # what's alive
nmap -sV -sC -p- 10.10.10.{12..16}                         # full scan
```

Expect `80/http` on `.12`; `21/ftp 22/ssh 80/http 445/microsoft-ds` on `.13`; `8080 8888 9090/http` and `8025` (MailHog) on `.14`; `6443/https` and `10250/https` (kubelet) on `.15`; `1883/mqtt` on `.16`.

## vuln-web: Juice Shop (10.10.10.12)

Deliberately broken shop with a built-in scoreboard. Work it like a real black-box web app: `whatweb`, `curl -I`, `ffuf` with the SecLists `common.txt` wordlist, then dig into the API, the client-side code and anything the UI forgot to link. The scoreboard tracks your progress; chase it.

The [companion guide](https://pwning.owasp-juice.shop/) is the answer key, not the first stop.

## vuln-net: weak services (10.10.10.13)

Classic infrastructure target: enumerate the three services, collect what they leak, then attack credentials. Anonymous and guest access is worth checking before anything else (`ftp`, `smbclient -N`). For credential attacks, `hydra` plus the SecLists password lists is the standard loop; usernames from your enumeration feed it.

### After the foothold

Three planted privesc breadcrumbs, one of which is only visible from inside. The usual post-exploitation checklist finds them: readable files in homes and the web root, `sudo -l`, [GTFOBins](https://gtfobins.github.io/). Full paths in `docs/walkthrough.md`.

## vuln-docker: WebGoat and crAPI (10.10.10.14)

WebGoat (`:8080/WebGoat`, guided lessons; WebWolf on `:9090/WebWolf`): the structured-learning target. Register an account on first visit; progress survives `make configure`, not `make destroy`. Without a GUI on the attacker, tunnel from your Mac:

```bash
ssh -L 8080:10.10.10.14:8080 -p 2201 redteam@127.0.0.1
```

crAPI (`:8888`, MailHog on `:8025`): OWASP API Top 10 microservice app; the free-form counterpart to WebGoat. Register an account, read the app's mail in MailHog (needed for several vulnerabilities), attack the APIs with curl/ffuf/Burp using your token. The [crAPI repo](https://github.com/OWASP/crAPI) is the answer key.

## vuln-k8s: Kubernetes (10.10.10.15)

Single-node k3s with cluster-level weaknesses. Recon: `nmap -sV -p 6443,10250 10.10.10.15`, and `kube-hunter --remote 10.10.10.15` if available. From any foothold on the node, the classic Kubernetes attack surface applies: file permissions, service-account and kubeconfig reachability, then what cluster RBAC lets you get away with. The intended chain runs scan to node escape; see `docs/walkthrough.md`.

## vuln-iot: MQTT (10.10.10.16)

Anonymous Mosquitto broker: connect, subscribe and see what falls out. `mosquitto-clients` is on the attacker.

```bash
nmap -p 1883 --script mqtt-subscribe 10.10.10.16
mosquitto_sub -h 10.10.10.16 -t '#' -v -W 30    # watch all traffic
```

Watch the traffic long enough to map the topic tree, then ask what a device trusts and what a publisher controls. Device behaviour in `docs/walkthrough.md`.

## Workflow

Metasploit is installed with its database initialised (`msfconsole -q`, then `db_nmap -sV <target>`, `hosts`). Loop for any target: enumerate → match version to a known issue ([searchsploit](https://www.exploit-db.com/searchsploit)) → exploit → loot → pivot.

Reset between sessions: `make destroy && make up` for a clean slate, `make configure` to just re-apply config.

## Rules of engagement

Only against the lab you built. Authorised, educational use on machines you own; never point these tools at anything without explicit permission.

# Attacking the lab

Operator's guide per target. Everything here is for **your own lab**: intentionally vulnerable machines, isolated on `10.10.10.0/24`. Targets default to `state=off` in `lab.conf`; set `state=on` and run `make up` first.

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

Deliberately broken shop with a built-in scoreboard. Start with recon (`whatweb`, `curl -I`, `ffuf` with the SecLists `common.txt` wordlist), then work the classics:

- **SQLi login bypass:** log in as admin with `' OR 1=1--` in the email field; automate with `sqlmap`
- **Broken access control:** change IDs in the API calls (`/api/Users/1`, basket IDs)
- **XSS:** the search field reflects unsanitised HTML
- **Hidden endpoints:** the JS bundles and the `/ftp` directory

The [companion guide](https://pwning.owasp-juice.shop/) is the answer key, not the first stop.

## vuln-net: weak services (10.10.10.13)

**Anonymous FTP (21):** `ftp 10.10.10.13` as `anonymous` with an empty password, or `curl ftp://10.10.10.13/ --user anonymous:`.

**Weak SSH (22):** a `victim` user with a top-list password:

```bash
hydra -l victim -P /usr/share/seclists/Passwords/Common-Credentials/10-million-password-list-top-1000.txt \
  ssh://10.10.10.13
```

**Open Samba (445):** world-writable guest share `public`: `smbclient -L //10.10.10.13/ -N`, `smbclient //10.10.10.13/public -N`, `enum4linux -a`.

### After the foothold

Three planted privesc breadcrumbs (hints only):

- Something in the web root was meant to be temporary (`/backup/config.txt`)
- Users leave key copies in their home directory; check permissions, try the key on every account
- `sudo -l` first; if it lists a binary, check [GTFOBins](https://gtfobins.github.io/)

## vuln-docker: WebGoat and crAPI (10.10.10.14)

**WebGoat** (`:8080/WebGoat`, guided lessons; WebWolf on `:9090/WebWolf`): the structured-learning target. Register an account on first visit; progress survives `make configure`, not `make destroy`. Without a GUI on the attacker, tunnel from your Mac:

```bash
ssh -L 8080:10.10.10.14:8080 -p 2201 redteam@127.0.0.1
```

**crAPI** (`:8888`, MailHog on `:8025`): OWASP API Top 10 microservice app; the free-form counterpart to WebGoat. Register an account, read the app's mail in MailHog (needed for several vulnerabilities), attack the APIs with curl/ffuf/Burp using your token. The [crAPI repo](https://github.com/OWASP/crAPI) is the answer key.

## vuln-k8s: Kubernetes (10.10.10.15)

Single-node k3s with cluster-level weaknesses. Recon: `nmap -sV -p 6443,10250 10.10.10.15`, and `kube-hunter --remote 10.10.10.15` if available. Attack paths (spoilers, minimal):

- `/etc/rancher/k3s/k3s.yaml` is world-readable (0644): any foothold on the box, as any user, is cluster-admin once you copy the kubeconfig to the attacker
- Enumerate secrets in every namespace (one holds a base64 "production database" credential), then `kubectl exec` into the `debug-tools` pod: privileged, `hostPID`, host filesystem on `/host`; effectively root on the node

Chain to practise: **scan → weak kubeconfig → cluster admin → secret theft → privileged pod → node escape**.

## vuln-iot: MQTT (10.10.10.16)

Anonymous Mosquitto broker, no ACLs: anyone who can connect owns every device. `mosquitto-clients` is on the attacker.

```bash
nmap -p 1883 --script mqtt-subscribe 10.10.10.16
mosquitto_sub -h 10.10.10.16 -t '#' -v -W 30    # watch all traffic
```

Planted weaknesses (spoilers, minimal):

- A gateway periodically publishes its admin credentials in a status topic; intercept it in the `#` firehose
- The smart lock obeys anyone publishing to its command topic:

```bash
mosquitto_pub -h 10.10.10.16 -t home/devices/smartlock/cmd -m 'open'
mosquitto_sub -h 10.10.10.16 -t home/devices/smartlock/state -W 5
```

## Workflow

Metasploit is installed with its database initialised (`msfconsole -q`, then `db_nmap -sV <target>`, `hosts`). Loop for any target: **enumerate → match version to a known issue ([searchsploit](https://www.exploit-db.com/searchsploit)) → exploit → loot → pivot**.

Reset between sessions: `make destroy && make up` for a clean slate, `make configure` to just re-apply config.

## Rules of engagement

Only against the lab you built. Authorised, educational use on machines you own; never point these tools at anything without explicit permission.

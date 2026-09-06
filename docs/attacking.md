# Attacking the lab

A short operator's guide: how to work from the Kali attacker box and where to
start on each target. Everything here is for **your own lab**. The machines are
intentionally vulnerable and isolated on `10.10.10.0/24`.

The layout after `make up`:

| Host | Lab IP | What it is |
|------|--------|------------|
| `attacker` | `10.10.10.11` | Kali, where you work |
| `vuln-web` | `10.10.10.12` | OWASP Juice Shop (web) |
| `vuln-net` | `10.10.10.13` | Weak SSH / FTP / Samba services |
| `vuln-docker` | `10.10.10.14` | OWASP WebGoat + WebWolf (guided web lessons) |
| `vuln-k8s` | `10.10.10.15` | k3s Kubernetes cluster with weak configuration |
| `vuln-iot` | `10.10.10.16` | Anonymous MQTT broker with simulated devices |

## Get onto the attacker

```bash
make ssh attacker             # from the repo on your Mac
```

The targets are already in `/etc/hosts` (`redteam-vuln-web`, `redteam-vuln-net`,
`redteam-vuln-docker`, `redteam-vuln-k8s`, `redteam-vuln-iot`),
SecLists is at `/usr/share/seclists`, and the toolset (`ATTACKER_TOOLSET`) is
installed. A good habit before a session:

```bash
sudo apt update && sudo apt full-upgrade -y
```

Tip: if you want a GUI (Burp Suite, a browser), open the `redteam-attacker`
console in UTM. The box installs the standard Kali kernel so the display works.
Everything below is terminal-only and works over SSH.

## Recon first

Sweep the segment, then fingerprint each host. Enumerate before you exploit.

```bash
# what's alive on the lab net
nmap -sn 10.10.10.0/24

# full service/version scan of all targets
nmap -sV -sC -p- 10.10.10.12 10.10.10.13 10.10.10.14 10.10.10.15 10.10.10.16
```

You should see `80/http` on `.12`, `21/ftp 22/ssh 80/http 445/microsoft-ds`
on `.13`, `8080 8888 9090/http` (Docker-proxy) and `8025` (MailHog) on `.14`,
`6443/https` plus `10250/https` (kubelet) on `.15`, and `1883/mqtt` on `.16`.
Match each open port to a follow-up ([nmap docs](https://nmap.org/book/man.html)).

## vuln-web: OWASP Juice Shop (10.10.10.12)

[Juice Shop](https://owasp.org/www-project-juice-shop/) is a modern, deliberately
broken shop with a built-in scoreboard of challenges. Start with web recon:

```bash
whatweb http://10.10.10.12
curl -I http://10.10.10.12
# content discovery
ffuf -u http://10.10.10.12/FUZZ -w /usr/share/seclists/Discovery/Web-Content/common.txt
```

Then work the classic bugs:

- **SQL injection login bypass:** log in as admin with `' OR 1=1--` in the email
  field. Automate deeper injection with [`sqlmap`](https://sqlmap.org/).
- **Broken access control:** inspect the API calls in your browser's dev tools
  (or Burp) and try changing IDs (`/api/Users/1`, basket IDs, etc.).
- **XSS:** the search field and several inputs reflect unsanitised HTML.
- **Sensitive data / hidden endpoints:** check the JavaScript bundles and the
  `/ftp` directory the app exposes.

The official [Juice Shop companion guide](https://pwning.owasp-juice.shop/) walks
every challenge if you get stuck. Treat it as the answer key, not the first stop.

## vuln-net: weak services (10.10.10.13)

This box is the "enumerate the infra" target. Its intended weaknesses:

**Anonymous FTP (vsftpd, port 21).** Anonymous login is enabled:

```bash
ftp 10.10.10.13          # log in as: anonymous / (empty password)
# or non-interactively
curl ftp://10.10.10.13/ --user anonymous:
```

**Weak SSH credentials (port 22).** There is a `victim` user with a weak
password. Brute force it with [Hydra](https://github.com/vanhauser-thc/thc-hydra)
and a SecLists wordlist:

```bash
hydra -l victim -P /usr/share/seclists/Passwords/Common-Credentials/10-million-password-list-top-1000.txt \
  ssh://10.10.10.13
# then just:
ssh victim@10.10.10.13
```

(The seed password is a top-list classic, so a small wordlist finds it fast.)

**Open Samba share (port 445).** A world-readable/writable guest share named
`public`:

```bash
smbclient -L //10.10.10.13/ -N        # list shares
smbclient //10.10.10.13/public -N     # connect as guest, then `ls`, `get`, `put`
enum4linux -a 10.10.10.13             # full SMB enumeration
```

### After the foothold: privesc breadcrumbs

Once you're on the box as `victim`, three planted misconfigurations take you
further. Finding them is the exercise; hints only:

- Something in the web root was meant to be temporary
  (`http://10.10.10.13/backup/config.txt`).
- Users often leave copies of keys in their home directory.
  Check file permissions, then try the key against every account you know.
- `sudo -l` is the first command after any login. If it lists a binary, check
  [GTFOBins](https://gtfobins.github.io/) for a shell escape.

## vuln-docker: WebGoat (10.10.10.14)

[WebGoat](https://owasp.org/www-project-webgoat/) is a deliberately insecure
app with **guided lessons**: each lesson explains a vulnerability, lets you
exploit it in the app itself, and shows the solution. It is the best target for
structured learning; Juice Shop is the better target for free-form practice.

Open in a browser (from the attacker GUI, or an SSH tunnel):

```bash
# from your Mac, if the attacker has no GUI:
ssh -L 8080:10.10.10.14:8080 -p 2201 redteam@127.0.0.1
```

- WebGoat lessons: `http://10.10.10.14:8080/WebGoat`
- WebWolf (companion app for some lessons): `http://10.10.10.14:9090/WebWolf`

Register a new account on first visit; progress is stored in the container
(`make configure` re-applies config without resetting it, `make destroy` wipes
it).

### crAPI (same host, port 8888)

[crAPI](https://owasp.org/www-project-crapi/) ("completely ridiculous API") is
a modern microservice app built to teach the **OWASP API Security Top 10**:
BOLA/IDOR on vehicle and mechanic records, JWT flaws, mass assignment,
excessive data exposure. It is the free-form counterpart to WebGoat's guided
lessons.

- Web app: `http://10.10.10.14:8888` (register a fresh account, e.g.
  `attacker@lab.local`)
- MailHog (reads every mail the app sends, needed for several
  vulnerabilities): `http://10.10.10.14:8025`
- Attack the APIs directly with curl/ffuf/Burp once you have a token; the
  OpenAPI spec is exposed by the app.

The [crAPI docs](https://github.com/OWASP/crAPI) describe every vulnerability;
treat them as the answer key.

## vuln-k8s: Kubernetes (10.10.10.15)

A single-node [k3s](https://k3s.io) cluster whose weaknesses are cluster-level,
not app-level. Recon first:

```bash
nmap -sV -p 6443,10250 10.10.10.15
# if kube-hunter is in your toolset:
kube-hunter --remote 10.10.10.15
```

The intended attack paths (spoilers, minimal):

- The API server on `6443` needs credentials to do anything interesting. The
  kubeconfig on the node is world-readable (`/etc/rancher/k3s/k3s.yaml`, mode
  0644), so any foothold on the box, as any user, hands you cluster-admin.
- With the kubeconfig on the attacker (e.g. over SSH), enumerate secrets in
  every namespace: one holds a base64 "production database" credential worth
  decoding. Then look at the `debug-tools` pod: privileged, `hostPID`, host
  filesystem mounted at `/host`; `kubectl exec` into it and you are
  effectively root on the node itself.

A full takeover chain to practise: **scan → weak kubeconfig → cluster admin →
secret theft → privileged pod → node escape**.

## vuln-iot: MQTT (10.10.10.16)

A Mosquitto MQTT broker with **no authentication and no ACLs**, plus simulated
devices. The core IoT lesson: if anyone can connect, anyone owns every device.

Recon and enumeration (`mosquitto-clients` is on the attacker):

```bash
nmap -p 1883 --script mqtt-subscribe 10.10.10.16
# subscribe to EVERYTHING for 30 seconds and watch what flows by:
mosquitto_sub -h 10.10.10.16 -t '#' -v -W 30
```

Two planted weaknesses (spoilers, minimal):

- One device periodically publishes a status message containing its admin
  credentials; intercept it in the `#` firehose.
- The smart lock obeys commands published to its command topic by anyone.
  Publish an "open" command and watch the state topic confirm it:

```bash
mosquitto_pub -h 10.10.10.16 -t home/devices/smartlock/cmd -m 'open'
mosquitto_sub -h 10.10.10.16 -t home/devices/smartlock/state -W 5
```

## Metasploit and a workflow

Metasploit is installed and the attacker role initialises its database, so the
console comes up connected (`db_status` shows `Connected to msf.`):

```bash
msfconsole -q
msf6 > db_nmap -sV 10.10.10.13        # scan straight into the workspace
msf6 > hosts                          # review what you found
```

A repeatable loop for any target: **enumerate → match a service/version to a
known issue ([searchsploit](https://www.exploit-db.com/searchsploit)) → exploit →
loot → pivot**. On this flat lab there's nothing to pivot to yet, so see
`docs/extending.md` for adding more targets.

## Reset between sessions

Because the whole lab is disposable, the fastest "undo" is a rebuild:

```bash
make destroy && make up      # clean slate
# or just re-apply config without recreating VMs
make configure
```

## Rules of engagement

Only ever run this against the lab you built. The tools here are for authorised,
educational use on machines you own. Never point them at anything you don't have
explicit permission to test.

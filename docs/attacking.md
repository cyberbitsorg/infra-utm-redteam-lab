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

## Get onto the attacker

```bash
make ssh VM=attacker          # from the repo on your Mac
```

The targets are already in `/etc/hosts` (`redteam-vuln-web`, `redteam-vuln-net`),
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

# full service/version scan of both targets
nmap -sV -sC -p- 10.10.10.12 10.10.10.13
```

You should see `80/http` on `.12`, and `21/ftp 22/ssh 80/http 445/microsoft-ds`
on `.13`. Match each open port to a follow-up ([nmap docs](https://nmap.org/book/man.html)).

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

## Metasploit and a workflow

Metasploit is installed. Start the console (a database is preconfigured on Kali):

```bash
msfconsole -q
msf6 > db_nmap -sV 10.10.10.13        # scan straight into the workspace
msf6 > hosts                          # review what you found
```

A repeatable loop for any target: **enumerate → match a service/version to a
known issue ([searchsploit](https://www.exploit-db.com/searchsploit)) → exploit →
loot → pivot**. On this flat lab there's nothing to pivot to yet, so see
`docs/extending.md` for adding a second subnet or an AD phase.

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

# Walkthrough (full spoilers)

Every planted weakness and one way to exploit it, per target. Read `docs/attacking.md` first and try each target yourself; come here when you are stuck or want to compare your path. Targets default to `state=off` in `lab.conf`; set `state=on` and run `make up` first.

## vuln-web: Juice Shop (10.10.10.12)

- SQLi login bypass: log in as admin with `' OR 1=1--` in the email field; automate with `sqlmap`
- Broken access control: change IDs in the API calls (`/api/Users/1`, basket IDs)
- XSS: the search field reflects unsanitised HTML
- Hidden endpoints: the JS bundles and the `/ftp` directory

The [companion guide](https://pwning.owasp-juice.shop/) covers the rest of the scoreboard.

## vuln-net: weak services (10.10.10.13)

FTP (21): anonymous login with an empty password: `ftp 10.10.10.13`, or `curl ftp://10.10.10.13/ --user anonymous:`.

SSH (22): the `victim` user has a top-list password:

```bash
hydra -l victim -P /usr/share/seclists/Passwords/Common-Credentials/10-million-password-list-top-1000.txt \
  ssh://10.10.10.13
```

Samba (445): world-writable guest share `public`: `smbclient -L //10.10.10.13/ -N`, `smbclient //10.10.10.13/public -N`, `enum4linux -a`.

### Privesc breadcrumbs

Three planted breadcrumbs:

1. `/var/www/html/backup/config.txt` in the web root holds a plaintext credential worth reusing elsewhere
2. `~victim/.backup/id_backup` is a world-readable private key that authorises the `backup` account: copy it to the attacker, `chmod 600`, `ssh -i` as `backup`
3. `sudo -l` as `victim` lists `/usr/bin/find`: a GTFOBins shell escape (`sudo find . -exec /bin/sh \; -quit`) yields root

## vuln-docker: WebGoat and crAPI (10.10.10.14)

WebGoat grades each lesson itself; open the lesson's hints in the UI when stuck. crAPI attack surface worth working:

- Broken user authentication: sign-up flow and the JWT returned on login (decode it, check the algorithm and the claims)
- Email verification: MailHog (`:8025`) holds the tokens; the refresh-token flow is also abusable
- Excessive exposure / BOLA: the vehicle and location endpoints take object IDs you should not be able to guess or reuse
- Mass assignment / XSS / SSRF: the profile endpoints accept more fields than the UI shows

The [crAPI repo](https://github.com/OWASP/crAPI) documents every vulnerability.

## vuln-k8s: Kubernetes (10.10.10.15)

Chain to practise: scan → weak kubeconfig → cluster admin → secret theft → privileged pod → node escape.

- `/etc/rancher/k3s/k3s.yaml` is world-readable (0644): any foothold on the box, as any user, is cluster-admin once you copy the kubeconfig to the attacker
- Enumerate secrets in every namespace (one holds a base64 "production database" credential), then `kubectl exec` into the `debug-tools` pod: privileged, `hostPID`, host filesystem on `/host`; effectively root on the node

## vuln-iot: MQTT (10.10.10.16)

The broker allows anonymous connections and applies no ACLs: anyone who can connect owns every device.

- A gateway periodically publishes its admin credentials in a status topic; intercept it with `mosquitto_sub -t '#'`
- The smart lock obeys anyone publishing to its command topic:

```bash
mosquitto_pub -h 10.10.10.16 -t home/devices/smartlock/cmd -m 'open'
mosquitto_sub -h 10.10.10.16 -t home/devices/smartlock/state -W 5
```

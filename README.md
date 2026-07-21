# Server Migration Redirect Demo

A laptop-local Docker Compose rig that shows a hostname being migrated from one
server to another with nginx — and the client never noticing.

Two backends (`server-old`, `server-new`) built from **one image**, differing only
in an identity env var. An nginx proxy in front of them. The audience watches a
request land on OLD, watches one word change in one small file, and watches the
same request land on NEW without a single client-side change.

Phase 1 (what this README covers) brings the rig up and proves HTTP lands on OLD
through the proxy, alongside the 301-redirect approach for contrast.

---

## One-time setup — a prerequisite, not a startup step

Your host machine needs `app.demo.test` to resolve to `127.0.0.1`:

```bash
echo '127.0.0.1  app.demo.test' | sudo tee -a /etc/hosts
```

**Why this exists.** The browser runs on your host, outside Docker, and cannot
query Docker's embedded DNS. The `client` container resolves `app.demo.test`
through Docker DNS for free; the browser cannot. Without the `/etc/hosts` line
the browser and the `client` container would be using two different names on
stage — and "the hostname never changed" is the exact claim this demo rests on.
One name, both clients (D-03, D-04).

**This is a host-OS change, performed once, by hand, by you.** Nothing in this
repository writes to `/etc/hosts` or escalates privileges — no setup script, no
`make install`, no bootstrap step. The line above is the only host state the
demo touches, and removing that line is the complete uninstall. `make status`
checks for the entry and prints this exact command if it is missing.

It is a prerequisite for the **browser** demo only. Every automated check passes
without it — the `client` container uses Docker DNS, and the host-side checks use
`localhost`.

---

## Starting the demo

```bash
docker compose up -d --wait
```

That is the whole thing. One command, no arguments, no environment file.

A Makefile is provided as a convenience wrapper, and `make up` does the same
thing plus a status print. The Makefile is **convenience only** — nothing
essential is hidden behind it, and every target is a one-line `docker compose`
invocation you could type yourself (D-20).

---

## Ports

| Port | Service | Role |
|------|---------|------|
| 9090 | `server-old` | direct access to the Old box |
| 9091 | `server-new` | direct access to the New box |
| 9092 | `proxy` | **the migration endpoint** — transparent reverse proxy |
| 9093 | `proxy` | the redirect listener — the other way of doing it |

**Narration mnemonic:** *"90 is the Old box, 91 is the New box, 92 proxies, 93
redirects."* Four adjacent numbers, monotonic, and the "92 proxies / 93
redirects" pairing is the one line that keeps them straight while you talk.

The direct backend ports exist for a reason beyond convenience: they let you say
"here are two separate boxes" *before* nginx enters the story, and they give the
301 redirect a real, reachable destination to point at (D-05).

All four are bound to `127.0.0.1` only. The rig is never offered to conference
wifi.

---

## The contrast demo (HTTP-04)

This is the conceptual crux. Same destination, two different mechanisms — and
only one of them is invisible to the client.

### In the browser (the primary path)

**Open a private / incognito window first.** This matters more than it sounds:
a `301 Moved Permanently` is cacheable **indefinitely** by specification, and
browsers honour that enthusiastically. In a normal window, a second run jumps
straight to the target without ever contacting nginx — no 301 appears in the
log, and the demo looks broken on stage. A private window, or devtools with
"Disable cache" ticked, avoids it entirely.

1. Visit **`http://app.demo.test:9092/`** — the amber **OLD** banner appears.
   The URL bar still reads `app.demo.test:9092`, exactly what you typed.
   *Someone answered on your behalf and you cannot tell.*

2. Visit **`http://app.demo.test:9093/`** — the same amber **OLD** banner, but
   the URL bar has visibly changed to `app.demo.test:9090`.
   *You were told to go somewhere else, and you went.*

Put the two tabs side by side. The difference in the URL bar is the entire
point: only the first mechanism lets a migration happen without the client
changing anything.

### On the command line (the backup path)

```bash
make contrast
```

```
PROXIED   9092 ->
  final=http://localhost:9092/whoami  redirects=0
REDIRECT  9093 ->
  final=http://app.demo.test:9090/whoami  redirects=1
```

Two labelled lines, one command — the technical backup view for when a projector
cannot show a URL bar (D-09). `curl` does not cache, so this path is immune to
the 301-caching trap above and can be run as many times as you like.

Note: the redirect target is reachable from the **host browser** (via the
`/etc/hosts` entry plus the published 9090), but **not** from inside the `client`
container, where `app.demo.test` resolves to the proxy — which does not listen
on 9090. Do not demo the redirect from inside the client container; the browser
is its home.

---

## What "the client never changes" means (HTTP-02 — the verification contract)

This is the claim the whole demo rests on, and it is easy to test against the
wrong thing. Being explicit about what is being verified:

**HTTP-02 is verified as URL invariance.** The client's requested URL — scheme,
host, port and path — is byte-identical before and after traversing the proxy.
The evidence:

- `curl -w '%{url_effective}'` with `-L` returns the URL that was typed
- `curl -w '%{num_redirects}'` returns `0` — nothing moved the client
- the proxy access log records `app.demo.test:9092` as the host and port the
  client asked for, and that field stays constant across the Phase 2 flip

**HTTP-02 is NOT verified via the client's source IP** — and this is not a
shortcut, it is unsatisfiable here. On macOS Docker Desktop every host-originated
request is SNAT'd to the Linux VM gateway `192.168.65.1` before nginx ever sees
it. `$remote_addr` shows `192.168.65.1` for every host request regardless of how
the proxy is configured, so it cannot evidence client-address invariance no
matter what you do. A reader who tests HTTP-02 against source IP will conclude
the demo failed on grounds that have nothing to do with the demo.

Practical note: if you want a meaningful source address in the log, issue the
request from the `client` container, where the real container IP is preserved:

```bash
docker compose exec client curl -sS http://app.demo.test:9092/whoami
# proxy log: 172.19.0.5 -> app.demo.test:9092 "GET /whoami HTTP/1.1" 200 ... backend=OLD
```

---

## Command reference

| Target | What it does |
|--------|--------------|
| `make up` | `docker compose up -d --build --wait`, then a status print |
| `make down` | `docker compose down` — stops the rig, keeps the images |
| `make status` | service/status/ports table, plus an `/etc/hosts` check with the exact fix line if missing |
| `make check` | alias for `status` |
| `make logs` | live tail of the proxy access log — this is where `backend=OLD` flips to `backend=NEW` |
| `make test` | the full smoke suite (`sh scripts/smoke.sh`) |
| `make contrast` | the proxied-vs-redirected side-by-side, two labelled lines |
| `make reload` | `nginx -t`, then a graceful `nginx -s reload`, then a verifying request — never a container restart |
| `make reset` | full teardown and rebuild, **and** restore of the flip include to OLD |

**`make reset` is the between-takes command.** It runs `docker compose down -v`
*and* rewrites `proxy/active-backend.conf` back to `old`. Both halves are
necessary: `down -v` removes containers, volumes and networks but does not touch
host files, so a previous take's flip would otherwise leave the demo opening on
NEW. Together they guarantee a byte-identical clean starting state on every run
(D-21).

Every target is a thin wrapper. `sh scripts/smoke.sh [backends|proxy|redirect]`
runs a single section if you want a faster loop.

---

## Layout

```
.
├── compose.yaml                  # the whole rig, one command
├── Makefile                      # the presenter's command surface
├── README.md                     # you are here
├── proxy/
│   ├── nginx.conf                # upstreams, log format, the 9092 proxy and the 9093 redirect
│   └── active-backend.conf       # <- THE ONE FILE THE CUTOVER EDITS (5 lines)
├── backend/
│   ├── Dockerfile                # one image, instantiated twice
│   ├── entrypoint.sh             # renders templates, generates host keys, execs supervisord
│   ├── supervisord.conf          # nginx + sshd in one container
│   └── templates/
│       ├── default.conf.template # X-Backend header, /healthz, /whoami
│       └── index.html.template   # the big colour-coded OLD/NEW banner
├── client/
│   └── Dockerfile                # the in-network command source (curl, ssh)
└── scripts/
    └── smoke.sh                  # every mechanically checkable requirement
```

`proxy/active-backend.conf` is the file to have open on screen during the
cutover. It is five lines, two of them comments, and the flip changes exactly one
word in it. Everything else — the upstream targets, the validity guard, the log
format — lives in `nginx.conf` so that file stays readable on a projector.

---

## SSH

`sshd` is built into the backend image now, and both backends are listening on
port 22 **inside** their containers. It is not routed and not demoed in this
phase, and **no host port is bound for it** — `docker compose ps` shows nothing
on 22.

From Phase 3 the `client` container is the canonical SSH source: it reaches the
backends entirely over the Docker network, with no host port published and no
client-side flag. That framing is what lets the "no client change" claim stay
fully honest — a presenter typing `ssh -p 2222` would have quietly conceded the
point.

---

## No cloud, no cost

Everything here runs on your laptop.

- Every image is a Docker Official Image (`nginx:1.30-alpine`, `alpine`) pulled
  anonymously. No `docker login`, no private registry, no registry credentials.
- No cloud SDK, no cloud account, no provisioning step, no bill.
- No `.env` file, no secrets file, no credential of any kind in this repository.
- The only credential that exists at all is a deliberately obvious throwaway SSH
  login inside the backend containers, which is published to no host port and
  reachable only from within the Docker network.

The complete uninstall is `docker compose down -v`, deleting this directory, and
removing the one `/etc/hosts` line you added at the top of this README.

---

## A note on privilege

No Makefile target, shell script, or compose entry in this repository executes
privileged commands or modifies host OS state. The escalation command appears in
exactly two places — this README, and the remediation line `make status` prints
when the `/etc/hosts` entry is missing — and in both it is text for you to read
and decide on, never something the repository runs.

That is deliberate. A demo rig you can throw away without wondering what it
changed is worth more than one that saves you thirty seconds of setup.

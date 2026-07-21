> **SUPERSEDED HOSTNAME:** every `app.demo.local` reference below reads `app.demo.test` as of 2026-07-21. `.local` is RFC 6762-reserved for multicast DNS; macOS routed it to an unreachable mDNS resolver under Tailscale, stalling every `getaddrinfo` for 5s. See `01-CONTEXT.md` D-22. This document is left otherwise unedited as a historical record.

# Phase 1: Demo Up, HTTP Lands on OLD - Research

**Researched:** 2026-07-21
**Domain:** nginx reverse proxy / TCP stream proxy, Docker Compose local orchestration, multi-process containers
**Confidence:** HIGH

> **Every material claim in this document was verified empirically on the target machine** (macOS 25.5.0, Docker Desktop 29.5.3, Docker Engine 29.6.1, Compose v5.1.4) by building and running a throwaway rig, not by web search or training recall. Commands and their observed output are quoted inline.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**Client-facing story**
- **D-01:** The demo uses a real-looking hostname, `app.demo.local`, not `localhost`. The "hostname stayed the same" claim is the point of the demo and `localhost` undermines it.
- **D-02:** A `client` container is part of the compose stack. It resolves `app.demo.local` via Docker's own DNS / `extra_hosts` and is the source of `curl` (and, in Phase 3, `ssh`) commands. Presenter runs e.g. `docker compose exec client curl http://app.demo.local:9092`.
- **D-03:** The presenter's host machine also gets an `/etc/hosts` entry mapping `app.demo.local` → `127.0.0.1`. This is a documented one-time setup step. Rationale: the browser runs on the host and cannot see Docker's internal DNS — without this the browser and the client container would be using two different names on stage, which muddies the story.
- **D-04:** Both clients therefore use the identical hostname. This is deliberate and load-bearing for the narrative.

**Network exposure**
- **D-05:** `server-old` and `server-new` are each exposed directly on their own host ports, in addition to being reachable through the proxy. Two reasons: the presenter can establish "here are the two boxes" before introducing the proxy, and the 301 redirect needs a real, reachable `Location` target.
- **D-06:** Exact port numbers for direct access and for the redirect listener are planner's discretion, with two constraints: 9092 is the proxied HTTP port (locked by the user), and the numbers should be adjacent/memorable enough to narrate.

**Redirect contrast (HTTP-03/04)**
- **D-07:** The proxy-vs-redirect contrast is demonstrated **in a browser**, not with `curl -v`. Seeing the URL bar stay put on the proxied port and visibly change on the redirect port is the most visceral proof for the audience.
- **D-08:** The redirect is served from a separate nginx port (not a path on 9092), so "port 9092 is the migration endpoint" stays a clean framing.
- **D-09:** `curl -v` remains available as the technical backup view, but the browser is the primary demo path.

**Backend identity signal (BACK-03)**
- **D-10:** Each backend serves an HTML page with a large, colour-coded **OLD** or **NEW** banner showing its hostname — readable across a room.
- **D-11:** Each backend also sets an `X-Backend: server-old` / `server-new` response header, so scripts and log inspection have something machine-greppable. Both signals, not one or the other.

**nginx config shape**
- **D-12:** The upstream target lives in a small dedicated include file (e.g. `active-backend.conf`), `include`d by the main nginx config. The Phase 2 flip must be a one-line edit in one small file that the audience can see in full on screen.
- **D-13:** The config is structured so the same include can later be referenced from the `stream` block in Phase 3, without restructuring.
- **D-14:** Changes are picked up with `docker compose exec proxy nginx -s reload` — a graceful reload, not a container restart. This is what you'd do in production and it implicitly makes the zero-downtime point.
- **D-15:** Phase 1 ships **no `stream` block at all**. ENV-04 is satisfied by proving the module is compiled in (`nginx -V`), which drives the base image choice. Phase 3 adds the stream config from scratch.

**Backend container makeup**
- **D-16:** One Dockerfile, built once, instantiated twice as two compose services. Identity comes from a `BACKEND_ID=OLD|NEW` (or equivalent) env var that drives the page banner, its colour, the `X-Backend` header, and later the SSH banner. Rationale: provably identical boxes differing only in identity strengthens "the only thing that changed is which server answered."
- **D-17:** Web server and sshd run **in the same container** per backend — one container = one "server". This matches the mental model the demo depends on and puts the Phase 4 host-key story naturally on the same box. Needs a small init/supervisor to run two processes; that trade-off is accepted.
- **D-18:** sshd is built into the image **now**, in Phase 1, even though SSH isn't routed or demoed until Phase 3. BACK-01/02 as written say the backends accept SSH, and building once avoids an image rebuild mid-project. Phase 1 simply doesn't route or demo it.

**Presenter command surface**
- **D-19:** A **Makefile** is the presenter's interface: `make up`, `make status`, `make reset`, and (from Phase 2) `make flip`. Short commands read well on stage and are hard to fumble live.
- **D-20:** The Makefile is convenience, not a dependency. Raw `docker compose up` must work standalone — ENV-01 is satisfied literally, and nothing essential is hidden behind `make`.
- **D-21:** `make reset` (ENV-02) does a **full teardown and rebuild** — `docker compose down -v` plus restoring the active-backend include to point at OLD. Guarantees an identical clean starting state on every run. The faster config-only flip-back is Phase 2's concern (CUT-05), not this.

### Claude's Discretion

- Base image choice for the proxy container, subject to the hard constraint that `nginx -V` shows the `stream` module compiled in.
- Base image and process supervisor for the backend containers (D-17 requires two processes in one container; the mechanism is open).
- Exact port numbers for direct backend access and the redirect listener (D-06).
- nginx log format — must make the serving upstream visible, since Phase 2's EVID-01 depends on it. Getting this right in Phase 1 avoids rework.
- Health check definitions and how "all came up healthy" is verified.
- File and directory layout of the repo.

### Deferred Ideas (OUT OF SCOPE)

- **Config-only fast flip-back** (containers keep running, just repoint the include and reload) — genuinely useful for back-to-back demo takes, but it is CUT-05 and belongs in Phase 2. Phase 1 only provides the full teardown reset.
- **`make flip` target** — Phase 2. Phase 1 should not implement the cutover, only structure the config so the flip is trivial.
- **`stream` block for SSH** — Phase 3, per D-15.
- **Shared SSH host keys / host-key mismatch staging** — Phase 4. Phase 1 installs sshd but takes no position on host-key generation strategy beyond not actively preventing Phase 4's approach.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| ENV-01 | Single `docker compose up` brings the entire demo up | Verified: 4-service compose file with `depends_on: condition: service_healthy` comes up clean from cold. See **Compose Orchestration**. |
| ENV-02 | Single command tears down and returns to clean state | Verified: `docker compose down -v` removes containers, volumes and network. D-21 also requires restoring the include — see **Makefile / Reset Semantics**. |
| ENV-03 | Runs entirely locally, no cloud account/credential/cost | Verified: all images are Docker Official Images pulled anonymously; no registry auth, no cloud calls. |
| ENV-04 | nginx container includes the `stream` module | **Verified by direct execution** — `nginx -V` shows `--with-stream` in *every* official nginx variant tested. See **Standard Stack** and **ENV-04 Verification**. |
| BACK-01 | `server-old` serves HTTP and accepts SSH | Verified: supervisord runs nginx + sshd in one container; both listening on 80/22. See **Pattern 2**. |
| BACK-02 | `server-new` serves HTTP and accepts SSH | Same image, second instance, `BACKEND_ID=NEW`. Verified. |
| BACK-03 | HTTP response body states identity (OLD/NEW) and hostname | Verified: envsubst-rendered `index.html` + `/whoami` endpoint. See **Pattern 3**. |
| HTTP-01 | Client reaches active backend via nginx on 9092 over plain HTTP | Verified end-to-end from both the host and a client container. |
| HTTP-02 | nginx forwards transparently — client address and port never change | Verified: `curl -L` reports `redirects=0` and `url_effective` unchanged. See **Pitfall 6** for the macOS source-IP caveat. |
| HTTP-03 | Separate nginx port returns 301/302 with a `Location` header to the backend directly | Verified: `return 301` on a dedicated listener. See **Pattern 4**. |
| HTTP-04 | Presenter can show side by side that proxy keeps the URL and redirect changes it | Verified with `curl -w '%{url_effective} %{num_redirects}'`; browser path is D-07's primary. See **Pattern 4**. |
</phase_requirements>

## Summary

This phase is entirely served by mainstream, boring technology: Docker Official Images (`nginx:1.30-alpine`, `alpine:3.22`), Docker Compose v2+ healthchecks, and nginx core modules. There is **no dependency to install from any language package registry** — no npm, no PyPI, no crates — which removes the largest class of supply-chain risk from this phase entirely.

The single most consequential design question in Phase 1 is not "which nginx image" (every official variant ships `--with-stream`), but **how the `active-backend.conf` include is shaped**, because D-12 (one-line flip in one small file) and D-13 (same include reusable from the `stream` block in Phase 3) are in tension. An `upstream {…}` block cannot be shared between the `http` and `stream` contexts — the backend ports differ (80 vs 22) and the two contexts have separate upstream namespaces. The resolution, **verified working in both contexts from a single included file**, is to put a `map` in the include and select between pre-declared upstreams by name. This satisfies D-12 and D-13 simultaneously and needs no restructuring in Phase 3.

Three findings materially change what the planner must specify, and would each have cost hours if discovered during execution. First, the nginx official image's `/docker-entrypoint.d/` templating machinery **silently does nothing** when you override `CMD` to run a supervisor — which is exactly the D-16 + D-17 combination this phase requires; the phase must ship its own entrypoint. Second, `ssh-keygen -A` run at **build** time bakes identical host keys into both backends, which would make Phase 4's KEY-01 (`server-new` has *different* host keys) impossible to stage; keys must be generated at container start. Third, the `map`-based flip **passes `nginx -t` even when the value is a typo** and fails as a runtime 502 — a live-stage hazard that Phase 1 should defuse now with a cheap validation guard.

**Primary recommendation:** Build on `nginx:1.30-alpine` for both the proxy and the backends. Give the backend image its own `ENTRYPOINT` that renders `BACKEND_ID`-driven templates with `envsubst`, generates SSH host keys at runtime, then `exec`s `supervisord` running nginx + sshd. Shape `active-backend.conf` as a single `map $server_port $active_backend { default old; }` include, with `upstream old`/`upstream new` pre-declared in `nginx.conf` and `proxy_pass http://$active_backend;`. Log with a custom `log_format` carrying both `$upstream_addr` and `$upstream_http_x_backend`.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Hostname resolution for the client container (`app.demo.local`) | Docker embedded DNS (127.0.0.11) | — | A compose **network alias** on the proxy service resolves the name straight to the proxy container; no host round-trip. Verified. |
| Hostname resolution for the host browser | Host OS (`/etc/hosts`) | — | The browser runs outside Docker and cannot query Docker DNS. D-03 already locks this. |
| HTTP request termination and forwarding (9092) | Proxy container (nginx `http` block) | — | `proxy_pass` — the client's URL is never rewritten. |
| Redirect demonstration (HTTP-03/04) | Proxy container (separate listener) | Host `/etc/hosts` + published backend ports | `return 301` needs a `Location` target that the *client* can reach; on the host that is a published backend port. |
| Backend identity (page, header, `/whoami`) | Backend container (nginx, env-driven) | — | Rendered at container start from `BACKEND_ID`; the proxy passes it through untouched. |
| Backend HTTP serving | Backend container (nginx) | — | Same nginx binary as the proxy — one technology to explain on stage. |
| Backend SSH listener | Backend container (OpenSSH sshd) | — | Built in Phase 1 (D-18), routed in Phase 3. |
| Two-process lifecycle inside one container | Backend container (supervisord as PID 1) | Docker `init` | D-17 requires co-location; supervisord restarts either process and reaps children. |
| Health determination | Docker healthcheck (`curl /healthz`) | Compose `depends_on: service_healthy` | Makes "came up healthy" (criterion 1) machine-checkable, not eyeballed. |
| Routing evidence / which upstream answered | Proxy container (`log_format`) | Backend `X-Backend` header | Phase 2's EVID-01 consumes this; the header is what makes the log human-readable. |
| Presenter command surface | Host (`Makefile`) | `docker compose` directly | D-19/D-20: convenience layer only, never load-bearing. |
| Port publishing to the host | Docker Desktop (VM port forwarder) | — | macOS-specific behaviour documented in Pitfall 6. |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `nginx` Docker Official Image, alpine variant | `1.30-alpine` (resolves to nginx 1.30.4) | Both the proxy and the backend web server | The only nginx distribution channel the project needs; `--with-stream` confirmed present, ~50 MB, and the same image serves both roles so there is one technology to explain on stage. [VERIFIED: `docker run --rm nginx:stable-alpine nginx -V`] |
| `alpine` Docker Official Image | `3.22` | Base for the `client` container | Smallest credible base with `apk` access to `curl` and `openssh-client` (the latter needed from Phase 3). [VERIFIED: `docker manifest inspect alpine:3.22`] |
| Docker Compose | v2+ (v5.1.4 present) | Orchestration, healthchecks, DNS, port publishing | ENV-01 names it directly; `depends_on: condition: service_healthy` requires Compose v2. [VERIFIED: `docker compose version` → `v5.1.4`] |
| OpenSSH `sshd` (Alpine `openssh` package) | Alpine 3.22 repo | Backend SSH listener (D-18, BACK-01/02) | The reference SSH implementation; Phase 4's host-key story assumes its file layout (`/etc/ssh/ssh_host_*`). [VERIFIED: installed and listening in the test rig] |
| `supervisor` (supervisord, Alpine package) | Alpine 3.22 repo | Runs nginx + sshd in one container (D-17) | See **Alternatives Considered** — chosen for explainability. [VERIFIED: running as PID 1 in the test rig] |
| `gettext-envsubst` (provides `envsubst`) | Pre-installed in `nginx:*-alpine` | Renders `BACKEND_ID` into config and HTML at container start (D-16) | Already in the nginx image — **zero packages to add** if you build on nginx. [VERIFIED: `apk info -W $(which envsubst)` → `gettext-envsubst-0.24.1-r1`] |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| `curl` (Alpine package) | Alpine 3.22 repo | Container healthchecks and the client container's request tool | Needed inside the backend image for the `CMD curl` healthcheck, and inside the client for the demo commands. |
| GNU Make | 3.81 (macOS system) | Presenter command surface (D-19) | Already present on macOS. **Do not use GNU Make 4+ syntax** — see Pitfall 8. [VERIFIED: `make --version` → `GNU Make 3.81`] |
| `openssh-client` (Alpine package) | Alpine 3.22 repo | Client container's `ssh` | Phase 3 needs it; adding it to the client image in Phase 1 avoids a rebuild mid-project, mirroring D-18's reasoning. Optional in Phase 1. |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `nginx:1.30-alpine` (stable) | `nginx:1.31-alpine` (mainline) | Both ship `--with-stream` [VERIFIED]. Mainline moves faster; a demo that must reproduce identically months later should sit on the stable line. Use `nginx:1.30.4-alpine` for a full pin. |
| `nginx:1.30-alpine` | `nginx:latest` (Debian, 1.31.3) | Also has `--with-stream` [VERIFIED], but ~3x the image size for no benefit here. |
| `nginx` on the backends | `busybox httpd` / `python -m http.server` | Smaller, but introduces a second web server to explain and loses `add_header`/`log_format`. Reusing nginx means one mental model across proxy and backends. |
| `supervisord` | `s6-overlay` | s6 is the more correct init (proper signal/PID-1 semantics, `docker stop` handled cleanly). But it needs a multi-file `/etc/s6-overlay/s6-rc.d/` tree and a tarball download in the Dockerfile. For a demo whose config must be readable on screen, a 14-line `supervisord.conf` wins on explainability. |
| `supervisord` | `tini` + a wrapper script backgrounding sshd | Fewest moving parts, but if sshd dies the container never notices and Phase 3 fails mysteriously. supervisord's `autorestart=true` removes that failure mode for ~10 extra lines. |
| `supervisord` | Two containers per "server" | Directly contradicts D-17 (locked). Not available. |
| `envsubst` templating | nginx `sub_filter` on the response body | `sub_filter` cannot set the `X-Backend` header (D-11) and adds per-request rewriting cost. envsubst renders once at start, is inspectable (`cat` the rendered file on stage), and covers both signals. |
| `envsubst` templating | Two separate Dockerfiles | Contradicts D-16 (locked) and weakens the "provably identical boxes" claim. |
| Compose network **alias** for `app.demo.local` | `extra_hosts: app.demo.local:host-gateway` | The alias resolves to the proxy container directly (`172.19.0.4`). `host-gateway` resolved to an **IPv6** address and routed the client out to the host and back in through the published port — it works, but it is a conceptually muddy path and it hides the client's real IP from the proxy log. **Use the alias.** [VERIFIED: both paths tested] |

**Installation:**

```bash
# No package-registry installs. All dependencies are Docker Official Images
# plus Alpine repo packages installed inside the backend image:
#   apk add --no-cache openssh supervisor curl
# `envsubst` is already present in nginx:*-alpine (gettext-envsubst).
```

**Version verification (run 2026-07-21 on the target machine):**

```
$ docker run --rm nginx:stable-alpine nginx -v   → nginx/1.30.4
$ docker run --rm nginx:alpine        nginx -v   → nginx/1.31.3
$ docker run --rm nginx:latest        nginx -v   → nginx/1.31.3
$ docker manifest inspect nginx:1.30-alpine      → exists
$ docker manifest inspect nginx:1.30.4-alpine    → exists
$ docker manifest inspect alpine:3.22            → exists
```

## Package Legitimacy Audit

**No language-ecosystem packages are installed by this phase.** There is no `package.json`, `requirements.txt`, or `Cargo.toml`. The `gsd-tools query package-legitimacy check` seam covers npm/PyPI/crates and is therefore not applicable; dependencies were instead verified directly against their authoritative registries by pulling and executing them.

| Package | Registry | Provenance | Verified How | Verdict | Disposition |
|---------|----------|-----------|--------------|---------|-------------|
| `nginx:1.30-alpine` | Docker Hub — **Docker Official Image** | Docker Official Images programme (`library/nginx`) | `docker manifest inspect` + `docker run … nginx -V` executed | OK | Approved |
| `alpine:3.22` | Docker Hub — **Docker Official Image** | Docker Official Images programme (`library/alpine`) | `docker manifest inspect` + executed | OK | Approved |
| `openssh` | Alpine `main` repository | Alpine Linux distro repo, signed index | Installed in-image; `sshd -D -e` observed listening on :22 | OK | Approved |
| `supervisor` | Alpine `main`/`community` repository | Alpine Linux distro repo, signed index | Installed in-image; observed as PID 1 supervising both processes | OK | Approved |
| `curl` | Alpine `main` repository | Alpine Linux distro repo, signed index | Installed in-image; healthcheck executed successfully | OK | Approved |
| `gettext-envsubst` 0.24.1-r1 | Alpine `main` repository | **Pre-installed** in `nginx:*-alpine` | `apk info -W /usr/bin/envsubst` → `gettext-envsubst-0.24.1-r1` | OK | Approved (no install needed) |

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

No package name in this document originated from WebSearch or training recall — every one was confirmed by execution against its registry. No `checkpoint:human-verify` gate is required for dependency installation in this phase.

## Architecture Patterns

### System Architecture Diagram

```
   ┌──── HOST (macOS, presenter's laptop) ─────────────────────────────────┐
   │                                                                        │
   │   Browser ──┐                                                          │
   │             │ resolves app.demo.local via /etc/hosts → 127.0.0.1  (D-03)│
   │             ▼                                                          │
   │   ┌── published ports on 127.0.0.1 ──────────────────────────────┐     │
   │   │  :9090      :9091       :9092            :9093               │     │
   │   └───┬──────────┬────────────┬────────────────┬────────────────┘     │
   └───────│──────────│────────────│────────────────│──────────────────────┘
           │          │            │                │
   ┌───────│──────────│────────────│────────────────│─── docker network ───┐
   │       │          │            ▼                ▼    (demo_default)     │
   │       │          │      ┌───────────────────────────────────────┐      │
   │       │          │      │            proxy  (nginx)             │      │
   │       │          │      │  alias: app.demo.local  ◄────────┐    │      │
   │       │          │      │                                  │    │      │
   │       │          │      │  :9092 http{}                    │    │      │
   │       │          │      │    server ── proxy_pass ──┐      │    │      │
   │       │          │      │                           │      │    │      │
   │       │          │      │  include active-backend.conf │   │    │      │
   │       │          │      │    map → $active_backend ──┤   [DNS]  │      │
   │       │          │      │         (old │ new)        │          │      │
   │       │          │      │                            ▼          │      │
   │       │          │      │  upstream old { server-old:80 }       │      │
   │       │          │      │  upstream new { server-new:80 }       │      │
   │       │          │      │                                       │      │
   │       │          │      │  :9093 ── return 301 Location: ───────┼──┐   │
   │       │          │      │           http://app.demo.local:9090  │  │   │
   │       │          │      │                                       │  │   │
   │       │          │      │  access_log → stdout (log_format demo)│  │   │
   │       │          │      │    $upstream_addr, $upstream_http_x_backend │
   │       │          │      └──────────┬────────────────────────────┘  │   │
   │       │          │                 │ ACTIVE path (Phase 1: → old)  │   │
   │       │          │       ┌─────────┴────────┐                      │   │
   │       ▼          ▼       ▼                  ▼                      │   │
   │  ┌──────────────────────────┐   ┌──────────────────────────┐       │   │
   │  │  server-old              │   │  server-new              │       │   │
   │  │  BACKEND_ID=OLD          │   │  BACKEND_ID=NEW          │       │   │
   │  │  ┌────────────────────┐  │   │  ┌────────────────────┐  │       │   │
   │  │  │ supervisord (PID 1)│  │   │  │ supervisord (PID 1)│  │       │   │
   │  │  │  ├─ nginx  :80     │  │   │  │  ├─ nginx  :80     │  │       │   │
   │  │  │  └─ sshd   :22 ····│··│···│··│··└─ sshd   :22 ····│··│ idle  │   │
   │  │  └────────────────────┘  │   │  └────────────────────┘  │ until │   │
   │  │  entrypoint renders:     │   │  entrypoint renders:     │ Ph.3  │   │
   │  │   index.html (banner)    │   │   index.html (banner)    │       │   │
   │  │   X-Backend: OLD         │   │   X-Backend: NEW         │       │   │
   │  │   /healthz  /whoami      │   │   /healthz  /whoami      │       │   │
   │  │   ssh_host_* (runtime!)  │   │   ssh_host_* (runtime!)  │       │   │
   │  └──────────────────────────┘   └──────────────────────────┘       │   │
   │            ▲                                                        │   │
   │            └──── redirect target reachable from HOST only ◄─────────┘   │
   │                                                                        │
   │  ┌───────────────────────────┐                                         │
   │  │ client (alpine+curl+ssh)  │── curl http://app.demo.local:9092 ──────┤
   │  │  resolves alias via       │   (Docker DNS → proxy container)        │
   │  │  Docker DNS 127.0.0.11    │                                         │
   │  └───────────────────────────┘                                         │
   └────────────────────────────────────────────────────────────────────────┘

   Flip mechanism (Phase 2, structured here in Phase 1):
     edit active-backend.conf: `default old;` → `default new;`
     docker compose exec proxy nginx -t && nginx -s reload
     Phase 3 adds a stream{} block that includes THE SAME FILE.
```

### Recommended Project Structure

```
.
├── compose.yaml                  # ENV-01: the whole rig
├── Makefile                      # D-19: up / status / logs / reset
├── README.md                     # D-03 one-time /etc/hosts step
├── proxy/
│   ├── nginx.conf                # main config; declares upstreams, includes the flip file
│   └── active-backend.conf       # D-12: THE ONE FILE THAT CHANGES (3 lines)
├── backend/
│   ├── Dockerfile                # D-16: one image, two instances
│   ├── entrypoint.sh             # renders templates, generates host keys, execs supervisord
│   ├── supervisord.conf          # D-17: nginx + sshd
│   └── templates/
│       ├── default.conf.template # X-Backend header, /healthz, /whoami
│       └── index.html.template   # D-10: big colour-coded OLD/NEW banner
├── client/
│   └── Dockerfile                # D-02: curl (+ openssh-client for Phase 3)
└── scripts/
    └── smoke.sh                  # verifies the five success criteria
```

Rationale for `proxy/active-backend.conf` living at the top of `proxy/` rather than under a subdirectory: on stage the presenter will `cat` it, and a short path reads better. It is deliberately the only file in `proxy/` besides `nginx.conf`.

### Pattern 1: The dual-context flip include (D-12 + D-13)

**What:** A single 3-line include file, `map`-based, referenced from **both** the `http` and `stream` blocks.

**Why this shape:** An `upstream {…}` block cannot be shared across contexts — `http` upstreams point at port 80, `stream` upstreams at port 22, and nginx keeps separate namespaces for them. Putting the *selector* rather than the *target* in the shared file resolves this. `map` is available in both contexts (`ngx_http_map_module` and `ngx_stream_map_module`, both compiled in), and `$server_port` is a core variable that exists in both.

**When to use:** Whenever a single value must steer two protocol contexts.

**Verified:** the config below passed `nginx -t` and served traffic with the `stream` block present, and a one-word edit + `nginx -s reload` flipped the served backend from OLD to NEW.

```nginx
# proxy/active-backend.conf — THE ONLY FILE THE PRESENTER EDITS
# Change `old` to `new` to cut over. That's it.
map $server_port $active_backend {
    default old;
}
```

```nginx
# proxy/nginx.conf  (Phase 1 form — no stream block, per D-15)
worker_processes 1;
events { worker_connections 1024; }

http {
    include /etc/nginx/mime.types;

    log_format demo '$remote_addr -> $host:$server_port "$request" '
                    '$status upstream=$upstream_addr backend=$upstream_http_x_backend '
                    'rt=$request_time urt=$upstream_response_time';
    access_log /dev/stdout demo;
    error_log  /dev/stderr notice;

    upstream old { server server-old:80; }
    upstream new { server server-new:80; }

    include /etc/nginx/active-backend.conf;   # ← defines $active_backend

    # HTTP-01/02: transparent reverse proxy. Client URL never changes.
    server {
        listen 9092;
        location / {
            proxy_pass http://$active_backend;
            proxy_set_header Host              $host;
            proxy_set_header X-Real-IP         $remote_addr;
            proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
        }
    }

    # HTTP-03/04: the contrast. Separate listener (D-08).
    server {
        listen 9093;
        location / { return 301 http://app.demo.local:9090$request_uri; }
    }
}

# Phase 3 will append — note it includes THE SAME FILE, no restructuring (D-13):
# stream {
#     upstream old { server server-old:22; }
#     upstream new { server server-new:22; }
#     include /etc/nginx/active-backend.conf;
#     server { listen 22; proxy_pass $active_backend; }
# }
```

**Verified detail:** `proxy_pass http://$active_backend;` with a variable and **no URI part** passes the original request URI through unchanged — `GET /whoami` on 9092 reached the backend's `/whoami` intact. (If you write `proxy_pass http://$active_backend/;` with a trailing slash, nginx substitutes the URI instead. Do not add the slash.)

**Verified detail:** nginx resolves the variable against **declared upstream group names first**, before attempting DNS. No `resolver` directive is needed as long as the value matches a declared upstream.

### Pattern 2: Two processes in one container (D-17)

**What:** `supervisord` as PID 1, supervising nginx and sshd, with both processes' logs multiplexed to the container's stdout/stderr so `docker compose logs` still works.

**Verified running state inside the container:**

```
    1 root  {supervisord} /usr/bin/python3 /usr/bin/supervisord -c /etc/supervisord.conf
   11 root  nginx: master process /usr/sbin/nginx -g daemon off;
   12 root  sshd: /usr/sbin/sshd -D -e [listener] 0 of 10-100 startups

tcp  0  0 0.0.0.0:22   0.0.0.0:*  LISTEN
tcp  0  0 0.0.0.0:80   0.0.0.0:*  LISTEN
```

```ini
# backend/supervisord.conf
[supervisord]
nodaemon=true
logfile=/dev/null
logfile_maxbytes=0
pidfile=/run/supervisord.pid

[program:nginx]
command=/usr/sbin/nginx -g "daemon off;"
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0

[program:sshd]
command=/usr/sbin/sshd -D -e
autorestart=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
stderr_logfile=/dev/stderr
stderr_logfile_maxbytes=0
```

`stdout_logfile_maxbytes=0` is mandatory — without it supervisord attempts log rotation on `/dev/stdout` and fails at startup. `nginx -g "daemon off;"` is mandatory — a daemonising nginx exits immediately and supervisord will restart-loop it.

Set `init: true` on the backend services in `compose.yaml` so Docker inserts `tini` as PID 1 for signal forwarding and zombie reaping; supervisord then runs as PID 2 under it.

### Pattern 3: Env-var-driven identity via an explicit entrypoint (D-16)

**What:** One image, one `BACKEND_ID`, rendering both the page (D-10) and the `X-Backend` header (D-11) at container start.

**Critical:** this **must** use the phase's own `ENTRYPOINT`, not the nginx image's `/docker-entrypoint.d/` mechanism. See **Pitfall 1** — the image's templating silently no-ops under a supervisor `CMD`.

```sh
#!/bin/sh
# backend/entrypoint.sh
set -e
: "${BACKEND_ID:?BACKEND_ID must be set}"
: "${BACKEND_COLOR:=#666666}"
export BACKEND_HOSTNAME="$(hostname)"

VARS='${BACKEND_ID} ${BACKEND_COLOR} ${BACKEND_HOSTNAME}'
envsubst "$VARS" < /templates/default.conf.template > /etc/nginx/conf.d/default.conf
envsubst "$VARS" < /templates/index.html.template  > /usr/share/nginx/html/index.html

# Generate SSH host keys at RUNTIME, not build time — see Pitfall 2.
# Each container therefore gets unique keys, which is what Phase 4 KEY-01 needs.
ssh-keygen -A

echo "entrypoint: rendered config for BACKEND_ID=${BACKEND_ID} host=${BACKEND_HOSTNAME}"
nginx -t
exec "$@"
```

Passing an **explicit variable list** to `envsubst` (rather than letting it substitute every env var) is what keeps nginx's own `$host`, `$remote_addr`, `$hostname` untouched. This is the same protection the nginx image offers via `NGINX_ENVSUBST_FILTER`, done explicitly.

```nginx
# backend/templates/default.conf.template
server {
    listen 80 default_server;
    server_name _;

    add_header X-Backend      "${BACKEND_ID}" always;   # ← envsubst
    add_header X-Backend-Host "$hostname"     always;   # ← nginx variable, untouched

    root /usr/share/nginx/html;
    location / { index index.html; }

    location = /healthz { access_log off; default_type text/plain; return 200 "ok\n"; }
    location = /whoami  { default_type text/plain; return 200 "${BACKEND_ID} $hostname\n"; }
}
```

**Verified response through the proxy:**

```
$ curl -sS -i http://localhost:9092/whoami
HTTP/1.1 200 OK
Server: nginx/1.29.8
Content-Type: text/plain
X-Backend: OLD
X-Backend-Host: server-old

OLD server-old
```

Note `add_header` is **not** a header the proxy strips — `proxy_pass` forwards backend response headers to the client verbatim, and the value also becomes available to the proxy's own log as `$upstream_http_x_backend`. Both D-11 consumers are served by one directive.

```html
<!-- backend/templates/index.html.template — D-10, readable across a room -->
<!doctype html><html><head><meta charset="utf-8"><title>${BACKEND_ID}</title>
<style>
  body{margin:0;font-family:system-ui,sans-serif;background:${BACKEND_COLOR};color:#fff;
       display:flex;flex-direction:column;align-items:center;justify-content:center;height:100vh}
  h1{font-size:22vw;margin:0;letter-spacing:.05em}
  p{font-size:3vw;opacity:.9;margin:.3em}
</style></head>
<body><h1>${BACKEND_ID}</h1><p>hostname: ${BACKEND_HOSTNAME}</p></body></html>
```

Suggested colours: OLD `#b45309` (amber) / NEW `#15803d` (green). `22vw` sizing means the word fills the screen at any projector resolution.

```dockerfile
# backend/Dockerfile
FROM nginx:1.30-alpine
RUN apk add --no-cache openssh supervisor curl \
 && adduser -D -s /bin/sh demo \
 && echo 'demo:demo' | chpasswd
COPY templates/       /templates/
COPY supervisord.conf /etc/supervisord.conf
COPY entrypoint.sh    /entrypoint.sh
RUN chmod +x /entrypoint.sh && rm -f /etc/nginx/conf.d/default.conf
ENV BACKEND_ID=OLD BACKEND_COLOR="#b45309"
EXPOSE 80 22
ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/bin/supervisord","-c","/etc/supervisord.conf"]
```

`rm -f /etc/nginx/conf.d/default.conf` is required — the stock config is a `default_server` on :80 and will shadow the rendered one if left in place.

### Pattern 4: Proxy-vs-redirect side by side (HTTP-03/04)

**Verified — the exact contrast the presenter shows:**

```
$ curl -sS -L -o /dev/null \
    -w 'final=%{url_effective} redirects=%{num_redirects}\n' \
    http://localhost:9092/whoami
final=http://localhost:9092/whoami redirects=0        ← PROXIED: URL unchanged

$ curl -sS -i http://localhost:9093/whoami
HTTP/1.1 301 Moved Permanently
Location: http://localhost:9090/whoami                ← REDIRECT: Location header

$ curl -sS -L -o /dev/null \
    -w 'final=%{url_effective} redirects=%{num_redirects}\n' \
    http://localhost:9093/whoami
final=http://localhost:9090/whoami redirects=1        ← REDIRECT: URL changed
```

`curl -w '%{url_effective}'` with `-L` is the cleanest single-line proof and is much easier to read on stage than `curl -v`. D-07 makes the browser primary; this is D-09's backup view and is worth putting in the Makefile as `make contrast`.

**Use `301` rather than `302`.** 301 is the migration-flavoured code the audience expects and it is what a real hostname migration would emit. Be aware that browsers **cache 301s aggressively** — see Pitfall 7.

**`Location` target choice.** Write it literally, not with `$host`:

```nginx
location / { return 301 http://app.demo.local:9090$request_uri; }
```

`$host` would technically work from the browser (nginx's `$host` excludes the port, so `http://$host:9090` renders correctly — verified), but a literal target is readable on screen and eliminates a whole class of confusion. **Known limitation:** this target is reachable from the host browser (via D-03's `/etc/hosts` + the published 9090) but **not** from the `client` container, where `app.demo.local` resolves to the proxy container, which is not listening on 9090. That is acceptable — D-07 already makes the browser the demo path for this criterion — but the walkthrough should not tell the presenter to run `curl -L` against 9093 from inside the client container.

### Pattern 5: Compose orchestration with real health gating

```yaml
name: demo

services:
  server-old:
    build: ./backend
    image: demo-backend:1
    hostname: server-old
    init: true
    environment:
      BACKEND_ID: OLD
      BACKEND_COLOR: "#b45309"
    ports: ["9090:80"]
    healthcheck:
      test: ["CMD", "curl", "-fsS", "http://localhost/healthz"]
      interval: 3s
      timeout: 2s
      retries: 10
      start_period: 3s

  server-new:
    image: demo-backend:1          # same image, no rebuild (D-16)
    depends_on: [server-old]       # ensures the image is built before this starts
    hostname: server-new
    init: true
    environment:
      BACKEND_ID: NEW
      BACKEND_COLOR: "#15803d"
    ports: ["9091:80"]
    healthcheck:
      test: ["CMD", "curl", "-fsS", "http://localhost/healthz"]
      interval: 3s
      timeout: 2s
      retries: 10
      start_period: 3s

  proxy:
    image: nginx:1.30-alpine
    volumes:
      - ./proxy/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./proxy/active-backend.conf:/etc/nginx/active-backend.conf:ro
    ports: ["9092:9092", "9093:9093"]
    networks:
      default:
        aliases: [app.demo.local]    # D-01/D-02: client resolves this via Docker DNS
    depends_on:
      server-old: {condition: service_healthy}
      server-new: {condition: service_healthy}

  client:
    build: ./client
    command: ["sleep", "infinity"]
    depends_on: [proxy]
```

**Verified from cold:**

```
$ docker compose up -d
 Container demo-server-old-1  Healthy
 Container demo-server-new-1  Healthy
 Container demo-proxy-1       Started
 Container demo-client-1      Started

SERVICE      STATUS
client       Up 12 seconds
proxy        Up 12 seconds
server-new   Up 18 seconds (healthy)
server-old   Up 18 seconds (healthy)
```

`depends_on: condition: service_healthy` is not cosmetic here — it is load-bearing. nginx **refuses to start** if an upstream hostname does not resolve at parse time:

```
nginx: [emerg] host not found in upstream "server-old:80" in /etc/nginx/nginx.conf:11
```

Without the health gate the proxy races the backends and `docker compose up` fails intermittently — a demo-day failure mode. [VERIFIED: reproduced directly.]

The `:ro` mount on `active-backend.conf` is safe: the presenter edits the file **on the host**, and the container sees the change immediately. Read-only only prevents writes from inside the container.

**Verified: the alias gives the proxy the client's real identity in the log —**

```
$ docker compose exec client curl -sS http://app.demo.local:9092/whoami
# proxy log:
172.19.0.6 -> app.demo.local:9092 "GET /whoami HTTP/1.1" 200 upstream=172.19.0.3:80 backend=OLD rt=0.000 urt=0.000
```

Both the client's real container IP **and** the hostname it asked for appear in the log — which is precisely the HTTP-02 evidence.

### Pattern 6: The log format (Claude's-discretion item; Phase 2 EVID-01 depends on it)

```nginx
log_format demo '$remote_addr -> $host:$server_port "$request" '
                '$status upstream=$upstream_addr backend=$upstream_http_x_backend '
                'rt=$request_time urt=$upstream_response_time';
access_log /dev/stdout demo;
```

**Verified output:**

```
192.168.65.1 -> localhost:9092    "GET /whoami HTTP/1.1" 200 upstream=172.19.0.3:80 backend=OLD rt=0.001 urt=0.001
192.168.65.1 -> localhost:9093    "GET /whoami HTTP/1.1" 301 upstream=-          backend=-   rt=0.000 urt=-
172.19.0.6   -> app.demo.local:9092 "GET /whoami HTTP/1.1" 200 upstream=172.19.0.3:80 backend=OLD rt=0.000 urt=0.000
```

Design rationale, and why this must be settled in Phase 1:

- **`$upstream_http_x_backend` is the field that makes EVID-01 work on stage.** It renders `backend=OLD` / `backend=NEW` — a word the audience can read from the back of the room as it flips. It is only populated because the backends set `X-Backend` (D-11), which is why D-11 and the log format are the same decision.
- **`$upstream_addr` alone is not sufficient** for the demo. It renders a container IP (`172.19.0.3:80`) that changes between `compose up` runs and means nothing to an audience. Keep it — it is the honest low-level evidence and pairs well as a technical follow-up — but do not rely on it as the primary signal.
- **`$host` and `$server_port`** together are the HTTP-02 proof: the presenter can point at `app.demo.local:9092` staying constant in the log across the flip.
- **Both are `-` on the redirect port**, which is itself a teaching moment: no upstream was involved, because nginx answered directly.
- `access_log /dev/stdout` (not a file) makes `docker compose logs -f proxy` the live tail EVID-01 asks for, with no volume mount or `tail -f` inside a container.

Phase 2 should not need to change this format. If it does, the flip-moment log tail has to be re-rehearsed.

### Anti-Patterns to Avoid

- **Putting the `upstream {…}` block in the shared include.** It cannot work in both `http` and `stream` (different ports, separate namespaces) and will force a restructure in Phase 3, breaking D-13.
- **Relying on the nginx image's `/docker-entrypoint.d/` templating on the backends.** It is silently skipped under a supervisor `CMD`. See Pitfall 1.
- **`ssh-keygen -A` in the Dockerfile.** Bakes identical host keys into both backends and makes Phase 4 impossible. See Pitfall 2.
- **`proxy_pass http://$active_backend/;`** (trailing slash). Changes URI-handling semantics; drops the request path.
- **Letting `envsubst` run without an explicit variable list.** It will happily eat nginx's `$host`, `$remote_addr`, and any other config variable whose name collides with an environment variable.
- **Adding a `stream` block in Phase 1.** D-15 is explicit, and there is a concrete hazard: the nginx image's entrypoint auto-appends its own `stream { include /etc/nginx/stream-conf.d/*.conf; }` to `nginx.conf` if it finds any `*.stream-template` file. Shipping no stream templates in Phase 1 keeps that machinery dormant.
- **Binding host port 22 in Phase 1.** Nothing needs it yet, and the mapping strategy is Phase 3's to settle (see Open Concerns).
- **Using `docker compose restart proxy` to pick up config changes.** Contradicts D-14 and throws away the zero-downtime point.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Waiting for backends before starting the proxy | A `wait-for-it.sh` / retry loop in an entrypoint | Compose `healthcheck` + `depends_on: condition: service_healthy` | Native, declarative, and surfaces the state in `docker compose ps` — which is what success criterion 1 is actually asking you to show. |
| Rendering `BACKEND_ID` into config and HTML | `sed` pipelines or a here-doc generator | `envsubst` with an explicit variable list | Already present in the image; explicit variable list is the exact protection you would otherwise reimplement badly. |
| Running nginx + sshd in one container | A shell wrapper backgrounding one and `wait`ing | `supervisord` (or s6-overlay) | A backgrounded process that dies goes unnoticed; `autorestart=true` is one line. |
| Determining which backend answered | Parsing the response body in the log, or a sidecar | `$upstream_http_x_backend` in `log_format` | nginx exposes every upstream response header as a log variable natively. |
| Zombie reaping / signal forwarding under a supervisor | A custom PID-1 signal handler | `init: true` in compose (Docker's bundled `tini`) | One line; correct `docker stop` behaviour. |
| Client hostname resolution inside the network | A custom DNS container, or hand-writing `/etc/hosts` in every container | Compose network `aliases` | Verified to resolve `app.demo.local` → the proxy container directly, and preserves the client's real source IP in the proxy log. |
| Config validation before reload | Diffing files or trusting the edit | `nginx -t` | Catches syntax errors while the old config keeps serving. Verified: traffic continued uninterrupted through a broken-config `nginx -t` failure. |

**Key insight:** Almost everything this phase needs is a first-class feature of nginx or Compose. The temptation to write glue is highest around startup ordering and template rendering — both of which have native, one-line answers. The one place custom code genuinely is needed is the backend entrypoint, and that is because the base image's built-in mechanism is incompatible with a locked decision (D-17), not because the mechanism is inadequate.

## Common Pitfalls

### Pitfall 1: The nginx image's template rendering silently does nothing under a supervisor CMD

**What goes wrong:** You put `default.conf.template` in `/etc/nginx/templates/`, set `BACKEND_ID`, override `CMD` to run supervisord — and the container starts fine, reports no error, and serves the **stock nginx welcome page** from the stock `default.conf`. No `X-Backend` header, no banner, no `/healthz`. The healthcheck then fails with a 404 and `depends_on: service_healthy` blocks the entire stack.

**Why it happens:** `/docker-entrypoint.sh` in the official image guards its whole body:

```sh
if [ "$1" = "nginx" ] || [ "$1" = "nginx-debug" ]; then
    # ... run every /docker-entrypoint.d/*.sh, including 20-envsubst-on-templates.sh
fi
exec "$@"
```

[VERIFIED: `docker run --rm --entrypoint sh nginx:1.29-alpine -c 'cat /docker-entrypoint.sh'`]

With `CMD ["/usr/bin/supervisord", ...]`, `$1` is `/usr/bin/supervisord`, the guard is false, and **nothing runs** — no templating, no logging, no warning. This is the direct collision between D-16 (env-var-driven identity) and D-17 (two processes in one container), and it is invisible until you check the response headers.

**Observed failure:**

```
$ docker exec backend ls /etc/nginx/conf.d/
default.conf            ← the STOCK one; templates/ was never processed
$ docker exec backend head -3 /usr/share/nginx/html/index.html
<!DOCTYPE html><html><head>   ← stock nginx welcome page
$ docker inspect backend --format '{{json .State.Health}}'
{"Status":"unhealthy", "Output":"curl: (22) The requested URL returned error: 404"}
```

**How to avoid:** Ship your own `ENTRYPOINT` that renders templates explicitly and then `exec "$@"` (Pattern 3). Do not put templates in `/etc/nginx/templates/` at all on the backend image — use a neutral path like `/templates/` so nobody later assumes the image's mechanism is in play.

**Warning signs:** `Server: nginx/…` present but `X-Backend` absent; healthcheck 404 on `/healthz`; the entrypoint's `Running envsubst on …` lines missing from `docker compose logs`.

### Pitfall 2: `ssh-keygen -A` at build time gives both backends identical host keys — silently breaking Phase 4

**What goes wrong:** `RUN ssh-keygen -A` in the Dockerfile runs **once**, at build. Both `server-old` and `server-new` are instantiated from that one image (D-16), so both present the **same** SSH host key. Everything appears to work in Phases 1–3. Phase 4's KEY-01 — "run the demo in a state where `server-new` has *different* SSH host keys from `server-old`" — then becomes impossible to stage, and the entire host-key-mismatch narrative, which PROJECT.md calls out as the single most valuable real-world lesson in the demo, cannot be told without a Dockerfile change and full rebuild.

**Verified:**

```
$ docker compose exec server-old ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
256 SHA256:WETjLhsQ4Pq8aX6IgO9GqZJTee8oGqG/anf/FEjsQo4 root@buildkitsandbox (ED25519)
$ docker compose exec server-new ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub
256 SHA256:WETjLhsQ4Pq8aX6IgO9GqZJTee8oGqG/anf/FEjsQo4 root@buildkitsandbox (ED25519)
                                                        ^^^^^^^^^^^^^^^^^^ same key, and the
                                                        build-sandbox hostname gives it away
```

CONTEXT.md D-18 states Phase 1 should take "no position on host-key generation strategy beyond **not actively preventing** Phase 4's approach." A build-time `ssh-keygen -A` actively prevents it.

**How to avoid:** Move `ssh-keygen -A` into `entrypoint.sh` so it runs per container, per start.

**Verified fix:**

```
$ docker run --rm demo-backend sh -c 'rm -f /etc/ssh/ssh_host_*; ssh-keygen -A >/dev/null; ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub'
256 SHA256:6wfiOPm3ExpPEK2qGAcc9Mgl3m5mioNxfiIHYQ4e0vM root@f78e56b8a481 (ED25519)
$ docker run --rm demo-backend sh -c '…same command…'
256 SHA256:KfqtMavXA8YP61gM3VVoDQpS9IEceg4SBUP5h2ab4uU root@8cd4de3dc5ce (ED25519)
                                                        ^^^ distinct — KEY-01 satisfied for free
```

Phase 1 does not need to *do* anything with this beyond generating at runtime; it just must not foreclose it.

**Warning signs:** `root@buildkitsandbox` as the key comment; identical fingerprints across the two backends.

### Pitfall 3: A typo in the flip value passes `nginx -t` and fails as a runtime 502

**What goes wrong:** Because `proxy_pass` uses a variable, nginx cannot validate the value at config-parse time. Typing `nwe` instead of `new` produces a config that tests **clean**, reloads **successfully**, and then 502s every request. On stage, mid-cutover, with the audience watching.

**Verified:**

```
# active-backend.conf contains:  default nwe;
$ docker compose exec proxy nginx -t
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful     ← PASSES

$ docker compose exec proxy nginx -s reload
2026/07/21 04:58:34 [notice] 62#62: signal process started             ← SUCCEEDS

$ curl -sS -o /dev/null -w 'HTTP %{http_code}\n' http://localhost:9092/whoami
HTTP 502                                                                ← fails here

# proxy error log:
[error] 68#68: *9 no resolver defined to resolve nwe, client: 192.168.65.1, …
```

**Why it happens:** This is the cost of the `map`-based design that makes D-12 and D-13 work together. Declaring the upstream target directly in the include would give hard `nginx -t` validation (`[emerg] host not found in upstream "server-old:80"` — verified) but breaks the shared-include requirement.

**How to avoid — recommended, ~3 lines, and it turns a mystery into a message:**

```nginx
# in nginx.conf http{}, after the include
map $active_backend $backend_is_valid {
    default 0;
    old     1;
    new     1;
}

server {
    listen 9092;
    if ($backend_is_valid = 0) {
        return 503 "INVALID BACKEND '$active_backend' in active-backend.conf — expected 'old' or 'new'\n";
    }
    location / { proxy_pass http://$active_backend; ... }
}
```

Also worth doing regardless: never reload without testing first, and always smoke-test after. Phase 1's Makefile should establish the pattern so Phase 2's `make flip` inherits it:

```make
reload:
	docker compose exec proxy nginx -t
	docker compose exec proxy nginx -s reload
	@sleep 1 && curl -fsS http://localhost:9092/whoami
```

**Warning signs:** 502 immediately after a reload; `no resolver defined to resolve <value>` in the error log; `upstream=-` in the access log where a real address should be.

### Pitfall 4: nginx refuses to start when an upstream hostname does not resolve

**What goes wrong:** `docker compose up` fails intermittently — the proxy exits before the backends have registered in Docker DNS.

**Verified:**

```
nginx: [emerg] host not found in upstream "server-old:80" in /etc/nginx/nginx.conf:11
nginx: configuration file /etc/nginx/nginx.conf test failed
```

**Why it happens:** nginx resolves `upstream … server <name>` at **config parse time**, not per request. If Docker DNS cannot answer yet, nginx aborts. This is a hard start failure, not a degraded mode.

**How to avoid:** `depends_on` with `condition: service_healthy` on both backends (Pattern 5). This is the reason healthchecks are load-bearing rather than decorative in this phase.

**Warning signs:** proxy container in `Exited (1)`; `host not found in upstream` in `docker compose logs proxy`; the failure appearing only on a cold machine or a fresh `down -v`.

### Pitfall 5: supervisord config mistakes that produce restart loops

**What goes wrong:** The container starts and immediately churns, or supervisord itself dies at startup.

**Three specific causes, all verified as requirements in the working config:**
- `command=/usr/sbin/nginx` without `-g "daemon off;"` → nginx forks and exits, supervisord restarts it forever.
- `stdout_logfile=/dev/stdout` **without** `stdout_logfile_maxbytes=0` → supervisord tries to rotate `/dev/stdout` and fails at startup.
- `nodaemon=true` missing under `[supervisord]` → supervisord daemonises, PID 1 exits, container stops.

**How to avoid:** Use Pattern 2's config verbatim. All three are already handled there.

**Warning signs:** `INFO spawned: 'nginx' with pid …` repeating in `docker compose logs`; container in a restart loop; `supervisord` exiting with code 0 immediately.

### Pitfall 6: On macOS Docker Desktop, published-port traffic arrives SNAT'd — do not use source IP as HTTP-02 evidence

**What goes wrong:** The presenter tries to prove "the client's address never changes" (HTTP-02) by pointing at `$remote_addr` in the nginx log, and it shows a meaningless internal VM address rather than anything recognisable.

**Verified:** a request from the **host** to `localhost:9092` logs `192.168.65.1` — Docker Desktop's Linux VM gateway, not the host's LAN address. A request from the **client container** over the Docker network logs `172.19.0.6` — the client's real container IP.

```
192.168.65.1 -> localhost:9092      …   ← from the host browser/curl (SNAT'd, meaningless)
172.19.0.6   -> app.demo.local:9092 …   ← from the client container (real, useful)
```

**How to avoid:** HTTP-02 is a claim about the **client's URL**, not its source IP. Prove it with `curl -w '%{url_effective}' -L` showing `redirects=0` and an unchanged URL (Pattern 4), and with the log's `$host:$server_port` field showing `app.demo.local:9092` constant. If the presenter wants to show a meaningful source address in the log, run the request from the **client container** (D-02), where the real IP is preserved.

**Warning signs:** `192.168.65.x` in `$remote_addr` for every host-originated request regardless of which machine you are on.

### Pitfall 7: Browsers cache 301s hard, which can break a repeat demo run

**What goes wrong:** The presenter demonstrates the redirect on 9093 in the browser. On a second run — or after Phase 2's flip — the browser jumps straight to the redirect target without ever contacting nginx, so the 301 never appears in the log and the demo appears broken.

**Why it happens:** `301 Moved Permanently` is cacheable indefinitely by specification, and browsers honour that enthusiastically.

**How to avoid:** Do the browser redirect demo in a private/incognito window, or with devtools open and "Disable cache" ticked; the walkthrough should say so explicitly. If robustness matters more than the migration-flavoured status code, use `302` instead — but 301 is the more honest illustration of what a real hostname migration emits, so prefer 301 plus the incognito instruction. Note that `curl` does **not** cache, so the `curl -L` backup path (D-09) is immune.

**Warning signs:** No 301 line in `docker compose logs proxy` even though the browser clearly moved; the URL bar changing instantly with no network round-trip in devtools.

### Pitfall 8: macOS ships GNU Make 3.81 (from 2006)

**What goes wrong:** A Makefile written with `.ONESHELL:`, `$(file …)`, or GNU Make 4 `.RECIPEPREFIX` behaviour silently misbehaves or errors on the presenter's laptop.

**Verified:** `make --version` → `GNU Make 3.81` on the target machine.

**How to avoid:** Keep the Makefile to `target: ; <tab>command` and `.PHONY`. Nothing in D-19's `up` / `status` / `reset` needs anything more. Declare `.PHONY: up down status logs reset contrast` so the targets never collide with files.

**Warning signs:** `*** missing separator` errors; `.ONESHELL` having no effect.

### Pitfall 9: `docker compose down -v` alone does not satisfy ENV-02/D-21

**What goes wrong:** `make reset` tears everything down, brings it back — and the demo starts pointed at NEW because the previous run's flip left `active-backend.conf` edited. The "identical clean starting state" guarantee fails silently, and the presenter opens on the wrong backend.

**Why it happens:** `active-backend.conf` is a bind-mounted **host** file, tracked in git. `down -v` removes containers, volumes, and networks — it does not touch host files.

**How to avoid:** `make reset` must restore the include as well, exactly as D-21 specifies:

```make
.PHONY: reset
reset:
	docker compose down -v
	printf 'map $$server_port $$active_backend {\n    default old;\n}\n' > proxy/active-backend.conf
	docker compose up -d --build
	@$(MAKE) status
```

Note the `$$` — Make consumes single `$`. (`git checkout -- proxy/active-backend.conf` is an alternative, but it fails if the file has legitimate uncommitted edits, so writing the known-good content is more robust.)

**Warning signs:** A second demo run opening on NEW; `git status` showing `proxy/active-backend.conf` modified after a "reset".

### Pitfall 10: Single-file bind mounts and editor inode replacement

**What goes wrong:** In some Docker + editor combinations, editing a single bind-mounted **file** with a tool that replaces the inode (`sed -i`, `vim` with default `backupcopy`) leaves the container still holding the original inode, so `nginx -s reload` re-reads unchanged content. The flip appears to do nothing.

**Verified on this machine:** this does **not** occur — `sed -i ''` (which replaces the inode) followed by `nginx -s reload` correctly served the new backend on Docker Desktop 29.5.3 with VirtioFS. The mechanism is sound here.

**How to avoid:** It is verified working, so a single-file mount is acceptable. If the planner wants belt-and-braces against a presenter using a different editor or a colleague on a different Docker version, mount the **directory** instead (`./proxy:/etc/nginx/demo:ro`) and `include /etc/nginx/demo/active-backend.conf;`. Cost: one extra path segment in the config. Recommend the directory mount for robustness, since the demo may be run on a machine other than the one tested here.

**Warning signs:** `nginx -s reload` succeeding but the backend not changing; `docker compose exec proxy cat /etc/nginx/active-backend.conf` showing stale content that differs from the host file.

## Code Examples

All examples in **Architecture Patterns** above were executed in a working rig on the target machine on 2026-07-21 and produced the quoted output. The complete, verified end-to-end proof sequence for the five success criteria:

```bash
# Criterion 1 — one command, everything healthy
docker compose up -d
docker compose ps --format 'table {{.Service}}\t{{.Status}}'
#   server-old   Up 18 seconds (healthy)
#   server-new   Up 18 seconds (healthy)
#   proxy        Up 12 seconds
#   client       Up 12 seconds

# Criterion 2 — proxied request lands on OLD, URL unchanged
curl -sS -i http://app.demo.local:9092/whoami
#   HTTP/1.1 200 OK
#   X-Backend: OLD
#   X-Backend-Host: server-old
#   OLD server-old
curl -sS -L -o /dev/null -w 'final=%{url_effective} redirects=%{num_redirects}\n' \
     http://app.demo.local:9092/whoami
#   final=http://app.demo.local:9092/whoami redirects=0

# Criterion 3 — redirect port changes the URL
curl -sS -i http://app.demo.local:9093/whoami | head -3
#   HTTP/1.1 301 Moved Permanently
#   Location: http://app.demo.local:9090/whoami
curl -sS -L -o /dev/null -w 'final=%{url_effective} redirects=%{num_redirects}\n' \
     http://app.demo.local:9093/whoami
#   final=http://app.demo.local:9090/whoami redirects=1

# Criterion 4 — teardown to clean state
docker compose down -v
#   Container demo-server-new-1  Removed
#   Network demo_default         Removed

# Criterion 5 — ENV-04: stream module compiled in
docker compose exec proxy nginx -V 2>&1 | tr ' ' '\n' | grep -- --with-stream
#   --with-stream
#   --with-stream_realip_module
#   --with-stream_ssl_module
#   --with-stream_ssl_preread_module
```

### ENV-04 Verification — every official nginx variant qualifies

[VERIFIED: executed 2026-07-21]

| Image | nginx version | `--with-stream` |
|-------|---------------|-----------------|
| `nginx:1.29-alpine` | 1.29.8 | ✓ (+ realip, ssl, ssl_preread) |
| `nginx:stable-alpine` | 1.30.4 | ✓ (+ realip, ssl, ssl_preread) |
| `nginx:alpine` | 1.31.3 | ✓ (+ realip, ssl, ssl_preread) |
| `nginx:latest` (Debian) | 1.31.3 | ✓ (+ realip, ssl, ssl_preread) |

ENV-04 imposes **no real constraint** on image choice — this is worth knowing, because it was framed in CONTEXT.md as the driver of the base-image decision. Choose on size and version-stability instead. `nginx:1.30-alpine` (stable line, pinned minor) is the recommendation.

Note that `--with-stream` is a **static** build flag here, not a dynamic module — there is no `load_module` line to add. The `stream {}` block simply works once written in Phase 3.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `docker-compose` (v1, Python) with a `version:` key in the YAML | `docker compose` (v2+, Go plugin); `version:` is obsolete and warns | Compose v2, 2021+ | Do **not** put `version: "3.8"` in `compose.yaml`. Use `name:` instead to control the project prefix. |
| `docker-compose.yml` | `compose.yaml` is the Compose Specification's preferred filename | Compose Specification | Both work; `compose.yaml` is current. |
| `wait-for-it.sh` / `dockerize` startup ordering | `healthcheck` + `depends_on: condition: service_healthy` | Compose v2 | Removes a whole class of glue scripts. |
| Building nginx from source to obtain `stream` | Every official nginx image ships `--with-stream` | Long-standing | Verified above. No custom build needed. |
| `links:` between services | Automatic Docker DNS on the default network; `aliases:` for extra names | Long-standing | `links:` is legacy. |
| Hand-rolled `--init`-style PID 1 shims | `init: true` in the service definition | Compose v2 | One line. |

**Deprecated/outdated:**
- `version:` top-level key in Compose files — obsolete, emits a warning.
- `links:` — superseded by the default bridge network's DNS.
- `docker-compose` (hyphenated v1) — end-of-life; all commands here use `docker compose`.

## Runtime State Inventory

Not applicable — this is a greenfield phase creating a new rig, not a rename, refactor, or migration. There is no pre-existing runtime state. Verified: the repository contains only `.planning/`, `.claude/`, and `.git/`; no source files, no Dockerfiles, no running containers for this project.

## Environment Availability

[VERIFIED: probed on the target machine 2026-07-21]

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Docker Engine | ENV-01, ENV-03, everything | ✓ | 29.6.1 (server 29.5.3, Docker Desktop) | — |
| Docker Compose | ENV-01, ENV-02 | ✓ | v5.1.4 (v2+ syntax) | — |
| GNU Make | D-19 presenter surface | ✓ | 3.81 (see Pitfall 8) | Raw `docker compose` per D-20 |
| `curl` (host) | HTTP-01..04 demo, smoke tests | ✓ | 8.7.1 | Browser (D-07 primary anyway) |
| Docker Hub anonymous pull | All base images | ✓ | `nginx` and `alpine` pulled successfully | — |
| Host port 9090 | server-old direct (D-05) | ✓ free | — | — |
| Host port 9091 | server-new direct (D-05) | ✓ free | — | — |
| Host port 9092 | Proxied HTTP (locked) | ✓ free | — | — |
| Host port 9093 | Redirect listener (D-08) | ✓ free | — | — |
| Host port 22 | *Not used in Phase 1* (D-15) | ✓ free | — | Phase 3's concern; see Open Concerns |
| Host `/etc/hosts` write access | D-03 `app.demo.local` → 127.0.0.1 | ⚠ needs `sudo` | no passwordless sudo on this machine | Presenter runs one documented `sudo` line; see below |

**Missing dependencies with no fallback:** none.

**Items requiring presenter action:**
- **D-03 `/etc/hosts` entry.** Verified absent (`grep demo /etc/hosts` → no entry) and verified to require `sudo` (no passwordless sudo configured). This is a genuine one-time manual setup step and must be documented prominently in the README — it cannot be automated inside `docker compose up`, so it does **not** violate ENV-01, but a presenter who skips it will find `app.demo.local` unresolvable in the browser.

  ```bash
  echo '127.0.0.1  app.demo.local' | sudo tee -a /etc/hosts
  ```

  Recommend `make check` / `make status` verify this and print the exact fix line if missing, so the failure is caught before stage time rather than during it.

**Port allocation recommendation (D-06 discretion, all verified free):**

| Port | Role | Narration |
|------|------|-----------|
| 9090 | `server-old` direct | "90 is the **O**ld box" |
| 9091 | `server-new` direct | "91 is the **N**ew box" |
| **9092** | **Proxied HTTP (locked)** | "**92 proxies** — the migration endpoint" |
| 9093 | Redirect listener | "**93 redirects** — the other way of doing it" |

Four adjacent ports, monotonic, and the pairing "92 proxies / 93 redirects" is the one-line mnemonic the presenter needs for HTTP-04's side-by-side.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | **None — POSIX shell assertions.** No language runtime exists in this project (no Node, Python, or Rust toolchain is required or present), so introducing a test framework would add a setup dependency that directly contradicts ENV-03's "no prior setup" and the project's disposability goal. |
| Config file | none — see Wave 0 |
| Quick run command | `sh scripts/smoke.sh` |
| Full suite command | `make test` (wraps `scripts/smoke.sh`) |

`bats-core` was considered and rejected: it would need `apk`/`brew` installation on the presenter's machine for six assertions that `curl -fsS` plus `test` already express clearly. The Phase 3 verify script (EVID-04/05) has the same shape — a shell script asserting observed backend against expected and exiting non-zero — so establishing plain shell in Phase 1 means EVID-04 extends `scripts/smoke.sh` rather than introducing a second idiom.

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| ENV-01 | `docker compose up` brings all services up | integration | `docker compose up -d --wait` (exits non-zero if any healthcheck fails) | ❌ Wave 0 |
| ENV-02 | Teardown returns to clean state | integration | `docker compose down -v && test -z "$(docker compose ps -aq)"` | ❌ Wave 0 |
| ENV-03 | No cloud credentials required | manual-only | Inspection: no registry auth, no cloud SDK, no secrets in the repo. Not meaningfully automatable. | n/a |
| ENV-04 | `stream` module compiled in | smoke | `docker compose exec -T proxy nginx -V 2>&1 \| grep -q -- --with-stream` | ❌ Wave 0 |
| BACK-01 | `server-old` serves HTTP and accepts SSH | smoke | `curl -fsS localhost:9090/healthz && docker compose exec -T server-old sh -c 'nc -z localhost 22'` | ❌ Wave 0 |
| BACK-02 | `server-new` serves HTTP and accepts SSH | smoke | `curl -fsS localhost:9091/healthz && docker compose exec -T server-new sh -c 'nc -z localhost 22'` | ❌ Wave 0 |
| BACK-03 | Response body states identity and hostname | smoke | `curl -fsS localhost:9090/whoami \| grep -q '^OLD server-old$'` (and NEW/server-new on 9091) | ❌ Wave 0 |
| HTTP-01 | Client reaches active backend via 9092 | smoke | `curl -fsS http://localhost:9092/whoami \| grep -q OLD` | ❌ Wave 0 |
| HTTP-02 | URL unchanged through the proxy | smoke | `test "$(curl -sSL -o /dev/null -w '%{num_redirects}' http://localhost:9092/)" = 0` | ❌ Wave 0 |
| HTTP-03 | Redirect port returns 3xx with `Location` | smoke | `curl -sS -o /dev/null -w '%{http_code} %{redirect_url}' http://localhost:9093/ \| grep -q '^301 '` | ❌ Wave 0 |
| HTTP-04 | Redirected URL differs from requested | smoke | `test "$(curl -sSL -o /dev/null -w '%{url_effective}' http://localhost:9093/whoami)" != "http://localhost:9093/whoami"` | ❌ Wave 0 |
| — | `X-Backend` header present (D-11, feeds EVID-01) | smoke | `curl -sSI http://localhost:9092/ \| grep -qi '^X-Backend: OLD'` | ❌ Wave 0 |
| — | Log format exposes serving backend (Phase 2 EVID-01 precondition) | smoke | `docker compose logs proxy \| grep -q 'backend=OLD'` | ❌ Wave 0 |
| — | Host keys differ between backends (Phase 4 KEY-01 precondition) | smoke | compare `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` across both; assert **not** equal | ❌ Wave 0 |

The last three rows are not Phase 1 requirements but are Phase 1 *responsibilities* — each is a precondition a later phase silently depends on, and each was found to be a real failure mode during this research. Asserting them in Phase 1's smoke script is what stops them regressing unnoticed.

### Sampling Rate

- **Per task commit:** `sh scripts/smoke.sh` (whole suite runs in a few seconds against an already-up stack)
- **Per wave merge:** `make reset && make test` (cold-start path — catches the Pitfall 4 startup race that a warm stack hides)
- **Phase gate:** `make reset && make test` green, plus the manual browser check for HTTP-04 (D-07), before `/gsd-verify-work`

The cold-start distinction matters: the `depends_on: service_healthy` race and the `[emerg] host not found in upstream` failure only manifest from a cold `down -v`, so a warm-stack-only test suite would miss the single most likely demo-day failure.

### Wave 0 Gaps

- [ ] `scripts/smoke.sh` — covers ENV-01, ENV-02, ENV-04, BACK-01, BACK-02, BACK-03, HTTP-01..04 plus the three cross-phase preconditions
- [ ] `Makefile` targets `test` and `status` — the runner surface (D-19)
- [ ] Framework install: **none required** — POSIX shell plus `curl`, both already present [VERIFIED]

## Security Domain

This is a locally-run demonstration artifact with no network exposure beyond loopback, no user data, and no persistence. PROJECT.md explicitly places "production hardening (auth, rate limiting, real certs)" out of scope. The applicable ASVS surface is correspondingly small, but three items are genuinely relevant because the artifact contains an SSH server and will be committed to a git repository.

### Applicable ASVS Categories (Level 1)

| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | **yes** (sshd) | Demo credentials only, never real ones. `demo:demo` is a deliberately obvious throwaway. sshd must never be published on a host port in Phase 1 (D-15 already ensures this), so the credential is reachable only from inside the Docker network. |
| V3 Session Management | no | No sessions, no cookies, no state. |
| V4 Access Control | no | No authorization model; every endpoint is intentionally public within the demo network. |
| V5 Input Validation | no (minimal) | nginx serves static content and fixed `return` responses. No user input reaches an interpreter. The one variable-driven path (`proxy_pass http://$active_backend`) is fed from a config file, not from a request. |
| V6 Cryptography | **yes** (SSH host keys) | Use `ssh-keygen -A` (OpenSSH's own generator) — never hand-roll or commit key material. Keys are generated at container runtime (Pitfall 2) and are therefore ephemeral and never in git. |
| V14 Configuration | **yes** | No secrets in the repository; pinned base image tags; no `latest`. |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Weak/default SSH credentials reachable from outside the laptop | Spoofing / Elevation | Do not publish port 22 to the host in Phase 1 (D-15 already forbids it). When Phase 3 does publish it, bind to loopback explicitly (`127.0.0.1:2222:22`) rather than `0.0.0.0`, so a laptop on conference wifi is not offering `demo:demo` to the room. **Flag for Phase 3.** |
| SSH host private keys committed to git | Information Disclosure | Runtime generation (Pitfall 2's fix) means no key material ever exists in the build context. Add `**/ssh_host_*` to `.gitignore` as defence in depth. |
| `sshd` running as root in a container | Elevation | Accepted for a local demo; sshd requires root to bind :22 and manage PAM. Not published to the host in Phase 1. |
| Host header injection into the redirect `Location` | Tampering / Open redirect | Mitigated by the Pattern 4 recommendation to write the `Location` target **literally** rather than deriving it from `$host`. A `$host`-derived `Location` on a publicly reachable server is a textbook open redirect; the literal form has no such surface. |
| Unpinned base images pulling a changed layer | Tampering | Pin to `nginx:1.30-alpine` / `alpine:3.22`, not `latest`. Already the recommendation. |
| Port 9092/9093 exposed on all host interfaces | Information Disclosure | `ports: ["9092:9092"]` binds `0.0.0.0`. For a demo on untrusted wifi, `127.0.0.1:9092:9092` is stricter — but note it would break the D-03 browser story only if the presenter mirrors to an external display over the network, which they do not. **Recommend loopback binding**; it costs nothing and the browser reaches it via `app.demo.local` → `127.0.0.1` anyway. |

No high-severity finding blocks this phase. The two actionable items — literal `Location` target and loopback port binding — are both already consistent with the recommended configuration.

## Assumptions Log

Nearly every claim in this document was verified by execution on the target machine. The following are the exceptions.

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Browsers cache `301` responses aggressively enough to disrupt a repeat demo run | Pitfall 7 | LOW — the mitigation (incognito window, or `302`) is cheap and harmless either way. Not verified in a browser during this research; based on HTTP caching semantics. |
| A2 | `s6-overlay` is heavier to explain on stage than `supervisord` | Alternatives Considered | LOW — a judgement call about presentation clarity, not a technical claim. Both work; supervisord was the one actually verified running. |
| A3 | The single-file bind-mount inode issue (Pitfall 10) may occur on Docker versions or editors other than the one tested | Pitfall 10 | LOW — verified *working* on the target machine; the directory-mount recommendation is precautionary hedging for other machines, not a known failure. |
| A4 | Suggested colours `#b45309` / `#15803d` read clearly across a room on a projector | Pattern 3 | LOW — cosmetic; the presenter can adjust. Not tested on projection hardware. |
| A5 | The presenter's demo machine will have ports 9090–9093 free | Environment Availability | LOW — verified free on *this* machine; another machine may differ. `make status` should check and report clearly rather than failing obscurely. |

All five are LOW risk and none gates planning. No assumption in this document concerns a security control, a compliance requirement, or a package identity.

## Open Questions (RESOLVED)

All three questions were closed at planning time (2026-07-21). Each recommendation was adopted; the adopting plan is cited inline.

1. **RESOLVED — Host port 22 mapping strategy (carried from STATE.md / CONTEXT.md Open Concerns)**
   - **Resolution:** Recommendation adopted in full. Plan `01-01` Task 3 publishes no mapping for container port 22 and asserts the published-port list contains only 9090/9091; plan `01-02` Task 2 extends that assertion to 9092. Plan `01-03` Task 2 frames the `client` container as the canonical SSH source in `README.md`, so Phase 3 can route `client -> proxy:22 -> backend:22` entirely inside the Docker network with no host port and no client-side flag. Phase 1 takes no position beyond not foreclosing that path.
   - What we know: Port 22 is **free** on this machine [VERIFIED: `nc -z 127.0.0.1 22` → free; macOS Remote Login is off by default]. Phase 1 ships no `stream` block (D-15) and therefore must not bind it. CONTEXT.md correctly notes that D-02's client container sidesteps the problem entirely for SSH, since it connects over the Docker network and never touches a host port.
   - What's unclear: Whether Phase 3 publishes 22 on the host at all. Publishing `22:22` would collide on any machine with Remote Login enabled; publishing `2222:22` weakens the "no client change" claim because the presenter would type `ssh -p 2222`.
   - Recommendation: **Phase 1 takes no position and binds nothing on 22** — which is already what D-15 requires. Phase 1 should, however, make the `client` container the canonical SSH source in its README and Makefile framing, so Phase 3 can route `client → proxy:22 → backend:22` entirely inside the Docker network with **no host port involved and no client-side flag**. That is the only option that keeps CUT-02's "same commands" claim fully honest, and Phase 1's compose layout (network alias on the proxy) already supports it without change. Add a `127.0.0.1:2222:22` publish in Phase 3 only as an optional convenience for a host-side `ssh`, clearly framed as a secondary path.

2. **RESOLVED — Whether the `$backend_is_valid` guard (Pitfall 3) is in scope for Phase 1**
   - **Resolution:** Recommendation adopted. Plan `01-02` Task 1 places the `$backend_is_valid` map and the `return 503` guard in `proxy/nginx.conf`, deliberately NOT in `active-backend.conf`, so the file the audience reads during the Phase 2 flip stays at five lines. Plan `01-02` Task 2 asserts the guard end-to-end by writing an invalid selector, reloading, confirming a 503 with a legible body, then restoring. Threat `T-01-07` is dispositioned on this mitigation.
   - What we know: The 502-on-typo failure mode is real and verified, and it strikes during Phase 2's live flip — the demo's money shot.
   - What's unclear: It costs ~5 lines in `nginx.conf` and slightly increases what the audience sees when the config is shown on screen.
   - Recommendation: **Include it in Phase 1.** It lives in `nginx.conf`, not in `active-backend.conf`, so the file the audience reads during the flip stays three lines. Adding it later means editing the config that Phase 2 has already rehearsed against.

3. **RESOLVED — Does the `client` container need `openssh-client` in Phase 1?**
   - **Resolution:** Recommendation adopted. Plan `01-01` Task 3 installs `curl` and `openssh-client` in a single `apk add --no-cache` layer in `client/Dockerfile`, on exactly D-18's reasoning — build once, avoid a mid-project rebuild. Phase 1 does not route or demo SSH.
   - What we know: Phase 1 does not demo SSH (D-15). Phase 3 needs it.
   - What's unclear: Whether adding it now is scope creep or prudence.
   - Recommendation: **Add it now**, on exactly the reasoning D-18 already applies to sshd on the backends — build once, avoid a mid-project rebuild. It costs one word in an `apk add` and nothing in Phase 1's demo surface.

## Project Constraints (from CLAUDE.md)

`./.claude/CLAUDE.md` is GSD-generated and restates PROJECT.md. Actionable directives for the planner:

- **Tech stack is fixed:** nginx (with `stream` module) + Docker Compose. Do not introduce another proxy, orchestrator, or web framework.
- **Ports:** HTTP on 9092 (locked by the user), SSH on 22. Phase 1 honours 9092; 22 is Phase 3's.
- **Environment:** entirely local, no cloud account or cost. No plan task may require a registry login, cloud SDK, or paid service.
- **Startup:** one command to bring the whole demo up. Any task that adds a required manual step before `docker compose up` violates this — with the single documented exception of D-03's `/etc/hosts` line, which is a host-OS prerequisite rather than a startup step and must be called out in the README.
- **No project skills** are defined (`.claude/skills/` absent), and Conventions/Architecture sections are empty placeholders — Phase 1 **establishes** the conventions that Phases 2–4 inherit. Naming choices (Makefile targets, file layout, log field names) should therefore be made deliberately, not incidentally.
- **GSD workflow enforcement:** file changes go through a GSD command. This research phase wrote only `.planning/` artifacts and a throwaway rig in the session scratchpad; no project source files were created.

## Sources

### Primary (HIGH confidence)

- **Direct execution on the target machine, 2026-07-21** — a complete four-service rig (proxy + two backends + client) was built and run, and every behavioural claim in this document was observed rather than inferred. Specific verifications:
  - `docker run --rm nginx:{1.29,stable,mainline,latest}-* nginx -V` — `--with-stream` across all variants
  - `docker run --rm --entrypoint sh nginx:1.29-alpine -c 'cat /docker-entrypoint.sh'` — the `$1 = nginx` guard (Pitfall 1)
  - `docker run --rm --entrypoint sh nginx:1.29-alpine -c 'cat /docker-entrypoint.d/20-envsubst-on-templates.sh'` — `NGINX_ENVSUBST_FILTER` and the `*.stream-template` auto-append
  - Shared `map` include exercised from **both** `http` and `stream` blocks — `nginx -t` pass and live traffic
  - `nginx -s reload` after a one-word include edit — OLD → NEW flip observed
  - `nginx -t` with a broken include — traffic continued uninterrupted on the old config
  - `nginx -t` with a typo'd map value — passed, then 502 with `no resolver defined to resolve nwe`
  - `ssh-keygen -lf` on both backends, build-time vs runtime generation — identical vs distinct fingerprints
  - `curl -w '%{url_effective}' -L` on 9092 and 9093 — redirects=0 vs redirects=1
  - Compose network alias vs `extra_hosts: host-gateway` — resolution and source-IP behaviour compared
  - `docker manifest inspect` on all recommended image tags
  - Host port and tooling probes (`nc`, `make --version`, `curl --version`, `/etc/hosts`)
- `.planning/PROJECT.md`, `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md`, `.planning/STATE.md`, `.planning/phases/01-.../01-CONTEXT.md`, `./.claude/CLAUDE.md`, `.planning/config.json` — read in full.

### Secondary (MEDIUM confidence)

- nginx directive semantics for `proxy_pass` with variables, `map` context availability, and `$host` port-exclusion — stated in official nginx documentation and **independently confirmed by execution** in the rig above, which is why they appear as verified claims rather than citations.

### Tertiary (LOW confidence)

- Browser 301 caching behaviour (A1) and s6-overlay explainability (A2) — reasoned, not executed. Both flagged in the Assumptions Log.

No WebSearch was used. Every dependency and behaviour was checkable with tools already present on the machine, in line with the project instruction to check tool availability before searching the web.

## Metadata

**Confidence breakdown:**

| Area | Level | Reason |
|------|-------|--------|
| Standard stack | **HIGH** | Every image pulled, executed, and version-confirmed against its registry. No package-registry dependencies exist, eliminating the main hallucination surface. |
| ENV-04 / stream module | **HIGH** | `nginx -V` run against four image variants; all show `--with-stream`. |
| Architecture (dual-context include) | **HIGH** | The `map`-in-shared-include design was built and exercised from both `http` and `stream` blocks, including a live reload flip. This is the phase's central design risk and it is resolved by demonstration. |
| Backend image / two-process pattern | **HIGH** | Built and run; process table and listening sockets observed. |
| Log format | **HIGH** | Output captured for proxied, redirected, and client-container requests. |
| Pitfalls | **HIGH** | Pitfalls 1–6 and 8–9 were each reproduced or directly observed. Pitfall 7 is reasoned (A1); Pitfall 10 was tested and found *not* to occur here, and is documented as precautionary. |
| Environment availability | **HIGH** | All probes executed on the target machine. |
| Validation architecture | **MEDIUM-HIGH** | Commands are straightforward and derived from verified behaviour, but `scripts/smoke.sh` has not itself been written and run end to end. |
| Security domain | **MEDIUM** | Threat surface is genuinely small and well understood; no dynamic analysis performed, which is proportionate for a loopback-only local demo artifact. |

**Research date:** 2026-07-21
**Valid until:** 2026-08-20 (30 days — nginx and Alpine are stable, slow-moving dependencies; the pinned tags will not drift. Re-verify sooner only if the Docker Desktop major version changes, since Pitfall 6 and Pitfall 10 are Docker-Desktop-specific.)

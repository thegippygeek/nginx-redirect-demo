# Phase 1: Demo Up, HTTP Lands on OLD - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-07-21
**Phase:** 1-Demo Up, HTTP Lands on OLD
**Areas discussed:** What the client types, nginx config shape, Backend container makeup, Presenter command surface

---

## What the client types

### Hostname the audience sees

| Option | Description | Selected |
|--------|-------------|----------|
| Real-looking hostname via /etc/hosts | `app.demo.local` → 127.0.0.1 in the presenter's /etc/hosts; costs one setup step outside Docker | |
| Plain localhost | Zero setup, but weakens the "hostname stayed the same" story | |
| Hostname resolved inside a client container | A `client` container in the compose network resolving the name via Docker DNS; fully self-contained | ✓ |

**User's choice:** Client container.
**Notes:** Raised a follow-up tension — the browser runs on the host and cannot resolve Docker-internal DNS. Resolved below.

### Reconciling client container with browser

| Option | Description | Selected |
|--------|-------------|----------|
| Add the host /etc/hosts line too | Browser and client container use the identical hostname; costs one documented manual step | ✓ |
| Browser uses localhost, container uses the hostname | No setup step, but two different names on stage | |
| Drop the client container, host /etc/hosts only | One client, one name, but loses the self-contained property | |

**User's choice:** Both — client container *and* a host `/etc/hosts` entry.
**Notes:** Consistency of the hostname across both clients was judged worth the one-time setup step.

### Direct backend exposure

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, on separate ports | Presenter can establish "here are two boxes" first; gives the 301 a real Location target | ✓ |
| No, proxy only | Cleaner network story, but the redirect has nowhere to send the client | |

**User's choice:** Expose both backends directly.

### Redirect contrast (HTTP-03/04)

| Option | Description | Selected |
|--------|-------------|----------|
| Second nginx port, `curl -v` side by side | Technical, precise, shows headers | |
| Same port, different path | Fewer ports, but muddies the ":9092 is the migration endpoint" framing | |
| Browser, not curl | URL bar visibly changes on redirect, stays put on proxy — more visceral | ✓ |

**User's choice:** Browser.
**Notes:** `curl -v` retained as a technical backup view; separate port kept (not a path) to preserve the 9092 framing.

### Backend identity signal (BACK-03)

| Option | Description | Selected |
|--------|-------------|----------|
| Big visual page + response header | Colour-coded OLD/NEW banner with hostname, plus `X-Backend` header | ✓ |
| Plain text only | Trivial to build, flat in a browser | |
| Header only | Clean for scripts, invisible to a non-technical audience | |

**User's choice:** Both signals.

---

## nginx config shape

### Config organisation

| Option | Description | Selected |
|--------|-------------|----------|
| Single included active-backend.conf | One tiny file holding the upstream target; the flip is a one-line edit visible in full on screen | ✓ |
| Monolithic nginx.conf | Fewer files, but the diff is buried in a large file | |
| Two complete config sets | Very visual, but "only the upstream moved" is harder to prove | |

**User's choice:** Included `active-backend.conf`.

### Reload mechanism

| Option | Description | Selected |
|--------|-------------|----------|
| `nginx -s reload` in the running container | Graceful, drains connections, mirrors production; implicitly makes the zero-downtime point | ✓ |
| Restart the proxy container | Simpler, but drops connections and undercuts seamlessness | |
| Auto-reload on file change | Slicker, but adds a moving part and hides the step the audience should see | |

**User's choice:** Graceful `nginx -s reload`.

### Stream block timing

| Option | Description | Selected |
|--------|-------------|----------|
| Structure now, wire up in Phase 3 | Lays out config layout so Phase 3 only fills in the block | |
| Full stream block in Phase 1 | Fewer surprises later, but bleeds Phase 3 scope into Phase 1 | |
| Nothing until Phase 3 | Cleanest phase boundary; small risk of restructuring later | ✓ |

**User's choice:** Nothing until Phase 3.
**Notes:** ENV-04 still satisfied in Phase 1 by proving the module is compiled in via `nginx -V`, which constrains the base image choice.

---

## Backend container makeup

### Build strategy

| Option | Description | Selected |
|--------|-------------|----------|
| One Dockerfile, two instances via env var | Provably identical boxes differing only in identity | ✓ |
| Two separate Dockerfiles | Easier to eyeball, but duplication invites drift | |
| Off-the-shelf image + mounted content | No build step, but SSH needs a second container per backend | |

**User's choice:** One Dockerfile, `BACKEND_ID` env var.

### Web and SSH co-location

| Option | Description | Selected |
|--------|-------------|----------|
| Same container (web + sshd) | Matches "one server running both services"; suits the Phase 4 host-key story. Needs a small supervisor | ✓ |
| Separate containers per backend | Cleaner one-process-per-container practice, but breaks the "this is one server" illusion | |

**User's choice:** Same container.
**Notes:** Two-processes-in-one-container trade-off explicitly accepted for narrative fidelity.

### sshd scope in Phase 1

| Option | Description | Selected |
|--------|-------------|----------|
| Yes, build it in now | BACK-01/02 say backends accept SSH; avoids an image rebuild in Phase 3 | ✓ |
| HTTP only, add sshd in Phase 3 | Strictly minimal, but BACK-01/02 wouldn't fully pass in Phase 1 | |

**User's choice:** Build sshd in now, route and demo it in Phase 3.

---

## Presenter command surface

### Interface

| Option | Description | Selected |
|--------|-------------|----------|
| Makefile wrapper | `make up` / `status` / `flip` / `reset` — short, memorable, hard to fumble live | ✓ |
| Raw docker compose only | Verbatim reproducible, but long commands | |
| Shell scripts in ./scripts | Same benefit, more portable, more files | |

**User's choice:** Makefile.

### ENV-01 literalness

| Option | Description | Selected |
|--------|-------------|----------|
| Both must work | Raw `docker compose up` works standalone; `make up` is convenience only | ✓ |
| Wrapper is the documented path | `make up` advertised; raw compose works but isn't the story | |

**User's choice:** Both must work — nothing essential hidden behind `make`.

### Reset semantics (ENV-02)

| Option | Description | Selected |
|--------|-------------|----------|
| Full teardown + rebuild | `docker compose down -v` plus restoring the include to OLD; identical clean state guaranteed | ✓ |
| Config-only reset | Instant between takes, but drifted state survives | |
| Both, as separate commands | Covers both cases | |

**User's choice:** Full teardown + rebuild.
**Notes:** The fast config-only flip-back was recognised as useful but assigned to Phase 2 (CUT-05) rather than Phase 1.

---

## Claude's Discretion

- Proxy base image, constrained by the `stream`-module requirement
- Backend base image and process supervisor for running web + sshd together
- Exact port numbers for direct backend access and the redirect listener (9092 is fixed)
- nginx log format — must expose the serving upstream, since Phase 2's EVID-01 depends on it
- Health check definitions and how "came up healthy" is verified
- Repository file and directory layout

## Deferred Ideas

- Config-only fast flip-back for back-to-back demo takes → Phase 2 (CUT-05)
- `make flip` target → Phase 2
- `stream` block for SSH → Phase 3
- SSH host-key generation and mismatch staging → Phase 4

---
phase: 01-demo-up-http-lands-on-old
verified: 2026-07-21T06:55:00Z
status: verified
score: 5/5 must-haves verified
behavior_unverified: 0
overrides_applied: 0
re_verification:
  previous_status: none
  previous_score: n/a
  gaps_closed: []
  gaps_remaining: []
  regressions: []
human_verification:
  - test: "Browser side-by-side at `app.demo.test`: 9092 proxied vs 9093 redirected, plus cross-room legibility of the OLD/NEW banners."
    expected: "9092 shows the amber OLD banner with the URL bar still reading `app.demo.test:9092`; 9093 shows the same OLD banner but the URL bar has visibly changed to `app.demo.test:9090`."
    why_human: "D-07 makes the browser URL bar the PRIMARY proof for HTTP-04, and a URL bar is not observable from the CLI."
    resolved: 2026-07-21
    result: PASS
    resolution_note: "The stale `127.0.0.1  app.demo.local` line (superseded by D-22) was removed from /etc/hosts and `127.0.0.1  app.demo.test` added. Resolution then measured at 0.03s (down from the 5.03s mDNS stall). Re-confirmed from the CLI at the real hostname: 9092 -> redirects=0, final URL identical to requested; 9093 -> redirects=1, final `http://app.demo.test:9090/whoami`. `make status` reports `hosts: OK`. The human then ran the incognito browser pass covering the URL-bar contrast and the cross-room OLD/NEW legibility check (colour covered, word alone carrying the signal) and reported all steps passing."
---

# Phase 1: Demo Up, HTTP Lands on OLD — Verification Report

**Phase Goal:** Presenter runs one command and can immediately show a browser/curl hitting nginx on port 9092, landing on `server-old`, with the URL unchanged — and show the redirect approach alongside it changing the URL
**Verified:** 2026-07-21T06:55:00Z
**Status:** verified (all five roadmap success criteria mechanically verified; the outstanding D-07 browser confirmation was resolved on 2026-07-21 — see `human_verification` in the frontmatter)
**Re-verification:** No — initial verification

All evidence below was produced by running commands against the live stack and against a cold `docker compose down -v` → `up` cycle in this verification session. No SUMMARY.md claim was accepted without independent execution.

## Goal Achievement

### Observable Truths (ROADMAP Success Criteria)

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | `docker compose up` brings nginx + both backends up healthy, no cloud account/credentials/prior setup | VERIFIED | Ran `docker compose down -v` (residue check: 0 containers, 0 volumes, 0 networks), then raw `docker compose up -d --wait` with no `make`: exit 0 in **7.9s**, all four services reported `Healthy` by Compose, `server-old`/`server-new` `(healthy)` via their own `/healthz` healthchecks. No `docker login`, no `.env`, no credential file anywhere in the repo. |
| 2 | Request to 9092 returns a body naming the backend as OLD with its hostname, URL unchanged | VERIFIED | `curl -i http://localhost:9092/whoami` → `200`, body `OLD server-old`, headers `X-Backend: OLD` / `X-Backend-Host: server-old`. `curl -sSL -w '%{url_effective} %{num_redirects}'` → `http://localhost:9092/whoami 0`. Via the real hostname: `docker compose exec client curl http://app.demo.test:9092/whoami` → `OLD server-old`. |
| 3 | Redirect port returns 3xx with `Location`; following it ends on a different URL; contrast showable side by side | VERIFIED | `curl -i http://localhost:9093/whoami` → `301 Moved Permanently`, `Location: http://app.demo.test:9090/whoami`. Followed: `final=http://app.demo.test:9090/whoami redirects=1` vs 9092's `final=http://localhost:9092/whoami redirects=0`. `make contrast` prints both labelled lines in one command. (Browser half → human item.) |
| 4 | One teardown command returns the demo to an identical clean state | VERIFIED | `docker compose down -v` in 4.0s left zero containers/volumes/networks. `make reset` (down -v + include restore + rebuild + wait) completed in **13.4s** and left `proxy/active-backend.conf` at SHA `9b57265…`, byte-identical to its pre-run state. Full smoke suite green immediately after. |
| 5 | `nginx -V` inside the proxy shows the `stream` module compiled in | VERIFIED | `docker compose exec proxy nginx -V` → nginx/1.30.4 with `--with-stream`, `--with-stream_realip_module`, `--with-stream_ssl_module`, `--with-stream_ssl_preread_module`. |

**Score:** 5/5 truths verified (0 present, behavior-unverified)

### Cross-Phase Responsibilities (Phase 1 owns; Phases 2/4 silently depend)

| # | Responsibility | Status | Evidence |
|---|----------------|--------|----------|
| A | Log format exposes the serving backend (Phase 2 EVID-01) | VERIFIED | Live proxy log: `172.19.0.1 -> localhost:9092 "GET /whoami HTTP/1.1" 200 upstream=172.19.0.2:80 backend=OLD rt=0.001 urt=0.000`. Value comes from `$upstream_http_x_backend` — the backend's own header, not a proxy assertion. |
| B | `X-Backend` response header present (D-11) | VERIFIED | `X-Backend: OLD` on 9090 direct and on 9092 through the proxy; `X-Backend: NEW` on 9091. |
| C | SSH host keys DIFFER between backends (Phase 4 KEY-01) | VERIFIED | `server-old` ED25519 `SHA256:vyrUJhu6…`, `server-new` `SHA256:RdRQIQf/…` — distinct. Generated by `ssh-keygen -A` in `backend/entrypoint.sh` at container start; confirmed no `ssh-keygen` in any Dockerfile RUN layer. |
| D | No `stream` block and no published port 22 (D-15) | VERIFIED | `nginx -T` inside the proxy shows no `stream {` block loaded (the only `stream` hits in the config are `upstream`/`$upstream_addr` substrings and the commented Phase-3 sketch). `docker compose ps` shows no `:22->` binding. |
| E | `proxy/active-backend.conf` is the small annotated include, restored intact by `make reset` (D-12 + D-21) | VERIFIED | File is 5 lines: 2 presenter-facing comments + a 3-line `map`. Extracted the exact `make reset` printf recipe via `make -n`, ran it into a scratch file, `diff` against the live file → **byte-identical**, comment lines included. Confirmed again by hash after two real `make reset` runs. |
| F | Supervisord keeps both processes alive without a container restart (D-17, BACK-01/02 concurrency edge) | VERIFIED (behavioral) | Killed nginx master in `server-old` (PID 13 → respawned as 300); `/healthz` still `200`. Killed sshd (PID 14 → respawned as 394); `nc -z localhost 22` succeeded again. Container uptime unbroken (`Up 2 minutes` throughout) — no compose restart occurred. |

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `compose.yaml` | The whole rig, one command | VERIFIED | 4 services, one shared `demo-backend:1` image for both backends, `depends_on: service_healthy` gates on the proxy, `aliases: [app.demo.test]`, all ports bound `127.0.0.1` only. Exercised end to end. |
| `Makefile` | Presenter command surface (D-19) | VERIFIED | `up/down/status/logs/test/reset/contrast/reload/check` all present and parse under Make 3.81. `reset`, `contrast`, `status`, `test` executed successfully this session. |
| `proxy/nginx.conf` | Upstreams, log format, 9092 proxy, 9093 redirect | VERIFIED | Loaded and serving; `nginx -t` passes; no `add_header` (identity is never proxy-synthesized). |
| `proxy/active-backend.conf` | 5-line flip include | VERIFIED | Wired into `nginx.conf` via `include`; drives `proxy_pass http://$active_backend`. |
| `backend/Dockerfile` + `entrypoint.sh` + `supervisord.conf` + templates | One image, two identities | VERIFIED | Both services resolve to image ID `7cd9936c52ac…`; `/whoami` returns `OLD server-old` / `NEW server-new`; banners render `<h1>OLD</h1>` / `<h1>NEW</h1>`. |
| `client/Dockerfile` | In-network command source | VERIFIED | Container resolves `app.demo.test` via Docker DNS and reaches the proxy. |
| `scripts/smoke.sh` | Every mechanically checkable requirement | VERIFIED | 42 assertions, **42 passed / 0 failed**, run three times (warm, post-cold-start, post-reset). Runtime 8.2s warm. |
| `README.md` | Presenter entry point | VERIFIED | Contains the `/etc/hosts` prerequisite with exact command, the incognito/301-caching warning, the four-port table + mnemonic, the standalone `docker compose up` statement (D-20), the explicit HTTP-02 URL-invariance contract with the macOS SNAT rationale, and the ENV-03 no-cloud section. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| `compose.yaml` `BACKEND_ID` | banner + `X-Backend` | `entrypoint.sh` envsubst | WIRED | One env var drives both identity signals; verified live on both backends. |
| `active-backend.conf` `$active_backend` | `nginx.conf` `proxy_pass` | `include` | WIRED | Flip selector reaches the proxy; a corrupted value produces the intended 503. |
| backend `add_header X-Backend` | proxy `backend=` log field | `$upstream_http_x_backend` | WIRED | Confirmed in the live access log. |
| compose `aliases: [app.demo.test]` | client container | Docker embedded DNS | WIRED | `exec client curl http://app.demo.test:9092/whoami` → `OLD server-old`. |
| backend healthchecks | proxy `depends_on` | `condition: service_healthy` | WIRED | Cold start ordering observed: both backends `Healthy` before `demo-proxy-1 Starting`. |
| 9093 `return 301` | published `server-old:9090` | literal `app.demo.test:9090$request_uri` | WIRED | Redirect target reachable; `curl -L --resolve` lands on `OLD server-old`. |

### Behavioral Spot-Checks

| Behavior | Command | Result | Status |
|----------|---------|--------|--------|
| Cold start from zero | `docker compose down -v` then `docker compose up -d --wait` | exit 0, 7.9s, all Healthy, no residue | PASS |
| Full reset cycle | `make reset` | exit 0, 13.4s, include SHA unchanged | PASS |
| Full smoke suite | `sh scripts/smoke.sh` | 42 passed, 0 failed (x3 runs) | PASS |
| Proxied identity | `curl -i localhost:9092/whoami` | `200`, `OLD server-old`, `X-Backend: OLD` | PASS |
| Redirect contrast | `make contrast` | `redirects=0` vs `redirects=1`, different final URLs | PASS |
| Stream module | `docker compose exec proxy nginx -V` | `--with-stream` present | PASS |
| Invalid-selector guard | smoke `guard_check` | `503` naming `nwe`, then restored to `200` | PASS |
| supervisord autorestart | `kill -9` nginx and sshd in `server-old` | both respawned, service restored, container not restarted | PASS |
| Empty-identity edge | `docker run -e BACKEND_ID= …` | entrypoint exits non-zero, no page served | PASS |
| Distinct host keys | `ssh-keygen -lf` on both backends | fingerprints differ | PASS |

### Probe Execution

No `scripts/*/tests/probe-*.sh` convention in this repo; `scripts/smoke.sh` is the phase's declared runnable check and was executed three times (see above). Not applicable otherwise.

### Requirements Coverage

| Requirement | Description | Status | Evidence |
|-------------|-------------|--------|----------|
| ENV-01 | Single `docker compose up` | SATISFIED | Raw `docker compose up -d --wait` from a torn-down state, no `make`, exit 0 |
| ENV-02 | Single teardown → clean start | SATISFIED | `docker compose down -v` (zero residue) and `make reset` (13.4s, include byte-identical) |
| ENV-03 | No cloud account, credentials or cost | SATISFIED (human-verified) | Absence claim; inspected at the 01-03 checkpoint and user-approved. Independently corroborated: no `.env`, no registry auth, no cloud SDK, only Docker Official Images, only credential is `demo:demo` on an unpublished port 22 |
| ENV-04 | nginx includes `stream` module | SATISFIED | `nginx -V` → `--with-stream` |
| BACK-01 | `server-old` serves HTTP, accepts SSH | SATISFIED | `/healthz` 200 on 9090; `nc -z localhost 22` inside the container |
| BACK-02 | `server-new` serves HTTP, accepts SSH | SATISFIED | `/healthz` 200 on 9091; `nc -z localhost 22` inside the container |
| BACK-03 | Body states identity + hostname | SATISFIED | `OLD server-old` / `NEW server-new`, anchored; banner + header carry the same word |
| HTTP-01 | Reach active backend via nginx on 9092 | SATISFIED | `OLD server-old` through 9092 from both host and client container |
| HTTP-02 | Transparent forwarding, client unchanged | SATISFIED | Verified as URL invariance (`num_redirects=0`, `url_effective` identical, log records `app.demo.test:9092`). The source-IP reading is unsatisfiable on macOS Docker Desktop (SNAT to `192.168.65.1`) and README documents this contract explicitly — confirmed present |
| HTTP-03 | Separate port demonstrates 301 with `Location` | SATISFIED | `301` + `Location: http://app.demo.test:9090/whoami`, literal target, path preserved |
| HTTP-04 | Side-by-side proxied vs redirected URL | SATISFIED (CLI) / human item (browser) | `make contrast` proves it one line at a time; D-07's browser URL-bar path is the outstanding human confirmation |

No orphaned requirements: all 11 requirements ROADMAP maps to Phase 1 are claimed by a plan and verified above.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| — | — | — | — | None. Scan for `TODO`/`FIXME`/`XXX`/`TBD`/`HACK`/`PLACEHOLDER`/"not yet implemented"/"coming soon" across `Makefile`, `compose.yaml`, `README.md`, `scripts/`, `proxy/`, `backend/`, `client/` returned zero matches. No stubs, no empty handlers, no hardcoded-empty data. |

### Prohibition Checks (must-NOT)

| Requirement | Prohibition | Status | Evidence |
|-------------|-------------|--------|----------|
| BACK-03 | Must not rely on colour alone | UPHELD | The literal word appears in the `<h1>` banner, the `/whoami` body, and the `X-Backend` header, independent of `BACKEND_COLOR` |
| BACK-01 | No vendor-specific naming in the artifact | UPHELD | Grep for `aws|nutanix|azure|gcp|vmware|hyper-v|proxmox` across all source returned zero matches (the enclosing directory name is repo metadata, not artifact content) |
| HTTP-01 | Proxy must not synthesize backend identity | UPHELD | Zero non-comment `add_header` in `proxy/nginx.conf`; the `backend=` log field is `$upstream_http_x_backend`, read from the observed response |
| ENV-03 | Must not modify host state automatically | UPHELD | The only `/etc/hosts` contact in the repo is a read-only `grep -q` in `make status`; the `sudo` string appears solely as printed remediation text and in README prose. Nothing executes it. Verified independently: `/etc/hosts` was not modified by any command run in this session |

### Human Verification Required

**1. Browser side-by-side at the current hostname (D-07 / HTTP-04 primary path)**

**Test:** Add the D-03 entry for the hostname D-22 actually settled on:
```bash
echo '127.0.0.1  app.demo.test' | sudo tee -a /etc/hosts
```
Then in an incognito window, open `http://app.demo.test:9092/` and `http://app.demo.test:9093/` side by side.

**Expected:** 9092 shows the amber OLD banner with the URL bar still reading `app.demo.test:9092`. 9093 shows the same OLD banner but the URL bar has visibly changed to `app.demo.test:9090`.

**Why human:** A URL bar is not observable from the CLI, and D-07 designates it the primary proof for HTTP-04.

**Why this is being raised despite the 01-03 checkpoint sign-off:** this machine's `/etc/hosts` currently contains `127.0.0.1  app.demo.local` (line 72) and **no** `app.demo.test` entry. `.local` is the hostname D-22 explicitly superseded. The 01-03 SUMMARY records the browser check as passing at `app.demo.test`, but that state does not exist on this host, so the check cannot be corroborated or re-run as written. `make status` correctly reports `hosts: MISSING` with the exact fix line — the repository behaves correctly; only the host prerequisite is stale.

**Suggested cleanup:** remove the obsolete `app.demo.local` line while adding the `.test` one, so a fumbled hostname on stage cannot silently resolve to a 5-second mDNS stall (the exact failure D-22 documents).

### Observations (not gaps)

- **Proxy container has no `healthcheck`.** Under `docker compose up --wait` Compose reports a healthcheck-less container as `Healthy` once it is running, so SC1 passes as written and a crash-on-start would still fail the `--wait`. The smoke suite independently proves the proxy is serving. Noted only because Phase 2's flip/reload work will lean on proxy readiness — a `healthcheck` on the proxy would make `--wait` a stronger gate.
- **SC1's "no prior setup" vs D-03's `/etc/hosts` step.** The one-time host entry is a locked, human-approved decision (D-03) and is required only for the browser path; every automated check passes without it, and README states this scoping explicitly. Recorded as an accepted design characteristic, not a deviation.
- **`make status`'s hosts grep uses unescaped dots** (`grep -q 'app.demo.test' /etc/hosts`). Harmless today — it correctly did *not* match the `app.demo.local` line present on this machine — but the dots are regex wildcards. Cosmetic.
- **D-13 forward-compatibility holds.** `active-backend.conf` uses `map $server_port $active_backend`, and both `map` and `$server_port` exist in nginx's `stream` context, so Phase 3 can include the same file unchanged as the commented sketch in `nginx.conf` describes.

### Gaps Summary

None. All five roadmap success criteria are independently reproduced against the live stack, including the full cold-start and reset cycles, and all six cross-phase responsibilities that Phases 2 and 4 depend on are verified. The single outstanding item is a human confirmation of the browser URL-bar contrast at the post-D-22 hostname — a host-machine prerequisite, not a codebase defect.

The working tree is clean and the stack was left running, reset, and green (42/42) at the end of verification.

---

_Verified: 2026-07-21T06:55:00Z_
_Verifier: Claude (gsd-verifier)_

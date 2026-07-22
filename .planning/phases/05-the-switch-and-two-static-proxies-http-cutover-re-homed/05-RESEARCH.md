# Phase 5: The Switch and Two Static Proxies — HTTP Cutover Re-Homed - Research

**Researched:** 2026-07-22
**Domain:** Docker Compose topology restructure; nginx multi-hop reverse proxy; evidence-log re-sourcing
**Confidence:** HIGH (mechanism proven in v1; all net-new nginx behaviours verified empirically against the exact pinned `nginx:1.30.4-alpine`)

## Summary

This is a **brownfield restructure**, not new-mechanism research. v1 already ships and is verified: the map-flip + `nginx -s reload` cutover, the JSON evidence log, the stateless status service, the `:8081` reload oracle, and the `app.demo.test` embedded-DNS alias all work today in `proxy/`. Phase 5 re-shapes the *topology* around that proven mechanism: v1's single flip-in-place `proxy` splits into a three-tier blue-green shape — one front `switch` (the client's only endpoint, holding the flip surface and the evidence log) in front of two **static** single-upstream proxies (`proxy-old`→`server-old`, `proxy-new`→`server-new`).

The single genuinely new correctness surface is **evidence through two hops**: the switch must log the client's real `remote_addr` while the backend's own `X-Backend`/`X-Backend-Host` identity headers propagate untouched back up the chain so `backend=OLD/NEW` stays the backend's own assertion. I verified this empirically (see Code Examples): a custom `X-Backend` response header survives both hops with zero special config, and `$upstream_http_x_backend` at the switch reads the backend's value because nginx forwards upstream response headers by default and each `$upstream_http_*` reads the immediate upstream's response. The static proxies stay transparent **only if they add no identity header of their own** — that is the one integrity discipline to enforce and test.

The bulk of the work is mechanical and low-risk: (1) three nginx configs from one, (2) a compose health-gate cascade one level deeper, and (3) a large but rote rename of the evidence/reload/oracle operations from the `proxy` service to the `switch` service across the Makefile, `flip.sh`, `status.py`, and — the big one — ~128 `proxy` references in `scripts/smoke.sh` (the Nyquist harness). One net-new UI touch: `remote_addr` must be added to the evidence JSON and surfaced on the status page to satisfy EV2-01 / criterion 3 (hence *UI hint: yes*).

**Primary recommendation:** Reuse the stock `nginx:1.30-alpine` image for all three proxy tiers (no Dockerfiles — mount configs, exactly as v1's `proxy` does). Create `switch/`, `proxy-old/`, `proxy-new/`; leave `proxy/` in the tree untouched for Phase 7 to formalize. Configure the static proxies **fully (HTTP + SSH stream) now** so "never reconfigured" is literally true from birth. Gate `switch` → `proxy-old`+`proxy-new` (healthy) → backends. Add `remote` to the switch's evidence JSON. Re-point every `proxy`-service operation to `switch`.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Client's single endpoint (9092, later 22) | `switch` | — | SW-01: the client must see one unchanged endpoint; the switch inherits `app.demo.test` |
| Flip surface (`default old`→`new` + reload) | `switch` | — | SW-02/SW-04: the switch holds `active-proxy.conf`; identical mechanism to v1 |
| Evidence log (JSON + `demo` stdout) | `switch` | — | EV2-01: only the front tier sees the client's real `remote_addr` |
| Backend identity (`X-Backend`) | `server-old`/`server-new` | — | EV2-02: identity is the backend's own header, asserted by no proxy tier |
| Static HTTP forward to a fixed backend | `proxy-old`/`proxy-new` | — | PROX-01/02: single-upstream, never reconfigured |
| Direct-reach alias (`app-old`/`app-new.demo.test`) | `proxy-old`/`proxy-new` | — | PROX-03: distinct aliases; Phase 6 validates through them |
| 301 redirect contrast (9093) | `switch` | — | Client-facing contrast surface belongs on the client's endpoint |
| Reload oracle + health listener (8081) | `switch` (+ each static proxy has its own health listener) | — | Switch owns the oracle (it reloads); each proxy needs a health endpoint for compose gating |
| Status/evidence rendering | `status` | — | Unchanged; re-pointed to probe `switch:8081` and read the switch's log |

## Standard Stack

No new packages. The entire phase is config + compose + shell edits on the existing pinned images.

### Core
| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| `nginx:1.30-alpine` | 1.30.4 `[VERIFIED: docker run nginx:1.30-alpine nginx -v]` | switch + both static proxies (stock image, mounted config) | Already the one pinned nginx across the whole rig — "one version to explain on stage" |
| `python:3.13-alpine` | 3.13 (unchanged) | status service | Unchanged; stdlib-only, re-pointed via env/mount |
| Docker Compose | v2 (`name:`, no `version:` key) | the rig | Already the project's substrate |

### Supporting (facts the plan relies on)
| Fact | Verified | Use |
|------|----------|-----|
| `curl` present in stock `nginx:1.30-alpine` | `curl 8.21.0` `[VERIFIED: docker run]` | Static proxies use the same `curl -fsS http://localhost:8081/...` healthcheck idiom as v1's `proxy` — no `apk add`, no build |
| `--with-stream` compiled in | `[VERIFIED: nginx -V]` (also `--with-stream_ssl_preread_module`) | Static proxies can carry their SSH `stream` block now |
| Custom response headers pass through untouched | `[VERIFIED: 2-hop docker test]` | `X-Backend`/`X-Backend-Host` reach the switch and the client through both hops |
| `$upstream_http_x_backend` reads immediate-upstream response | `[VERIFIED: switch log line]` | Switch's `backend=` field carries the backend's own value across two hops |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Stock image + mounted config (3 tiers) | A Dockerfile per proxy tier | Adds build steps to `make up` for zero benefit; v1 deliberately mounts config into stock nginx. **Reject.** |
| One nginx image, three mounted configs | One shared config with `map`-selected everything | The whole point is three *distinct* configs (one flippable switch, two frozen proxies) — VAL-04 later needs the static configs provably unchanged. **Keep them separate files.** |
| Static proxies configured HTTP-only in Phase 5, SSH added in Phase 6 | Configure HTTP + SSH stream now | Deferring SSH means Phase 6 re-edits the "never reconfigured" proxies, weakening PROX-01/02. **Configure fully now** (SSH block is inert until Phase 6 wires the switch's stream). |

**Installation:** none. `docker compose up -d --build --wait` (the backend image still builds; the three nginx tiers are `image:`-only).

## Package Legitimacy Audit

**Not applicable.** Phase 5 installs no external packages. All images (`nginx:1.30-alpine`, `python:3.13-alpine`, the `demo-backend:1` build) are already in the shipped v1 rig and pinned. No npm/PyPI/crates dependency is added. No `postinstall` surface exists.

## Architecture Patterns

### System Architecture Diagram

```
                 flip surface: switch/active-proxy.conf  (map default old->new)
                                        │
                                        ▼
 client ──HTTP 9092──▶  ┌─────────────────────────────┐        proxy_pass http://$active_proxy
 (app.demo.test,        │  switch  (alias app.demo.test)│──old──▶ proxy-old ──▶ server-old:80
  the ONLY endpoint)    │  · 9092 proxy  · 9093 redirect│         (alias         (X-Backend: OLD)
                        │  · 8081 health + reload oracle│          app-old.demo.test)
                        │  · WRITES demo-logs evidence  │──new──▶ proxy-new ──▶ server-new:80
                        └───────────────┬───────────────┘         (alias         (X-Backend: NEW)
                                        │                          app-new.demo.test)
                        $remote_addr = real client          each: transparent, single-upstream,
                        $upstream_http_x_backend = backend's        emits NO identity header,
                        own header (survives 2 hops)                own :8081 health listener
                                        │
                     demo-logs volume (access.log, JSON) ── :ro ──▶ status  (probes switch:8081)
```

Trace the primary case: client hits `app.demo.test:9092` → switch selects `old` via the map → `proxy_pass` to `proxy-old` → `proxy-old` forwards to `server-old:80` → `server-old` answers `OLD server-old` with `X-Backend: OLD` → that header rides back up through `proxy-old` (untouched) to the switch → switch logs `remote=<client>`, `backend=OLD` to the evidence file → status reads it.

### Recommended Project Structure
```
switch/
├── nginx.conf          # was proxy/nginx.conf: upstreams point at proxy-old/proxy-new;
│                       #   http block only in Phase 5 (stream block lands in Phase 6, SW-03)
└── active-proxy.conf   # was proxy/active-backend.conf: map ...{ default old; }  (the ONLY edited file)
proxy-old/
└── nginx.conf          # static: proxy_pass to server-old:80 (+ SSH stream :22 -> server-old:22); :8081 health
proxy-new/
└── nginx.conf          # static: proxy_pass to server-new:80 (+ SSH stream :22 -> server-new:22); :8081 health
proxy/                  # LEFT UNTOUCHED — v1 form; Phase 7 (MIG-03) decides preservation strategy
status/status.py        # env defaults re-pointed: probe switch:8081, read active-proxy.conf; render remote_addr
compose.yaml            # proxy service -> switch + proxy-old + proxy-new; health cascade; alias moves to switch
Makefile, scripts/*.sh  # every `exec proxy` / `logs proxy` -> switch; CONF path -> switch/active-proxy.conf
```

### Pattern 1: Static single-upstream transparent proxy (proxy-old / proxy-new)
**What:** A frozen nginx that forwards one fixed backend and asserts nothing about identity.
**When to use:** Both static proxies.
```nginx
# Source: verified 2-hop test (scratchpad) — passes X-Backend through untouched
events { worker_connections 1024; }
http {
    upstream backend { server server-old:80; }         # proxy-new: server-new:80
    server {
        listen 80;
        location / {
            proxy_pass http://backend;
            proxy_set_header Host            $host;
            proxy_set_header X-Real-IP       $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            # NO add_header X-Backend here — the backend owns identity (EV2-02 integrity)
        }
    }
    server {                                            # compose healthcheck target
        listen 8081;
        access_log off;
        location = /nginx-health { return 200 "ok\n"; }
    }
}
stream {                                                # inert in Phase 5, wired by the switch in Phase 6
    upstream ssh { server server-old:22; }              # proxy-new: server-new:22
    server { listen 22; proxy_pass ssh; }
}
```

### Pattern 2: Switch = v1's proxy with upstreams re-pointed at the proxies
**What:** The front tier is v1's `proxy/nginx.conf` almost verbatim, with three edits.
```nginx
upstream old { server proxy-old:80; }   # was server-old:80
upstream new { server proxy-new:80; }   # was server-new:80
include /etc/nginx/demo/active-proxy.conf;   # was active-backend.conf; still: map ...{ default old; }

log_format evidence escape=json
    '{"t":"$time_iso8601","ms":"$msec","remote":"$remote_addr",'   # <-- ADD remote (EV2-01)
    '"path":"$uri","req":"$request_uri","status":$status,'
    '"backend":"$upstream_http_x_backend","bhost":"$upstream_http_x_backend_host",'
    '"upstream":"$upstream_addr","host":"$host","port":"$server_port"}';
# 9092 proxy_pass http://$active_proxy;  9093 literal redirect (unchanged);  8081 health + /active-proxy oracle
```
**When to use:** `switch/nginx.conf`. Keep the `$backend_is_valid`→503 guard, the 9093 literal redirect, and the `:8081` oracle (renamed to report `$active_proxy`). Phase 5 ships **no stream block on the switch** (mirrors v1 Phase 1; SW-03 adds it in Phase 6).

### Anti-Patterns to Avoid
- **A static proxy emitting its own `X-Backend`:** corrupts the evidence chain — the demo would then assert an identity a proxy invented. Verified there is exactly one `X-Backend` through a transparent proxy; keep it that way and assert it.
- **`proxy_pass http://$active_proxy/` with a trailing slash:** rewrites the URI. v1 already documents this; carry the no-trailing-slash rule forward.
- **Deriving the 9093 redirect target from `$host`:** open-redirect surface (T-01-13). Keep it the literal `http://app.demo.test:9090$request_uri`.
- **Single-file bind mount of `active-proxy.conf`:** an editor inode-replace strands the mount on stale content. Mount the `switch/` **directory** (v1's Pitfall 10, already load-bearing).
- **Gating the switch's flip on the backends instead of the proxies:** the switch parses `upstream old { server proxy-old; }` on every reload — its flip gate must confirm `proxy-old`/`proxy-new` are reachable, not (only) the backends.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Passing the backend's identity up two hops | Custom header-copy logic / `proxy_set_header` gymnastics | nginx's default upstream-response-header pass-through | Verified: `X-Backend` survives both hops with zero config; `$upstream_http_x_backend` reads it |
| Static-proxy health for compose gating | A shell/exec probe script | An unpublished `:8081 { location=/nginx-health return 200 }` + `curl` healthcheck | curl is in the stock image; identical to v1's proven `proxy` health pattern |
| Startup ordering across 3 tiers | `sleep`/retry wrappers | `depends_on: {condition: service_healthy}` cascade | nginx aborts parse on unresolvable upstream; the health cascade is the load-bearing fix (v1 Pitfall 4) |
| Selector value read by the status page | New parser for a new file format | Keep `map ...{ default old; }` shape in `active-proxy.conf` | `status.py:read_config` already parses exactly this; no code change to the parser |

**Key insight:** Almost nothing here is new engineering. The mechanism, the health-gate idiom, the evidence format, and the DNS-alias approach are all proven in v1. The risk is entirely in the *rename fan-out* and the *one added evidence field*, not in any nginx capability.

## Runtime State Inventory

This is a restructure of a shipped rig. Explicit inventory of state that a file-only grep would miss:

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| **Stored data** | `demo-logs` named volume holds the evidence `access.log`. In v1 it is **written by the `proxy` service**; in v2 it must be **written by `switch`**. Data is ephemeral — `make up` truncates it — so **no data migration**, only a change of which container writes it. `demo-keys` volume: unchanged (backends still own SSH keys; no rename). | Code edit only: switch mounts `demo-logs:/var/log/demo` (rw); truncation commands re-pointed to `exec switch`. No volume rename, no data migration. |
| **Live service config** | None external. Every config lives in git (compose + mounted nginx confs). No n8n/Datadog/Cloudflare/UI-held state. | None — verified: no external service holds topology config. |
| **OS-registered state** | None. No Task Scheduler / systemd / launchd / pm2. The rig is pure `docker compose`. | None — verified: no OS registration. |
| **Secrets / env vars** | `status.py` module-level defaults name the old service/file: `DEMO_PROXY_PROBE=http://proxy:8081/nginx-health` and `DEMO_CONF_PATH=/etc/nginx/demo/active-backend.conf`. These are code defaults, not secrets; they **break silently** if the service is renamed and the file is renamed unless updated (via compose `environment:` override and/or editing the defaults). No secret keys involved. | Code edit: set `DEMO_PROXY_PROBE=http://switch:8081/nginx-health` and point `DEMO_CONF_PATH` at the mounted `active-proxy.conf`; mount `./switch` in the status service instead of `./proxy`. |
| **Build artifacts / installed packages** | None stale. The three nginx tiers are `image:`-only (no build → no cached artifact). `demo-backend:1` image is unchanged. No egg-info, no compiled binary, no global install. | None — verified: nothing to reinstall. |

**The canonical question answered:** after every file is renamed, the only runtime carrier of "proxy" is the **compose service name** and the strings that reference it — the `demo-logs` volume itself is name-neutral and truncated each `up`. There is **no persistent stored state keyed on the string "proxy"** that survives a rebuild. This is a clean rename with no data-migration task.

## Common Pitfalls

### Pitfall 1: Startup race resurfaces one tier deeper
**What goes wrong:** `docker compose up` intermittently fails with `host not found in upstream "proxy-old"` (or `proxy-new`) at the switch, or `server-old` at a static proxy.
**Why it happens:** nginx resolves `upstream ... server <name>` at config-parse time and aborts if Docker DNS can't answer yet (v1 RESEARCH Pitfall 4). The chain is now three deep, so there are two new gate points.
**How to avoid:** Cascade `depends_on: {condition: service_healthy}` — `proxy-old`→`server-old`, `proxy-new`→`server-new`, `switch`→`proxy-old`+`proxy-new`. Each static proxy needs its own healthcheck (the `:8081` listener) so the switch has something healthy to gate on.
**Warning signs:** A `switch` container in `Restarting` with an `[emerg] host not found` line; passes on a warm machine, flaps on a cold `up`.

### Pitfall 2: The flip gate probes the wrong tier
**What goes wrong:** The switch reload succeeds/`nginx -t` passes but the running config silently stays put, or the gate refuses a flip for the wrong reason.
**Why it happens:** v1's `flip.sh` gate probes `server-old`/`server-new` because those were the proxy's upstreams. The switch's upstreams are now `proxy-old`/`proxy-new`. A reload aborts if *those* don't resolve, not (directly) the backends.
**How to avoid:** Re-point the gate to probe `proxy-old` and `proxy-new` health (via `docker compose exec switch curl http://proxy-old:8081/nginx-health`). Probing the backends is still a useful transitive check but is not what the switch's parse depends on.
**Warning signs:** A flip that reports success while `:8081/active-proxy` still shows the old selector.

### Pitfall 3: `remote_addr` silently missing from evidence
**What goes wrong:** EV2-01 / criterion 3 fail — the status rows can't show the client's real address because the JSON evidence line never carried it.
**Why it happens:** v1's `evidence` log_format has **no `remote_addr` field** (only the `demo` stdout format does). Sourcing the log at the switch is necessary but not sufficient; the field must be added to the JSON *and* surfaced by `status.py`/`index.html`.
**How to avoid:** Add `"remote":"$remote_addr"` to the switch's `evidence` format; render it in `status.py:_render_row` and add the column/annotation to the status page (this is the UI touch behind *UI hint: yes*).
**Warning signs:** `curl localhost:9094/api/status | jq '.rows[0]'` has no `remote`/address field.

### Pitfall 4: `$upstream_addr` now names the proxy, read as a fidelity regression
**What goes wrong:** `make logs` shows `upstream=<proxy-old-ip>:80` instead of the backend's IP; someone "fixes" it.
**Why it happens:** The switch's immediate upstream is the static proxy, so `$upstream_addr` is the proxy's address (verified: `"upstream":"172.19.0.3:80"` = proxy-old in the 2-hop test). This is correct and expected.
**How to avoid:** **Document, don't fix.** `status.py` does not render `upstream` (confirmed — `_render_row` emits time/path/status/backend/ms/bhost only), so the status page is unaffected. Only the `demo` stdout line in `make logs` shows it, and the `backend=` token (from `X-Backend`) still carries the true identity the awk colouring keys on. The demo's honesty claim rests on `X-Backend`, not on `$upstream_addr`.
**Warning signs:** A plan task proposing to rewrite `$upstream_addr` — reject it.

### Pitfall 5: The rename is under-scoped (the smoke harness)
**What goes wrong:** Phase passes its own checks but `make test` (smoke.sh) is red or, worse, green-but-lying against the old topology.
**Why it happens:** `scripts/smoke.sh` has ~128 `proxy` tokens and ~106 references to `active-backend`/`9092`/log-path/`:8081`, across seven `section_*` functions (`section_backends`, `section_proxy`, `section_redirect`, `section_cutover`, `section_ssh`, `section_walkthrough`, `section_hostkey`). Every `docker compose exec -T proxy ...` and `docker compose logs proxy` must become `switch`, and `proxy/active-backend.conf` → `switch/active-proxy.conf`.
**How to avoid:** Treat the smoke-harness update as an explicit, sized task (not an afterthought). `section_ssh`/`section_walkthrough`/`section_hostkey` also assert against port 22 / SSH — Phase 5 ships HTTP only, so decide per-section whether the SSH assertions are skipped-until-Phase-6 or kept green because the static proxies already carry SSH.
**Warning signs:** `grep -n 'exec -T proxy\|logs proxy\|active-backend' scripts/smoke.sh` returns hits after the phase.

### Pitfall 6: `make reset` restores the wrong canonical file
**What goes wrong:** `make reset` rewrites `proxy/active-backend.conf` byte-for-byte, but the switch now reads `switch/active-proxy.conf` — a reset leaves the demo opening on a stale/absent selector.
**Why it happens:** The `reset` target hard-codes the canonical five-line file content and path; `flip.sh` and `status.py` also hard-code the path/filename.
**How to avoid:** Update the `reset` printf (path + header-comment filename), `flip.sh`'s `CONF=`, and `status.py`'s `DEMO_CONF_PATH` together. Keep the map body byte-identical so `read_config` and the presenter-visible diff are unchanged.
**Warning signs:** After `make reset`, `curl localhost:9092/whoami` doesn't return OLD, or the status page shows the config source erroring.

## Code Examples

### Verified: X-Backend survives two hops and lands in the switch's log
```bash
# Source: scratchpad 3-container test against nginx:1.30-alpine (this session)
# switch -> proxy-old -> backend(X-Backend: OLD)
curl -sD- http://t-switch/whoami        # client sees:  X-Backend: OLD   X-Backend-Host: server-old
docker logs t-switch | tail -1
# {"remote":"172.19.0.5","backend":"OLD","bhost":"server-old","upstream":"172.19.0.3:80","status":200}
#   remote  = the switch's immediate client (real client)          -> EV2-01 works when sourced here
#   backend = the BACKEND's own header, across 2 hops              -> EV2-02 works with zero special config
#   upstream= the STATIC PROXY's ip (172.19.0.3), not the backend  -> expected; status.py does not render it
# proxy-old adds no identity of its own:
curl -sD- http://t-proxyold/whoami | grep -ci x-backend    # -> 1  (exactly one, the backend's)
```

### Compose health cascade (the load-bearing ordering)
```yaml
# Each static proxy healthcheck reuses v1's proven idiom (curl IS in the stock image).
proxy-old:
  image: nginx:1.30-alpine
  volumes: [ ./proxy-old:/etc/nginx/demo:ro, ./proxy-old/nginx.conf:/etc/nginx/nginx.conf:ro, /etc/localtime:/etc/localtime:ro ]
  healthcheck: { test: ["CMD","curl","-fsS","http://localhost:8081/nginx-health"], interval: 3s, timeout: 2s, retries: 10, start_period: 3s }
  networks: { default: { aliases: [ app-old.demo.test ] } }     # PROX-03
  depends_on: { server-old: { condition: service_healthy } }
switch:
  image: nginx:1.30-alpine
  volumes: [ /etc/localtime:/etc/localtime:ro, ./switch:/etc/nginx/demo:ro, ./switch/nginx.conf:/etc/nginx/nginx.conf:ro, demo-logs:/var/log/demo ]
  healthcheck: { test: ["CMD","curl","-fsS","http://localhost:8081/nginx-health"], interval: 3s, timeout: 2s, retries: 10, start_period: 3s }
  ports: ["127.0.0.1:9092:9092","127.0.0.1:9093:9093"]
  networks: { default: { aliases: [ app.demo.test ] } }          # alias MOVES here from proxy (SW-01)
  depends_on:
    proxy-old: { condition: service_healthy }
    proxy-new: { condition: service_healthy }
```

## State of the Art

| Old (v1) | New (v2 Phase 5) | Impact |
|----------|------------------|--------|
| Single `proxy` flips its own `$active_backend` upstream (old/new backends) | Front `switch` flips `$active_proxy` between two static proxies | Enables pre-flip validation (Phase 6) and instant rollback (Phase 7); one extra hop each way |
| Evidence written by `proxy`; `$remote_addr` = client of the proxy | Evidence written by `switch`; `$remote_addr` = client of the switch (still the real client) | Same honesty, one tier forward; `upstream_addr` now names the static proxy |
| `proxy/active-backend.conf` is the flip surface | `switch/active-proxy.conf` is the flip surface | Same map shape, same `nginx -s reload`, same presenter diff |
| status probes `http://proxy:8081` | status probes `http://switch:8081` | Env/default re-point only |

**Deprecated/outdated:** nothing removed. `proxy/` stays in the tree (Phase 7 formalizes v1 preservation; v1 is already recoverable at git tag `v1.0`, which exists).

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | EV2-01 / criterion 3 ("rows show the client's real `remote_addr`") requires surfacing `remote_addr` on the **status page**, not just in the log — hence a UI-SPEC touch | Pitfall 3 / Summary | If the intent is log-only, the UI task is unnecessary scope; confirm the desired presentation (new column vs per-row annotation) in discuss/UI-phase |
| A2 | Static proxies should carry their **SSH stream block now** (configured once, never touched) rather than have Phase 6 edit them | Standard Stack / Pattern 1 | If deferred to Phase 6, PROX-01/02 "never reconfigured" is weaker but Phase 5 stays strictly HTTP; low risk either way |
| A3 | `proxy/` directory is **left in place** in Phase 5; Phase 7 owns the preservation decision (tag `v1.0` already exists) | Structure / State of the Art | If Phase 7 wants a `compose.v1.yaml` referencing a moved path, that's a Phase 7 choice this leaves open — no corner painted |
| A4 | The `make logs`/`logs-demo` tail set becomes `switch server-old server-new` (drop the intermediate static proxies as noise) | (Makefile edits) | If the presenter wants to *see* the proxy hop in logs, add `proxy-old proxy-new` — cosmetic, presenter preference |

All four are presentation/scope judgements, not technical unknowns. Every nginx behavioural claim in this document is `[VERIFIED]`.

## Open Questions (RESOLVED)

1. **`remote_addr` presentation on the status page**
   - What we know: it must be added to the evidence JSON (verified the switch captures it); the status page currently shows time/path/status/backend/ms/bhost.
   - What's unclear: new column vs. a header line ("client: <ip>") vs. per-row — a UI-SPEC decision.
   - Recommendation: resolve in the UI-phase for Phase 5; keep it a single, low-emphasis surface (the money shot stays OLD→NEW).
   - **RESOLVED:** no separate UI-SPEC produced (zero-visual-change plumbing phase, guarded by v1's UI token audit). Adopted in 05-02 Task 2 as a single low-emphasis client-IP column following v1's existing status-page design tokens.

2. **SSH assertions in `smoke.sh` during an HTTP-only phase**
   - What we know: `section_ssh`/`_walkthrough`/`_hostkey` assert over port 22; Phase 5 wires HTTP only through the switch, though the static proxies can already carry SSH.
   - What's unclear: skip-until-Phase-6 vs. keep-green-via-static-proxies.
   - Recommendation: if the static proxies ship their SSH stream in Phase 5 (A2), the direct `app-old`/`app-new:22` path is already testable; keep those green and defer only the *switch's* SSH:22 assertions to Phase 6.
   - **RESOLVED:** static proxies ship their SSH stream now (05-01 Task 2, inert until Phase 6). 05-03 Task 3 gates `section_ssh`/`section_hostkey` out of the `make test` `all` runner with explicit `# Phase 6 (SW-03)` markers — functions preserved intact, not deleted.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Docker + Compose v2 | the whole rig | ✓ | 29.6.1 | — |
| `nginx:1.30-alpine` | switch + 2 proxies | ✓ (local, 92.8 MB) | 1.30.4 | — |
| `curl` inside the image | static-proxy healthchecks | ✓ | 8.21.0 | busybox `wget` (as status uses) if ever absent |
| `--with-stream` module | static-proxy SSH (A2) | ✓ | compiled in | — |
| `jq` | validation checks | ✓ | 1.8.2 | `python -m json.tool` / grep |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** none needed — everything required is present and verified this session.

## Validation Architecture

### Test Framework
| Property | Value |
|----------|-------|
| Framework | POSIX shell smoke suite (`scripts/smoke.sh`) + `make test`; sections are `section_*` functions |
| Config file | none — plain `sh`; run via `make test` |
| Quick run command | `curl -s localhost:9092/whoami` / targeted `docker compose exec` checks |
| Full suite command | `make test` (updates required — see Wave 0) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| MIG-01 | one command brings up all 6 services healthy | integration | `docker compose up -d --wait && docker compose ps --format '{{.Service}} {{.Status}}' \| grep -c healthy` | ❌ Wave 0 (extend `section_proxy`) |
| SW-01 | client hits `app.demo.test:9092` unchanged → OLD | integration | `docker compose exec -T client curl -fsS http://app.demo.test:9092/whoami \| grep -qx 'OLD server-old'` | ❌ Wave 0 |
| SW-01 | chain is switch→proxy-old→server-old | integration | `docker compose logs switch \| grep -q 'upstream='` and `docker compose logs proxy-old \| grep -q server-old` | ❌ Wave 0 |
| SW-02/SW-04 | edit `switch/active-proxy.conf` + reload flips to NEW, same command | integration | `make flip-new && curl -fsS localhost:9092/whoami \| grep -qx 'NEW server-new'` | ⚠️ adapt `flip.sh` + `section_cutover` |
| PROX-01/02 | static proxies forward a fixed backend | integration | `docker compose exec -T switch curl -fsS http://proxy-old/whoami \| grep -qx 'OLD server-old'` (and proxy-new→NEW) | ❌ Wave 0 |
| PROX-03 | distinct aliases resolve on the demo net | integration | `docker compose exec -T switch getent hosts app-old.demo.test app-new.demo.test` | ❌ Wave 0 |
| EV2-01 | evidence rows carry the client's real `remote_addr`, not a proxy IP | integration | `curl -s localhost:9094/api/status \| jq -e '.rows[0].remote' ` and assert it ≠ proxy-old/proxy-new container IP | ❌ Wave 0 (needs new JSON field + render) |
| EV2-02 | `backend=` is the backend's own `X-Backend` through 2 hops; no proxy asserts it | integration | `curl -sD- localhost:9092/whoami \| grep -i '^X-Backend: OLD'` **and** `docker compose exec -T switch curl -sD- http://proxy-old/whoami \| grep -ci '^X-Backend:'` = 1 | ❌ Wave 0 |
| EV2-03 | status shows current selector + recent backends | integration | `curl -s localhost:9094/api/status \| jq -e '.config=="OLD" and (.rows\|length>0)'` | ⚠️ adapt `section_cutover` |

### Sampling Rate
- **Per task commit:** `curl -s localhost:9092/whoami` + the single requirement's targeted command.
- **Per wave merge:** the updated `section_proxy` / `section_cutover` (topology + flip).
- **Phase gate:** full `make test` green (all seven sections reconciled to the switch topology) before `/gsd-verify-work`.

### Wave 0 Gaps
- [ ] `scripts/smoke.sh` — reconcile ~128 `proxy` refs + ~106 topology refs to the `switch`/static-proxy shape; add proxy-old/proxy-new/alias/two-hop-header assertions
- [ ] `scripts/flip.sh` — `CONF`→`switch/active-proxy.conf`; all `exec proxy`→`exec switch`; gate probes proxy-old/proxy-new
- [ ] `status/status.py` + `status/index.html` — render `remote_addr`; re-point `DEMO_PROXY_PROBE`/`DEMO_CONF_PATH`
- [ ] `Makefile` — `up`/`reset`/`clear-evidence`/`logs`/`logs-demo`/`reload` re-pointed to `switch`; reset canonical file → `switch/active-proxy.conf`
- [ ] New assertion: EV2-02 integrity — exactly one `X-Backend` through a static proxy (no proxy-injected identity)

## Security Domain

`security_enforcement: true`, ASVS L1. No new trust boundary is crossed — the phase adds two internal proxy hops on the existing demo network and moves the evidence writer forward one tier.

### Applicable ASVS Categories
| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V2 Authentication | no | No auth surface added (SSH creds are inherited backend behaviour) |
| V3 Session Management | no | Stateless |
| V4 Access Control | no | No new authz |
| V5 Input Validation | **yes** | Attacker-controlled `$uri`/`$request_uri` still land in the evidence file → keep `escape=json` on the switch's evidence format (inherited from v1); 9093 redirect target stays **literal** (no open redirect, T-01-13) |
| V6 Cryptography | no | No TLS in scope; SSH host keys unchanged |
| V10 Malicious Code / Integrity | **yes** | Evidence integrity: `backend=` must be the backend's own header; static proxies must add **no** identity header — asserted by test |

### Known Threat Patterns for this stack
| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| A proxy tier forging `backend=NEW` | Spoofing / Tampering | Static proxies are transparent (no `add_header X-Backend`); verified exactly one `X-Backend` passes through; assert in smoke |
| Client-supplied `X-Backend` request header polluting evidence | Spoofing | Non-issue: `$upstream_http_x_backend` reads the **response** header, not the request — no filtering needed (don't add unnecessary defense) |
| Log injection via crafted path | Tampering | `escape=json` on the switch's evidence sink turns `%0a` into a literal escape (v1 control, carried forward) |
| Open redirect on 9093 | Tampering | Literal redirect target, never `$host`-derived (T-01-13) |
| Privilege escalation via Docker socket | Elevation | No socket mounted anywhere; status reads evidence via a `:ro` shared volume (unchanged) |
| Rig exposed to conference wifi | Info disclosure | Published ports stay loopback-bound (`127.0.0.1:`); the two static proxies publish **nothing** (internal-only); container `:22` never published (T-01-02) |

## Sources

### Primary (HIGH confidence)
- Live `docker run`/3-container test against `nginx:1.30.4-alpine` (this session) — curl presence (8.21.0), `--with-stream`, two-hop `X-Backend`/`X-Backend-Host` pass-through, `$upstream_http_x_backend` at the switch, `$upstream_addr`=proxy IP, single-header integrity.
- Codebase (this session): `compose.yaml`, `proxy/nginx.conf`, `proxy/active-backend.conf`, `status/status.py`, `Makefile`, `scripts/flip.sh`, `backend/Dockerfile`, `backend/templates/*`, `client/entrypoint.sh`.
- `.planning/REQUIREMENTS.md`, `ROADMAP.md`, `PROJECT.md`, `STATE.md` — requirement IDs, success criteria, locked v1 decisions.

### Secondary (MEDIUM confidence)
- v1 RESEARCH pitfalls referenced inline in the shipped configs (Pitfall 4 parse-time resolution, Pitfall 10 directory-mount, Pitfall 3 typo'd-selector 503) — treated as proven since v1 is verified.

### Tertiary (LOW confidence)
- None. No web search was needed; all behaviours were verified against the exact pinned image.

## Project Constraints (from CLAUDE.md)
- Tech stack fixed: nginx (with `stream`) + Docker Compose. **No other tech.**
- Ports: HTTP **9092**, SSH **22** — the switch inherits both from the client's point of view; 22 is Phase 6.
- Environment: entirely local, no cloud/cost.
- Startup: **one command** (`make up` / `docker compose up`) must bring the whole 6-service rig up (MIG-01 = ENV-01 preserved).
- GSD workflow enforcement: all edits go through a GSD command; no direct edits outside the workflow.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — verified against the exact pinned image; no new packages.
- Architecture: HIGH — two-hop header propagation and health cascade verified empirically; mechanism proven in v1.
- Pitfalls: HIGH — five of six are direct extrapolations of v1's already-documented, already-mitigated failure modes; rename fan-out is measured (128 tokens in smoke.sh).
- Evidence/UI (`remote_addr` surfacing): MEDIUM — the *need* is clear (criterion 3); the *presentation* is a UI-SPEC decision (A1).

**Research date:** 2026-07-22
**Valid until:** 2026-08-21 (stable; pinned images and a proven mechanism — re-verify only if the nginx pin changes)

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SW-01 | `switch` is the client's only endpoint at `app.demo.test:9092` (SSH 22 in Phase 6) | Alias moves from `proxy`→`switch`; switch owns 9092 + 9093; 22 deferred (Pattern 2, compose example) |
| SW-02 | one-line `default old`→`new` map in `switch/active-proxy.conf` | Same map shape as v1's `active-backend.conf`; `status.py:read_config` parses it unchanged (Pattern 2) |
| SW-04 | cutover = edit that line + `nginx -s reload` on the switch | `flip.sh` re-pointed to `exec switch`; identical mechanism (Pitfall 2, Wave 0) |
| PROX-01 | `proxy-old` statically forwards to `server-old`, never reconfigured | Pattern 1 (transparent single-upstream; SSH block now per A2) |
| PROX-02 | `proxy-new` statically forwards to `server-new`, never reconfigured | Pattern 1 (mirror; upstream `server-new`) |
| PROX-03 | distinct aliases `app-old`/`app-new.demo.test` | compose `networks.default.aliases` per proxy (compose example) |
| EV2-01 | evidence log is the **switch's**, capturing real `remote_addr` | Verified `remote` at switch = real client; must ADD `remote` to JSON + render (Pitfall 3) |
| EV2-02 | backend's own `X-Backend` propagates to the switch log, asserted by no proxy | Verified two-hop pass-through; integrity control = no proxy add_header (Code Examples, Security) |
| EV2-03 | status shows current selector + recent backends (re-sourced) | `status.py` unchanged except probe/conf re-point + `remote` render (State of the Art) |
| MIG-01 | whole v2 topology up with one command, ENV-01 preserved | Health cascade makes `up -d --wait` deterministic (Pitfall 1, compose example) |

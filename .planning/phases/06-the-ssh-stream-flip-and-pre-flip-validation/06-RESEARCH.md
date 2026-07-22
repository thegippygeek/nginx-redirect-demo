# Phase 6: The SSH Stream Flip and Pre-Flip Validation - Research

**Researched:** 2026-07-22
**Domain:** nginx `stream` (L4 TCP) proxying, two-hop opaque relay, Docker Compose service topology, POSIX shell test harness reconciliation
**Confidence:** HIGH — the whole phase is grounded in files already in this repo; the SSH-flip mechanism is proven in v1 and preserved verbatim in git history and on disk at `proxy/nginx.conf`.

## Summary

Phase 6 has no new technology and no new packages. Every mechanism it needs already exists in this codebase and is proven: the v1 stream-flip pattern (in `proxy/nginx.conf`, still on disk and in git), the shared-include idiom (D-39, live in the switch's http block today), and the static SSH streams on `proxy-old`/`proxy-new` (shipped inert in Phase 5, `05-01`). The job is three concrete edits plus a test reconciliation: (1) **re-home v1's stream block onto the switch** with its two upstreams retargeted from `server-old/new:22` to `proxy-old/new:22`; (2) **prove pre-flip validation** over `app-new.demo.test` (HTTP port 80 + SSH 22, both already live post-Phase-5, reached from the client container over Docker DNS); (3) **reconcile `verify.sh` and the two deferred smoke sections** (`section_ssh`, `section_hostkey`) from stale v1 `proxy`/`proxy/*.conf`/`/active-backend` references onto the switch, and re-enable them in the `all` runner. [VERIFIED: codebase read of switch/nginx.conf, proxy-*/nginx.conf, compose.yaml, scripts/*, git history of proxy/nginx.conf]

The SSH path becomes two stream hops: `client → switch:22 (map-selects proxy-old|proxy-new) → proxy-old/new:22 (static) → server-old/new:22`. nginx `stream` is an opaque TCP relay — it parses nothing and forwards bytes — so a second hop is mechanically identical to the first; SSH's own end-to-end crypto (host key, banner, session) is untouched by either relay. v1 proved one hop; two hops add no protocol concern, only two default idle `proxy_timeout` windows (10 min each) that are irrelevant for a demo. [VERIFIED: nginx stream semantics + v1 one-hop proof in codebase]

**Primary recommendation:** Re-home the v1 `proxy/nginx.conf` stream block onto `switch/nginx.conf` verbatim, changing only the two upstream targets to `proxy-old:22` / `proxy-new:22` and the shared include path to `demo/active-proxy.conf`. Add no compose changes (no `:22` host publish — D-15 stays intact; the switch's stream upstreams are already health-gated by the existing `depends_on` on the two proxies). Then reconcile `scripts/verify.sh` (add an `app-new` target mode) and re-point/re-enable `section_ssh` + `section_hostkey` in `scripts/smoke.sh`.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| SSH:22 flip selection (map old→new) | **switch** (new stream block) | — | The switch is the sole flip surface (SW-02/SW-04); its stream block must include the same `active-proxy.conf` the http block does so one edit governs both protocols (SW-03/D-39) |
| Static SSH relay to a fixed backend | **proxy-old / proxy-new** | — | Shipped Phase 5 (`05-01`); each statically forwards `:22 → server-old/new:22`, never reconfigured (PROX-01/02) |
| SSH host key + banner + session crypto | **server-old / server-new** | — | Backends own identity; both stream hops relay opaquely and cannot forge or alter it (EV2-02 integrity, inherited KEY-* behaviour) |
| Pre-flip validation endpoint | **proxy-new** (via `app-new.demo.test` alias) | client container | Docker DNS alias resolves straight to proxy-new, bypassing the switch; reachable only from inside the demo network (T-05-04) |
| Stream evidence line (label + selector) | **switch** (stdout only) | — | Re-homed from v1's proxy; MUST NOT write to the JSON evidence sink or it corrupts the status parser (D-46) |
| Two-protocol verification | **scripts/verify.sh** (host + client-container probes) | — | Asserts which backend answered through the switch; adds an `app-new` direct mode (EV2-04) |

## <phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| **SW-03** | The same selector governs both HTTP 9092 and SSH 22, so one edit flips both protocols | Re-home v1's stream block onto `switch/nginx.conf`; include the SAME `demo/active-proxy.conf` the http block includes (D-39 shared-map idiom, already proven live in the switch's http context). Upstreams retarget to `proxy-old:22`/`proxy-new:22`. Verified by the reconciled `section_ssh` SSH-02/D-39 assertions (shared include appears exactly twice in `switch/nginx.conf`). |
| **VAL-01** | Reach `app-new.demo.test` over HTTP → `server-new` before cutover, while `app.demo.test` still lands on OLD | Live NOW (Phase 5 shipped proxy-new HTTP :80 + `app-new.demo.test` alias). Command: `docker compose exec client curl -fsS http://app-new.demo.test/whoami` → `NEW server-new` (port 80, NOT 9092; Docker-DNS-only, run from client container). Concurrent `curl -fsS localhost:9092/whoami` → `OLD server-old`. |
| **VAL-02** | `ssh app-new.demo.test` → `server-new` banner before cutover | Live NOW (Phase 5 shipped proxy-new's static stream on :22). Command: `docker compose exec client ssh <opts> demo@app-new.demo.test true` → banner `NEW server-new`, while `ssh demo@app.demo.test` → OLD (after the switch stream block lands). |
| **EV2-04** | verify.sh asserts both protocols through the switch, exits non-zero on mismatch, can target `app-new.demo.test` directly | `verify.sh` already targets the switch (HTTP `localhost:9092`, SSH `app.demo.test`); the SSH half only starts passing once the switch stream block exists. Add a target-mode flag that redirects BOTH probes to `app-new.demo.test` executed from the client container (see Pitfall 2). Exit-code vocabulary (0/1/2/3) already implemented. |
</phase_requirements>

## Standard Stack

No new packages. The entire phase is configuration + shell, using tooling already pinned and running in the rig.

### Core
| Component | Version | Purpose | Why Standard |
|-----------|---------|---------|--------------|
| nginx | `nginx:1.30-alpine` (pinned) | `stream` module TCP relay on :22 | Already the image for switch + both proxies; `--with-stream` is compiled in (asserted by ENV-04 in `section_proxy`) [VERIFIED: compose.yaml, smoke.sh:128] |
| Docker Compose | v2+ (host) | Topology + Docker DNS aliases | Already the rig's substrate; `app-new.demo.test` alias live [VERIFIED: compose.yaml:158] |
| OpenSSH client | in `client` image | pre-flip + through-switch SSH probes | Already the canonical SSH source (D-02) [VERIFIED: client/entrypoint.sh] |
| POSIX sh | busybox / host sh | verify.sh, smoke.sh, flip.sh | Existing harness convention (no `set -e`, every assertion runs) [VERIFIED: scripts/*] |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Re-homing v1's stream block onto the switch | A fresh stream block written from scratch | Rejected — v1's block is battle-tested and its comments encode measured decisions (D-40, D-46, IPv4-wildcard gotcha). Copy, retarget two upstreams, done. |
| No host publish of `:22` | `ports: ["127.0.0.1:22:22"]` on the switch | Rejected — violates D-15/D-38/Phase-5 prohibition; the client reaches `switch:22` over the Docker network, so "ssh on port 22, no `-p` flag" stays literally true without exposing a `demo:demo` credential to the host (threat T-01-02). |

**Installation:** none. `docker compose up -d --wait` already stands up the full topology.

## Package Legitimacy Audit

**Not applicable — this phase installs no external packages.** All tooling (nginx 1.30-alpine, Docker Compose, OpenSSH client, POSIX sh) is already present, pinned, and running in the rig. No `npm`/`pip`/`cargo` surface exists in this project.

## Architecture Patterns

### System Data Flow (after Phase 6)

```
                       PRE-FLIP VALIDATION (VAL-01/02, live since Phase 5)
                       ┌─────────────────────────────────────────────┐
                       │  client container                            │
                       │  curl http://app-new.demo.test/whoami  (:80) │
                       │  ssh  demo@app-new.demo.test          (:22)  │
                       └───────────────┬──────────────────────────────┘
                          Docker DNS   │ alias app-new.demo.test
                                       ▼
                                  ┌──────────┐   static :80 → server-new:80
                                  │ proxy-new│   static :22 → server-new:22
                                  └────┬─────┘
                                       ▼         → NEW  (while switch still selects OLD)
                                  ┌──────────┐
                                  │server-new│
                                  └──────────┘

    THROUGH-THE-SWITCH FLIP (SW-03: one edit, both protocols)

  client ──HTTP :9092──┐
  (or host localhost)  │        switch/active-proxy.conf
  client ──SSH  :22 ───┤        ┌──────────────────────┐
                       ▼        │ map default old|new  │◄── the ONE edit
                  ┌─────────────┴──────────────────────┴───────────┐
                  │  switch                                          │
                  │  http{}   include active-proxy.conf → $active_backend
                  │           upstream old→proxy-old:80  new→proxy-new:80
                  │           server listen 9092 proxy_pass $active_backend
                  │  stream{} include active-proxy.conf → $active_backend   ◄── NEW (Phase 6)
                  │           upstream old→proxy-old:22  new→proxy-new:22
                  │           server listen 22   proxy_pass $active_backend
                  │           access_log /dev/stdout demo_stream  (NOT the JSON sink, D-46)
                  └───────┬──────────────────────────────┬─────────┘
              selector=old│                  selector=new│
                          ▼                              ▼
                   ┌──────────┐                    ┌──────────┐
                   │ proxy-old│ :80→server-old:80  │ proxy-new│ :80→server-new:80
                   │  (static)│ :22→server-old:22  │  (static)│ :22→server-new:22
                   └────┬─────┘                    └────┬─────┘
                        ▼                               ▼
                   server-old (OLD)                server-new (NEW)
```

The **map file is included twice** — once in `http{}` (already there), once in the new `stream{}` — because an nginx `map` is valid in both contexts while an `upstream` group is not shareable across them. `$active_backend` in http and `$active_backend` in stream are two independent variables in two independent namespaces, so the same 5-line file drives both. This is D-13/D-39's payoff, already cashed in the switch's http block. [VERIFIED: git history of proxy/nginx.conf; switch/nginx.conf:72-78,102]

### Pattern 1: Re-homed stream block on the switch
**What:** v1's `proxy/nginx.conf` stream block, copied onto `switch/nginx.conf`, with only the upstream targets and include path changed.
**When to use:** This is the SW-03 core edit.
**Example (the exact re-home; deltas vs v1 are marked):**
```nginx
# Source: v1 proxy/nginx.conf stream block (git rev 3b7dc6c), re-homed.
# DELTAS: upstreams now target the two static proxies on :22 (was server-old/new:22),
#         and the include path is demo/active-proxy.conf (was demo/active-backend.conf).
stream {
    log_format demo_stream '$remote_addr -> :$server_port ssh backend=$stream_label '
                           'selector=$active_backend upstream=$upstream_addr status=$status '
                           'bytes=$upstream_bytes_sent/$upstream_bytes_received sess=$session_time';

    # STDOUT ONLY (D-46): the JSON evidence sink is parsed by the status service,
    # which silently discards non-JSON lines. A stream line there is invisible rot.
    access_log /dev/stdout demo_stream;

    # Declared BEFORE the include so a variable proxy_pass resolves against declared
    # group names (no resolver needed). Port 22 here; an upstream is NOT shareable
    # across contexts, which is why the SELECTOR (not the target) is in the shared file.
    upstream old { server proxy-old:22; }   # DELTA: was server-old:22
    upstream new { server proxy-new:22; }   # DELTA: was server-new:22

    # THE SAME FILE the http block includes — D-39. A map is valid in both contexts.
    include /etc/nginx/demo/active-proxy.conf;   # DELTA: was demo/active-backend.conf

    # Uppercase label derived HERE, never in the shared file (keeps it 5 lines on the projector).
    map $active_backend $stream_label {
        default "?";
        old     OLD;
        new     NEW;
    }

    # `listen 22;` binds the IPv4 wildcard ONLY (0.0.0.0:22). No host publish (D-15/D-38):
    # the client reaches switch:22 over the Docker net. No $backend_is_valid analogue —
    # an SSH client cannot render a diagnostic; a bad selector logs status=500 (D-40 note).
    server {
        listen 22;
        proxy_pass $active_backend;
    }
}
```
[VERIFIED: git show of v1 proxy/nginx.conf stream block]

### Pattern 2: Pre-flip validation via the static-proxy alias (bypasses the switch)
**What:** `app-new.demo.test` is a Docker network alias on `proxy-new`, resolvable only inside the demo network. HTTP lands on port **80** (proxy-new's listener), SSH on 22 — both static, both live since Phase 5.
**When to use:** VAL-01/VAL-02, and `verify.sh --target app-new`.
**Example:**
```sh
# Source: compose.yaml:158 (alias) + proxy-new/nginx.conf (:80 http, :22 stream).
# BOTH probes run from the client container — app-new.demo.test is Docker-DNS-only,
# and no proxy host port is published (T-05-04), so localhost cannot reach it.
docker compose exec client curl -fsS http://app-new.demo.test/whoami        # -> NEW server-new
docker compose exec client ssh -o BatchMode=yes -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null demo@app-new.demo.test true              # banner: NEW server-new
# Meanwhile, through the switch, still OLD:
curl -fsS http://localhost:9092/whoami                                       # -> OLD server-old
```
[VERIFIED: proxy-new/nginx.conf, compose.yaml]

### Anti-Patterns to Avoid
- **Publishing `:22` on the switch.** Breaks D-15/D-38 and exposes `demo:demo` to the host (T-01-02). The client reaches the switch over the Docker net — no publish needed.
- **Writing the stream `access_log` to `/var/log/demo/access.log`.** The status service's JSON parser silently discards non-JSON lines while rescanning a growing file — invisible, unexplained corruption (D-46). Stream logs go to `/dev/stdout` only.
- **Adding a stream `access_log` to the two static proxies.** Only the switch logs the stream line; the proxies relay silently. A second log line would double-count and confuse `make logs`.
- **Probing the stream listener with the name `localhost`.** `listen 22;` in stream binds IPv4 wildcard only; busybox resolvers try `::1` first and don't retry — use the IPv4 loopback literal `127.0.0.1` (this is why `section_ssh` SSH-01 uses `nc -z 127.0.0.1 22`).
- **`ssh ... | head` in a test.** A pipeline reports the LAST command's status; a host-key failure would read as exit 0. Capture into a variable, read `$?` on the next line, grep the variable (already the harness idiom in verify.sh and section_ssh).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| SSH-over-TCP proxying | A custom TCP forwarder | nginx `stream` block (already compiled in) | Opaque L4 relay; SSH crypto/host-key/banner pass through untouched — proven one-hop in v1 |
| One-edit-both-protocols flip | Two separate selector files | The SAME `active-proxy.conf` included in both contexts (D-39) | A `map` is valid in both http and stream; an `upstream` is not — so the selector, not the target, is shared |
| Health-gating the switch's stream upstreams | New healthcheck wiring | The EXISTING `depends_on: {proxy-old, proxy-new: service_healthy}` | nginx resolves stream upstreams at parse time; the Phase-5 cascade already gates on both proxies healthy |
| Pre-flip validation endpoint | New service/port | The Phase-5 `app-new.demo.test` alias on proxy-new | Already live over HTTP:80 and SSH:22; nothing to build |

**Key insight:** This phase is almost entirely *re-homing and reconciliation*, not construction. The temptation is to rewrite; the correct move is to copy proven v1 config and retarget two strings, then fix stale service/path references in the two deferred test sections.

## Runtime State Inventory

> Rename/re-home phase — the SSH surface moves from v1's `proxy` service onto the `switch`. Explicit inventory below.

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| **Stored data** | None. The stream relay is stateless; no datastore keys reference old/new SSH paths. | None — verified: no DB/volume holds SSH routing state (compose has only `demo-logs`, `demo-keys`; keys are backend host keys, unaffected). |
| **Live service config** | The switch container currently has **no `:22` listener**. Adding the stream block gives it one on the next `nginx -s reload` / `up`. The two static proxies already listen on :22 (Phase 5, inert until now). | Add stream block to `switch/nginx.conf`; `docker compose up -d` (config is bind-mounted `:ro`, picked up on container recreate) or reload. No API/UI-stored config exists. |
| **OS-registered state** | None. No Task Scheduler / systemd / pm2 registrations in this laptop-local rig. | None — verified: rig is Docker Compose only. |
| **Secrets/env vars** | `demo:demo` credential (image-baked) and the ed25519 keypair (`demo-keys` volume). Neither references old/new by name; both unaffected by the re-home. | None. |
| **Build artifacts / installed packages** | None. No compiled artifacts; nginx configs are bind-mounted, not baked. | None. |
| **Stale references in code (the real re-home cost)** | `scripts/smoke.sh` `section_ssh` + `section_hostkey` (and the shared `selector_now()` helper at line 1080) still reference the **v1 `proxy` service, `proxy/nginx.conf`, `proxy/active-backend.conf`, and the `/active-backend` oracle endpoint**. These were deferred, not reconciled, in Phase 5. | Reconcile every stale reference onto the switch (see Pitfall 4 table) and re-enable both sections in the `all` runner. |
| **Archived v1 artifact still on disk** | `proxy/nginx.conf` and `proxy/active-backend.conf` remain in the working tree (not referenced by `compose.yaml` anymore). `section_ssh`'s SSH-02 assertions currently grep `proxy/nginx.conf`. | Decide per-assertion whether it should now grep `switch/nginx.conf` (it should — the live stream block is on the switch now). v1 preservation itself is **Phase 7 scope (MIG-03)** — do NOT delete `proxy/` here. |

**The canonical question — after every file is updated, what still has the old wiring?** Only the two deferred smoke sections and their shared `selector_now()` helper. Reconciling those strings + re-enabling the sections is the bulk of the test work.

## Common Pitfalls

### Pitfall 1: The stream `access_log` corrupting the JSON evidence sink
**What goes wrong:** If the switch's stream block writes to `/var/log/demo/access.log`, the status service's JSON parser silently drops each non-JSON stream line while still rescanning a growing file.
**Why it happens:** The http block legitimately writes JSON there; copying the `access_log` line without re-checking the target co-mingles two formats.
**How to avoid:** Stream `access_log /dev/stdout demo_stream;` — stdout only, exactly as v1 (D-46). The reconciled `section_ssh` D-46 assertions verify the stream region declares exactly one `access_log`, that it targets `/dev/stdout`, and names no `var/log` path.
**Warning signs:** Status page request table shows fewer rows than expected after SSH traffic; `access.log` grows without new visible rows.

### Pitfall 2: `app-new` verification must run from the client container on port 80 — not host:9092
**What goes wrong:** `verify.sh --target app-new` written to `curl localhost:9092` (or any host port) fails — `app-new.demo.test` is a Docker-DNS-only alias and proxy-new publishes no host port; and its HTTP listener is **:80**, not 9092.
**Why it happens:** The default (through-switch) HTTP probe runs from the host at `localhost:9092`; the app-new probe has a *different execution context and port*.
**How to avoid:** In app-new mode, run BOTH probes from inside the client container: `docker compose exec client curl -fsS http://app-new.demo.test/whoami` (port 80) and `docker compose exec client ssh ... demo@app-new.demo.test`. Expectation is fixed **NEW** (proxy-new is static). [VERIFIED: proxy-new/nginx.conf listens :80; compose.yaml — no proxy host ports]
**Warning signs:** `curl (7) Failed to connect` or DNS resolution failure when app-new probe runs from the host.

### Pitfall 3: nginx parses stream upstreams at load time — a down proxy aborts the reload
**What goes wrong:** The switch's `nginx -t` / reload aborts with `host not found in upstream` if `proxy-old`/`proxy-new` don't resolve, leaving the switch on its previous config.
**Why it happens:** Stream `upstream ... server <name>` resolves at parse time, same as http.
**How to avoid:** Nothing new needed — the switch's existing `depends_on: {proxy-old, proxy-new: service_healthy}` already gates this, and `flip.sh`'s health gate already probes BOTH proxies' `:8081/nginx-health` before touching the config. The stream block adds a second reason both proxies must be up, which the existing gates already cover. [VERIFIED: compose.yaml:111-113, flip.sh:86-95]
**Warning signs:** `flip.sh` refusal message naming a proxy; `nginx -t` failing inside the switch.

### Pitfall 4: Stale v1 `proxy` references throughout the two deferred smoke sections
**What goes wrong:** Re-enabling `section_ssh`/`section_hostkey` as-is fails immediately — they target a `proxy` service and files that no longer wire into the rig.
**Why it happens:** Phase 5 deferred (not reconciled) these sections; they still speak v1's topology.
**How to avoid:** Reconcile every reference. The full stale-reference map (from grep of `scripts/smoke.sh`):

| Location(s) | Current (v1) | Reconcile to (switch) |
|-------------|--------------|------------------------|
| `selector_now()` L1080 | `proxy/active-backend.conf` | `switch/active-proxy.conf` |
| `restore_ssh_state`/`finish_ssh_state` L1114-1123 | `proxy/active-backend.conf`, `exec -T proxy nginx -s reload` | `switch/active-proxy.conf`, `exec -T switch nginx -s reload` |
| SSH-01 listener L1331 | `exec -T proxy nc -z 127.0.0.1 22` | `exec -T switch nc -z 127.0.0.1 22` |
| SSH-02 / D-39 L1351-1372 | `proxy/nginx.conf`, `demo/active-backend.conf`, `proxy/active-backend.conf` | `switch/nginx.conf`, `demo/active-proxy.conf`, `switch/active-proxy.conf` |
| D-46 L1401-1405 | `proxy/nginx.conf` | `switch/nginx.conf` |
| EVID-01 stream L1417,1423 | `docker compose logs proxy` | `docker compose logs switch` |
| oracle probes L1506, L1633, L2199 | `exec -T proxy curl ... :8081/active-backend` | `exec -T switch curl ... :8081/active-proxy` (**note the endpoint renamed** `/active-backend` → `/active-proxy`) |

The direct-to-backend group in `section_ssh` (BACK-04/BACK-05, banner/host-key assertions against `server-old`/`server-new`) is **unchanged** — backends are untouched. Only the *proxied-hop* group and the shared helpers move.
**Warning signs:** `FAIL SSH-01`, `FAIL SSH-02`, `no such service: proxy`, oracle probe returning empty.

### Pitfall 5: Re-enabling the sections in the `all` runner
**What goes wrong:** Reconciling the section bodies but leaving them commented out in `all` means `make test` still skips them.
**Why it happens:** Phase 5 commented `# section_ssh` and `# section_hostkey` with explicit `# Phase 6 (SW-03)` deferral markers (smoke.sh L2261, L2276).
**How to avoid:** Uncomment both, preserving the ordering comments — `section_ssh` after `section_cutover` (which leaves the rig on OLD), `section_hostkey` LAST (most destructive: it flips, regenerates server-new host keys, writes the client's trust record, and restores on the way out). [VERIFIED: smoke.sh:2248-2277]
**Warning signs:** `make test` passes but the SSH/host-key sections never print their `--- ssh ---` / `--- hostkey ---` headers.

### Pitfall 6: Two-hop D-40 in-flight-session behaviour
**What goes wrong:** Worry that the added hop changes the "session opened before the flip keeps landing on OLD" guarantee.
**Why it happens:** D-40 relies on nginx's old worker generation holding the connection across a reload.
**How to avoid:** The behaviour is unchanged and correct. Only the **switch** reloads on a flip; its old worker keeps relaying the in-flight `client→switch` connection to its originally-selected upstream (proxy-old), which statically forwards to server-old. proxy-old/proxy-new never reload (they're static), so they add no interleave window. `worker_shutdown_timeout` stays unset on the switch (D-40). The reconciled D-40 assertions in `section_ssh` verify: in-flight session reports OLD after reload, fresh session reports NEW. [VERIFIED: smoke.sh:1445-1484 + stream relay semantics]
**Warning signs:** In-flight session unexpectedly reporting NEW (would indicate a stray `worker_shutdown_timeout` or a proxy reload).

## Code Examples

### The one-line flip governs both protocols (no flip.sh change)
```sh
# Source: scripts/flip.sh — edits switch/active-proxy.conf + reloads the switch.
# flip.sh needs NO change for SSH: it rewrites the ONE shared `default old|new;`
# line and reloads the switch. That single map file is included by BOTH the http
# and the new stream context, so the one reload flips both protocols at once.
sh scripts/flip.sh new     # HTTP:9092 AND SSH:22 both now select proxy-new
```
[VERIFIED: flip.sh edits switch/active-proxy.conf only; both contexts include it]

### verify.sh through-the-switch, both protocols (already implemented)
```sh
# Source: scripts/verify.sh — HTTP from host :9092, SSH from client to app.demo.test
# (both resolve to the switch). Exit 0 = both agree AND match; 1 = mismatch/unreadable;
# 2 = usage; 3 = protocols disagree with each other. The SSH half begins passing the
# moment the switch stream block exists.
make verify           # EXPECT=old (default)
make verify EXPECT=new
```
[VERIFIED: scripts/verify.sh:32-33, Makefile:127-129]

## State of the Art

| Old (v1 / pre-Phase-6) | Current (Phase 6) | When Changed | Impact |
|------------------------|-------------------|--------------|--------|
| SSH stream block on the single `proxy` service, upstreams `server-old/new:22` | Stream block on the `switch`, upstreams `proxy-old/new:22`; static proxies carry their own inert-until-now `:22` streams | Phase 6 | One SSH hop becomes two; the switch's map flips SSH as well as HTTP |
| Oracle endpoint `/active-backend` on `proxy` | `/active-proxy` on the `switch` | Phase 5 (endpoint), Phase 6 (tests catch up) | The deferred SSH tests must probe the new endpoint on the switch |
| Shared file `proxy/active-backend.conf` | `switch/active-proxy.conf` | Phase 5 | Include path in the new stream block is `demo/active-proxy.conf` |
| `section_ssh`/`section_hostkey` deferred (commented in `all`) | Reconciled + re-enabled | Phase 6 | `make test` covers the switch's SSH surface end to end |

**Deprecated/outdated:** `proxy/` directory (v1) is inert (not in compose) but must **remain** — v1 preservation is Phase 7 (MIG-03), out of scope here.

## Validation Architecture

> `nyquist_validation` is enabled (config.json). Test framework is the repo's POSIX-sh harness (`scripts/smoke.sh`, `scripts/verify.sh`), driven by `make test` / `make verify`.

### Test Framework
| Property | Value |
|----------|-------|
| Framework | POSIX sh assertion harness (`assert <label> <condition>`), no external deps |
| Config file | none — `scripts/smoke.sh` is self-contained; `Makefile` targets `test`, `verify`, `ssh` |
| Quick run command | `sh scripts/smoke.sh ssh` (SSH section only) / `make verify EXPECT=old` |
| Full suite command | `make test` (== `sh scripts/smoke.sh all`) |

### Phase Requirements → Test Map
| Req ID | Behavior | Test Type | Automated Command | Exists? |
|--------|----------|-----------|-------------------|---------|
| SW-03 | Switch stream block includes shared map; one edit flips SSH | integration | `sh scripts/smoke.sh ssh` (SSH-02/D-39 reconciled to `switch/nginx.conf`) | ❌ Wave 0 (reconcile refs) |
| SW-03 | Same command OLD→NEW over SSH across a flip | integration | `sh scripts/smoke.sh ssh` (CUT-04, D-40) | ❌ Wave 0 |
| VAL-01 | `app-new` HTTP → NEW while switch → OLD | integration | `docker compose exec client curl -fsS http://app-new.demo.test/whoami` == `NEW server-new` AND `curl -fsS localhost:9092/whoami` == `OLD server-old` | ❌ Wave 0 (new assertions) |
| VAL-02 | `app-new` SSH → server-new banner pre-flip | integration | `docker compose exec client ssh <opts> demo@app-new.demo.test true` grep `NEW server-new` | ❌ Wave 0 |
| EV2-04 | verify.sh both protocols through switch, exit non-zero on mismatch | integration | `make verify EXPECT=new` (exit 0/1/3) | ⚠️ Partial (SSH half activates with the stream block) |
| EV2-04 | verify.sh `--target app-new` asserts NEW pre-flip | integration | `sh scripts/verify.sh --target app-new` (new mode) | ❌ Wave 0 (add mode) |

### Observable Success Checks (for VALIDATION.md)
- **SW-03 both-protocol flip:** `ssh app.demo.test` → OLD banner; `sh scripts/flip.sh new`; `ssh app.demo.test` → NEW banner — one edit (`switch/active-proxy.conf`) flipped both HTTP and SSH; switch reloaded, no restart (CUT-05/D-14 still hold).
- **VAL-01/02 pre-flip:** with the switch selecting OLD, `docker compose exec client curl -fsS http://app-new.demo.test/whoami` → `NEW server-new` AND `docker compose exec client ssh <opts> demo@app-new.demo.test true` → banner `NEW server-new`, WHILE `curl -fsS localhost:9092/whoami` → `OLD server-old`.
- **EV2-04 through-switch verdict:** `make verify EXPECT=old` exits 0; after `flip new`, `make verify EXPECT=new` exits 0; a forced HTTP/SSH split exits 3 (the `VERIFY_SSH_HOST` test seam already proves the exit-3 branch is reachable).
- **EV2-04 app-new mode:** `sh scripts/verify.sh --target app-new` asserts NEW over both protocols, exit 0, pre-flip.
- **Regression gate:** `make test` green — including the re-enabled `section_ssh` and `section_hostkey`, with the switch's SSH:22 stream and `D-15 no host port 22` still passing.

### Sampling Rate
- **Per task commit:** `sh scripts/smoke.sh ssh` (or the specific reconciled section) + `nginx -t` inside the switch.
- **Per wave merge:** `make test`.
- **Phase gate:** `make test` green + `make verify EXPECT=new` exit 0 before `/gsd-verify-work`.

### Wave 0 Gaps
- [ ] Reconcile `section_ssh` proxied-hop group + `selector_now()`/`restore_ssh_state`/`finish_ssh_state` onto the switch (see Pitfall 4 table).
- [ ] Reconcile `section_hostkey` oracle probe (L2199) and any `proxy`/`app.demo.test:22` references onto the switch.
- [ ] Add VAL-01/VAL-02 assertions (app-new pre-flip, client-container context, port 80 + 22).
- [ ] Add `verify.sh --target app-new` mode (both probes from client container; expectation fixed NEW).
- [ ] Re-enable `section_ssh` + `section_hostkey` in the `all` runner (remove the `# Phase 6 (SW-03)` deferral markers, L2261/L2276).
- [ ] Add the stream block to `switch/nginx.conf` (this is the production edit the tests assert against).

## Security Domain

> `security_enforcement` enabled, ASVS L1. This is a demonstration artifact (explicitly out of scope: production hardening — REQUIREMENTS.md), so controls are demo-appropriate and mostly inherited/unchanged.

### Applicable ASVS Categories
| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V1 Architecture | yes | The tier that reports evidence cannot alter it (`:ro` mounts); no container-runtime socket mounted anywhere (D-29) — unchanged |
| V5 Input Validation | partial | Stream is opaque TCP; no request parsing. The http `$backend_is_valid` guard is unchanged; stream deliberately has no analogue (an SSH client can't render a diagnostic) |
| V7 Error Handling/Logging | yes | Stream log to `/dev/stdout` only; JSON evidence sink escaping unchanged (D-46, log_format escape=json) |
| V12 Communication | yes | No new host-exposed ports; `:22` stays unpublished (D-15/D-38) |

### Known Threat Patterns (from the project's own threat IDs)
| Pattern | STRIDE | Mitigation (status this phase) |
|---------|--------|--------------------------------|
| `demo:demo` credential reachable from host if `:22` published (T-01-02) | Elevation | Keep `:22` unpublished; client reaches switch:22 over Docker net — **do not add a `ports:` entry** |
| Proxy tier forging a backend identity (T-05-01/EV2-02) | Spoofing | Stream relays opaquely; the switch's stream log carries `selector=` (its OWN choice) beside `backend=` (label from selector), never a claimed backend identity — honesty preserved from v1 |
| Stream log corrupting the evidence sink read by the status page (D-46) | Tampering/DoS | Stream `access_log` to `/dev/stdout` only, never `/var/log/demo/access.log` |
| Static proxies exposing host ports (T-05-04) | Info disclosure | proxies publish nothing; `app-new` validation runs from the client container over Docker DNS |

No new secrets, no new external surface, no new packages — the security posture is inherited from Phases 3–5 and preserved.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Docker Compose | whole rig | ✓ (rig runs today) | v2+ | — |
| nginx `--with-stream` | switch SSH stream | ✓ | 1.30-alpine (pinned) | — (asserted by ENV-04) |
| OpenSSH client (in `client` image) | SSH probes | ✓ | image-provided | — |
| POSIX sh + `nc`/`curl`/`awk`/`sed` | test harness | ✓ | busybox/host | — |

**Missing dependencies:** none. Everything required is already present and proven in the running rig.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Two nginx stream hops relay SSH with no protocol concern beyond default idle `proxy_timeout` (10 min/hop, irrelevant for a demo) | Summary / Pitfall 6 | LOW — nginx stream is opaque L4; v1 proved one hop; a second identical relay adds no parsing. If a long idle session is wanted, set `proxy_timeout` explicitly on the switch stream server. |
| A2 | `$server_port` remains a valid map key in stream context (v1 used it; the map returns `default` regardless) | Pattern 1 | NONE — v1's identical map ran in stream context and passed; the key value is immaterial since only `default` is defined. [effectively VERIFIED via v1 proof] |
| A3 | VAL-01/VAL-02 are already live post-Phase-5 (proxy-new HTTP:80 + static SSH:22 + alias) and need only test coverage, not new production wiring | Phase Requirements | LOW — verified by reading proxy-new/nginx.conf + compose.yaml; if a Phase-5 regression exists, `make test` section_proxy would already be red. |

**All three assumptions are low/no risk and cross-checked against in-repo evidence.** No user confirmation required before planning.

## Open Questions

1. **Should `verify.sh --target app-new` be a `--target <name>` flag or a positional/second mode?**
   - What we know: current `verify.sh` takes one positional `<old|new>` (the expectation) and has a `VERIFY_SSH_HOST` test seam. EV2-04 asks for "a mode/flag to target app-new.demo.test directly."
   - What's unclear: exact CLI ergonomics (planner/discuss decision).
   - Recommendation: add `--target app-new` (default `switch`) that redirects BOTH probes to the client container against `app-new.demo.test` and fixes expectation to NEW; keep the existing positional for through-switch mode. Surface via a Make target (e.g. `make verify-new-stack`).

2. **Do the SSH-02 config-shape assertions grep `switch/nginx.conf` or keep an assertion against archived `proxy/nginx.conf`?**
   - What we know: the LIVE stream block is on the switch now; `proxy/nginx.conf` is inert but present.
   - Recommendation: point SSH-02/D-46 assertions at `switch/nginx.conf` (the live config). Leave `proxy/` untouched for Phase 7's MIG-03. Do not assert against the archived file.

## Sources

### Primary (HIGH confidence)
- `switch/nginx.conf`, `switch/active-proxy.conf` — the Phase-5 switch (http block, includes, oracle `/active-proxy`, no stream yet) [VERIFIED: read]
- `proxy-old/nginx.conf`, `proxy-new/nginx.conf` — static proxies with inert `:22` stream (`upstream ssh { server server-old/new:22; }`, `listen 22; proxy_pass ssh;`) and HTTP on `:80` [VERIFIED: read]
- `compose.yaml` — topology, `app-new.demo.test` alias on proxy-new, switch `depends_on` both proxies healthy, no `:22` publish, D-15 note [VERIFIED: read]
- `git show <3b7dc6c>:proxy/nginx.conf` stream block — the exact v1 pattern to re-home (log_format demo_stream, stdout access_log, upstream old/new:22, shared include, `map $active_backend $stream_label`, `listen 22; proxy_pass $active_backend;`) [VERIFIED: git history]
- `scripts/verify.sh` — through-switch both-protocol verifier, exit vocabulary, `VERIFY_SSH_HOST` seam [VERIFIED: read]
- `scripts/flip.sh` — one-word edit + reload + health gate on both proxies (no SSH change needed) [VERIFIED: read]
- `scripts/smoke.sh` — deferred `section_ssh`/`section_hostkey`, stale `proxy`/`active-backend` references, `all` runner deferral markers [VERIFIED: read + grep]
- `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md` — SW-03/VAL-01/VAL-02/EV2-04 definitions, Phase 6 success criteria, Phase 7 scope fences [VERIFIED: read]

### Secondary / Tertiary
- nginx `stream` module opaque-relay semantics — established knowledge, corroborated by v1's working one-hop implementation in this repo. [ASSUMED, cross-checked against in-repo proof]

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new packages; all tooling pinned and running.
- Architecture: HIGH — re-home of a proven v1 pattern; every wire verified against live files.
- Pitfalls: HIGH — each is either observed in v1's comments or derived from a grep of the actual deferred tests.

**Research date:** 2026-07-22
**Valid until:** 2026-08-21 (stable; config-only phase on a pinned image, no fast-moving deps)
</content>
</invoke>

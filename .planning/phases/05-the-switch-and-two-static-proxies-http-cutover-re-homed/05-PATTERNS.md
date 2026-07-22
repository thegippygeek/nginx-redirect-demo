# Phase 5: The Switch and Two Static Proxies — HTTP Cutover Re-Homed - Pattern Map

**Mapped:** 2026-07-22
**Files analyzed:** 9 (4 new, 5 modified)
**Analogs found:** 9 / 9 (every file has a direct in-repo v1 analog)

> Brownfield restructure. There is NO net-new mechanism here. Every new file is a
> reshaping of an existing, verified v1 file. The planner's job is to copy the
> established idiom and apply the small, enumerated deltas — not to invent.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `switch/nginx.conf` (new) | config (nginx front proxy) | request-response | `proxy/nginx.conf` (http block) | exact — same file, upstreams re-pointed + 1 field |
| `switch/active-proxy.conf` (new) | config (flip selector) | request-response | `proxy/active-backend.conf` | exact — verbatim shape, renamed var |
| `proxy-old/nginx.conf` (new) | config (static proxy) | request-response | `proxy/nginx.conf` (reduced) | role-match — same file stripped to single upstream |
| `proxy-new/nginx.conf` (new) | config (static proxy) | request-response | `proxy-old/nginx.conf` (this phase) | exact — mirror, one string differs |
| `compose.yaml` (mod) | config (compose topology) | orchestration | its own `proxy`/`server-*` service blocks | exact — split one service into three |
| `status/status.py` (mod) | service (evidence render) | request-response | its own `read_config`/`_render_row` | exact — env re-point + 1 render field |
| `scripts/flip.sh` (mod) | script (cutover) | event-driven | its own current body | exact — rename `proxy`→`switch`, CONF path |
| `scripts/smoke.sh` (mod) | test (smoke suite) | batch | its own `section_*` functions | exact — rename fan-out + new assertions |
| `Makefile` (mod) | config (command surface) | event-driven | its own targets | exact — re-point `proxy`→`switch` |

---

## Pattern Assignments

### `switch/nginx.conf` (config, request-response) — NEW

**Analog:** `proxy/nginx.conf` — copy the **http block only** (lines 1-155). Phase 5 ships **NO stream block on the switch** (the entire `stream {}` block, `proxy/nginx.conf` lines 193-293, is dropped; SW-03 adds it in Phase 6, mirroring how v1 Phase 1 shipped HTTP-only).

Copy the file wholesale, then apply exactly four deltas:

**Delta 1 — re-point the upstreams** (analog lines 60-61):
```nginx
# analog (proxy/nginx.conf:60-61):
upstream old { server server-old:80; }
upstream new { server server-new:80; }
# switch:
upstream old { server proxy-old:80; }   # was server-old:80
upstream new { server proxy-new:80; }   # was server-new:80
```

**Delta 2 — rename the include** (analog line 66):
```nginx
# analog: include /etc/nginx/demo/active-backend.conf;   # <- defines $active_backend
# switch: include /etc/nginx/demo/active-proxy.conf;     # <- still defines $active_backend, map default old;
```
Keep the map guard block below it (analog lines 72-76) byte-for-byte — `$active_backend`
stays the variable name so `status.py:read_config` and `flip.sh` need no parser change.
The `proxy_pass http://$active_backend;` on the 9092 server (analog line 90) stays as-is
(no trailing slash — RESEARCH anti-pattern).

**Delta 3 — ADD the `remote` field to the JSON evidence format** (EV2-01). Analog `evidence` format (proxy/nginx.conf:38-42):
```nginx
log_format evidence escape=json
    '{"t":"$time_iso8601","ms":"$msec","path":"$uri","req":"$request_uri",'
    '"status":$status,"backend":"$upstream_http_x_backend",'
    '"bhost":"$upstream_http_x_backend_host","upstream":"$upstream_addr",'
    '"host":"$host","port":"$server_port"}';
```
Switch version adds `"remote":"$remote_addr",` as the third field (verified two-hop:
`$remote_addr` at the switch is the real client):
```nginx
log_format evidence escape=json
    '{"t":"$time_iso8601","ms":"$msec","remote":"$remote_addr","path":"$uri","req":"$request_uri",'
    '"status":$status,"backend":"$upstream_http_x_backend",'
    '"bhost":"$upstream_http_x_backend_host","upstream":"$upstream_addr",'
    '"host":"$host","port":"$server_port"}';
```
Keep `escape=json` — it is a security control (log injection, ASVS V5), not cosmetic.

**Delta 4 — rename the oracle location** (analog lines 147-154). The `:8081` health +
oracle server stays identical in shape; rename `/active-backend` → `/active-proxy` for
readability (optional but recommended — `flip.sh`'s `ORACLE` must match whichever name):
```nginx
server {
    listen 8081;
    access_log off;
    default_type text/plain;
    location = /nginx-health  { return 200 "ok\n"; }
    location = /active-proxy  { return 200 "$active_backend\n"; }   # was /active-backend
}
```

**Unchanged, copy verbatim:** the `demo` stdout log_format (lines 17-19), both
`access_log` sinks (lines 49, 55), `error_log` (line 56), the `$backend_is_valid`→503
guard (lines 72-95), and the 9093 literal-redirect server (lines 105-128) — keep the
literal `return 301 http://app.demo.test:9090$request_uri;` (open-redirect mitigation,
T-01-13). The switch sets **NO** `add_header X-Backend` of its own (EV2-02).

---

### `switch/active-proxy.conf` (config, request-response) — NEW

**Analog:** `proxy/active-backend.conf` (all 5 lines) — copy verbatim, retitle the header comment only:
```nginx
# switch/active-proxy.conf — THE ONLY FILE THE PRESENTER EDITS
# Change `old` to `new` to cut over. Nothing else.
map $server_port $active_backend {
    default old;
}
```
Keep the map body byte-identical to the analog (`map $server_port $active_backend { default old; }`)
so `read_config` (which parses `default <x>;` and matches the variable spelling) and the
presenter-visible diff are unchanged. `old`/`new` now select `proxy-old`/`proxy-new` via
the switch's re-pointed upstreams — the selector file itself is topology-neutral.

---

### `proxy-old/nginx.conf` (config, request-response) — NEW

**Analog:** `proxy/nginx.conf` reduced to a **static single-upstream transparent proxy**.
This is v1's http block with the flip machinery removed. Reference shape (RESEARCH Pattern 1, verified two-hop):

```nginx
worker_processes 1;
events { worker_connections 1024; }
http {
    include /etc/nginx/mime.types;
    upstream backend { server server-old:80; }     # STATIC — the one delta vs proxy-new
    server {
        listen 80;
        default_type text/plain;
        location / {
            proxy_pass http://backend;              # static name, no $variable, no map
            proxy_set_header Host            $host;
            proxy_set_header X-Real-IP       $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            # NO add_header X-Backend — the backend owns identity (EV2-02 integrity)
        }
    }
    server {                                        # compose healthcheck target, copied from proxy/nginx.conf:147-154
        listen 8081;
        access_log off;
        location = /nginx-health { return 200 "ok\n"; }
    }
}
stream {                                            # configured now, inert until Phase 6 wires the switch (A2)
    upstream ssh { server server-old:22; }
    server { listen 22; proxy_pass ssh; }
}
```

**Deltas from `proxy/nginx.conf`:** drop both `log_format`s + the JSON evidence sink +
`/var/log/demo` mount (only the switch writes evidence now), drop the `map`/`$backend_is_valid`
guard, drop the `active-*.conf` include, drop the 9092/9093 listeners (this tier listens on
80 internally), drop the `/active-*` oracle location. **Critical integrity delta:** emit NO
identity header — verified exactly one `X-Backend` survives a transparent hop (the backend's),
and the smoke suite asserts it. `X-Backend`/`X-Backend-Host` pass through untouched by default
(no config needed).

---

### `proxy-new/nginx.conf` (config, request-response) — NEW

**Analog:** `proxy-old/nginx.conf` (above) — exact mirror. Two string deltas only:
```nginx
upstream backend { server server-new:80; }   # was server-old:80
upstream ssh     { server server-new:22; }   # was server-old:22
```
Everything else byte-identical. `app-new.demo.test` alias is set in compose, not here.

---

### `compose.yaml` (config, orchestration) — MODIFIED

**Analog:** the existing `proxy` service block (lines 63-107) plus the `server-old`/`server-new`
health idiom (lines 34-39). Split the single `proxy` service into three: `switch` + `proxy-old` + `proxy-new`.

**`switch`** inherits from the v1 `proxy` block (lines 63-107) almost verbatim:
- Mount `./switch` (not `./proxy`) as `/etc/nginx/demo:ro`, and `./switch/nginx.conf` as `nginx.conf` (analog lines 72-73).
- Keep the `demo-logs:/var/log/demo` rw mount (line 80) — **the switch is now the evidence writer** (was `proxy`).
- Keep `/etc/localtime:/etc/localtime:ro` (line 68), the `:8081/nginx-health` healthcheck (lines 85-90) verbatim, and `ports: ["127.0.0.1:9092:9092","127.0.0.1:9093:9093"]` (line 93).
- **Move the `app.demo.test` alias here** (analog lines 94-100) — SW-01, it leaves `proxy`.
- `depends_on` now gates on the **static proxies**, not the backends (Pitfall 1):
```yaml
depends_on:
  proxy-old: {condition: service_healthy}
  proxy-new: {condition: service_healthy}
```

**`proxy-old` / `proxy-new`** — new service blocks reusing the exact backend health idiom (analog server-old lines 34-39) and the proxy mount/localtime idiom:
```yaml
proxy-old:
  image: nginx:1.30-alpine
  volumes:
    - /etc/localtime:/etc/localtime:ro
    - ./proxy-old:/etc/nginx/demo:ro
    - ./proxy-old/nginx.conf:/etc/nginx/nginx.conf:ro
  healthcheck:                                    # verbatim from proxy/server-old idiom
    test: ["CMD","curl","-fsS","http://localhost:8081/nginx-health"]
    interval: 3s
    timeout: 2s
    retries: 10
    start_period: 3s
  networks: { default: { aliases: [app-old.demo.test] } }   # PROX-03
  depends_on:
    server-old: {condition: service_healthy}
  # NO ports: — internal-only, publishes nothing (Security: two static proxies expose nothing)
```
`proxy-new` mirrors with `./proxy-new`, `app-new.demo.test`, and `server-new`.

**`status` service** (analog lines 113-164): change its `./proxy` mount (line 136) to `./switch`
so it reads `active-proxy.conf`; keep `demo-logs:/var/log/demo:ro` and the `wget`/`127.0.0.1`
healthcheck (lines 154-159) unchanged. Add `environment:` overrides (or rely on status.py's new defaults):
`DEMO_PROXY_PROBE=http://switch:8081/nginx-health`, `DEMO_CONF_PATH=/etc/nginx/demo/active-proxy.conf`.
Keep **no** `depends_on: proxy` (the deliberate omission at lines 160-164 — the status page is most
valuable when the front tier is dead; do not add a `switch` dependency).

**`client` service** (line 179): `depends_on: [proxy]` → `depends_on: [switch]`.

---

### `status/status.py` (service, request-response) — MODIFIED

**Analog:** its own `read_config` + `_render_row` + module settings. Three deltas, no structural change.

**Delta 1 — re-point the two defaults** (lines 46, 48):
```python
CONF_PATH  = os.environ.get("DEMO_CONF_PATH",  "/etc/nginx/demo/active-proxy.conf")   # was active-backend.conf
PROXY_PROBE = os.environ.get("DEMO_PROXY_PROBE","http://switch:8081/nginx-health")     # was http://proxy:8081/...
```
(Compose may also set these via `environment:`; update the code defaults too so the module is honest standalone.)

**Delta 2 — render the new `remote` field** in `_render_row` (lines 226-234). The analog emits time/path/status/backend/ms/bhost; add `remote`:
```python
def _render_row(row):
    return {
        "time":    _hhmmss(row),
        "path":    str(row.get("path", "")),
        "status":  _as_int(row.get("status")),
        "backend": str(row.get("backend", "")).upper(),
        "ms":      _msec(row),
        "bhost":   str(row.get("bhost", "")),
        "remote":  str(row.get("remote", "")),      # NEW (EV2-01) — client's real addr from the switch log
    }
```
`read_config`/`read_log`/`build` need no change — `read_config` already parses `default <x>;`
(the map var spelling is preserved), and `read_log` passes unknown JSON keys through untouched.

**Delta 3 (UI, if in scope):** `status/index.html` surfaces `remote` (a low-emphasis column or
per-row annotation — presentation is a UI-SPEC decision per RESEARCH A1/Open Q1). Do NOT render
`upstream` (it now names the static proxy IP — expected, Pitfall 4; the analog already omits it).

---

### `scripts/flip.sh` (script, event-driven) — MODIFIED

**Analog:** its own current body. Rename fan-out with one gate-target change.

**Delta 1 — CONF path** (line 28): `CONF=proxy/active-backend.conf` → `CONF=switch/active-proxy.conf`.

**Delta 2 — every `exec -T proxy` → `exec -T switch`** (lines 84, 106, 118, 134, 182): the `nginx -t`,
`nginx -s reload`, the `:8081` oracle probe, and the `: > $EVIDENCE` truncation all now run in `switch`.

**Delta 3 — the health gate** (lines 83-92): v1 probes `server-old`/`server-new` through the proxy.
Re-point the loop to probe `proxy-old`/`proxy-new` health (Pitfall 2 — the switch's reload parse
depends on the proxies resolving, not the backends directly):
```sh
for _p in proxy-old proxy-new; do
    if ! docker compose exec -T switch curl -fsS --max-time 2 "http://$_p:8081/nginx-health" >/dev/null 2>&1; then
        echo "REFUSING TO FLIP: $_p is not answering."
        ...
```
`ORACLE=http://localhost:8081/active-proxy` if the oracle location was renamed in switch/nginx.conf.
Keep the six-step structure, the `diff -u` money-shot (lines 99-103), the exit-code checks, and the
reset-vs-forward split (lines 181-189) untouched.

---

### `scripts/smoke.sh` (test, batch) — MODIFIED

**Analog:** its own seven `section_*` functions (`section_backends`:32, `guard_check`:90,
`section_proxy`:116, `section_redirect`:176, `section_cutover`:340, `section_ssh`:1041,
`section_walkthrough`:1641, `section_hostkey`:1891). This is the largest task by volume
(67 `exec -T proxy`/`logs proxy`/`active-backend` hits; ~128 `proxy` tokens total).

**Mechanical rename deltas:**
- `docker compose exec -T proxy ...` → `... -T switch ...` (nginx -t, reload, oracle, curl-through). e.g. lines 92-108, 121-122, 170-171.
- `docker compose logs proxy` → `docker compose logs switch` (evidence grep, lines 150-151, 155-156).
- `proxy/active-backend.conf` → `switch/active-proxy.conf` (guard_check backup/restore/sed, lines 88-108).
- `proxy/nginx.conf` grep-assertions → `switch/nginx.conf` (e.g. add_header honesty line 146-147, 301 target line 194).
- `docker compose port proxy 9092/9093` → `... port switch ...` (lines 164, 199).

**New assertions to add (Wave 0 gaps):**
- PROX-01/02: `docker compose exec -T switch curl -fsS http://proxy-old/whoami | grep -qx 'OLD server-old'` (and proxy-new→NEW).
- PROX-03 aliases: `docker compose exec -T switch getent hosts app-old.demo.test app-new.demo.test`.
- EV2-01: `curl -s localhost:9094/api/status | jq -e '.rows[0].remote'` and assert it ≠ a proxy container IP.
- EV2-02 integrity: `docker compose exec -T switch curl -sD- http://proxy-old/whoami | grep -ci '^X-Backend:'` = 1 (exactly one; no proxy-injected identity).
- SW-01 chain: `docker compose logs proxy-old | grep -q server-old`.

**SSH sections decision (Open Q2):** the static proxies ship their SSH stream now (A2), so the
direct `app-old`/`app-new:22` path is testable and those assertions can stay green; defer only the
**switch's** SSH:22 assertions to Phase 6. The honesty assertion at line 146-147 (no `add_header` in
the config) must now run against BOTH `proxy-old/nginx.conf` and `proxy-new/nginx.conf`.

---

### `Makefile` (config, event-driven) — MODIFIED

**Analog:** its own targets. Re-point every `proxy`-container operation to `switch`.

- `up` (line 22): `exec -T proxy sh -c ': > /var/log/demo/access.log'` → `-T switch`.
- `clear-evidence` (line 198): same `-T proxy` → `-T switch`.
- `logs` (line 39) / `logs-demo` (line 53): `docker compose logs -f proxy server-old server-new` → `switch server-old server-new` (drop the two static proxies as noise per A4; add `proxy-old proxy-new` only if the presenter wants to see the hop — cosmetic). Keep the awk `backend=` colour matcher (lines 53-56) unchanged — `X-Backend` still carries identity across two hops.
- `reload` (lines 98-101): `exec proxy nginx -t` / `nginx -s reload` → `exec switch ...`.
- `reset` (lines 71-75): re-point the canonical-file printf to `switch/active-proxy.conf` — update the path AND the header-comment filename in the printf string, keep the `map $$server_port $$active_backend { default old; }` body byte-identical (Pitfall 6; note the doubled `$$` for Make).
- `flip`/`flip-old`/`flip-new` (lines 110-117): no change — they delegate to `flip.sh`, which owns the container name.
- `ssh`/`fix-hostkeys`/`rearm`/`verify` (Phase 6 SSH surface): leave as-is this phase; the `ssh` target's `app.demo.test` destination already resolves to the switch once the alias moves.

---

## Shared Patterns

### Compose healthcheck idiom (curl on :8081)
**Source:** `compose.yaml:34-39` (server-old) / `85-90` (proxy) — identical shape.
**Apply to:** `switch`, `proxy-old`, `proxy-new`.
```yaml
healthcheck:
  test: ["CMD", "curl", "-fsS", "http://localhost:8081/nginx-health"]
  interval: 3s
  timeout: 2s
  retries: 10
  start_period: 3s
```
`curl` is in the stock `nginx:1.30-alpine` (verified 8.21.0) — no `apk add`, no build.

### Directory bind-mount (never single-file), host-local time
**Source:** `compose.yaml:68-73` (proxy) / `136` (status).
**Apply to:** all three nginx tiers.
Mount the *directory* (`./switch:/etc/nginx/demo:ro`) plus the config file, and
`/etc/localtime:/etc/localtime:ro` — a single-file mount strands on an editor inode-replace
(RESEARCH anti-pattern / v1 Pitfall 10); localtime keeps all timestamps in the room's wall clock.

### Backend-owned identity — NO proxy add_header
**Source:** `proxy/nginx.conf:157-160` (trailing comment) — "This proxy sets NO identity header of its own."
**Apply to:** `switch`, `proxy-old`, `proxy-new` (all three tiers).
`X-Backend`/`X-Backend-Host` are the backend's own response headers; nginx forwards upstream
response headers by default across both hops. `$upstream_http_x_backend` reads the immediate
upstream's response, so `backend=` carries the true value. Any tier adding its own `X-Backend`
corrupts the evidence chain (EV2-02, ASVS V10). Smoke asserts exactly one `X-Backend` per hop.

### Health-cascade depends_on (parse-time DNS resolution)
**Source:** `compose.yaml:105-107` (proxy gates on backends).
**Apply to:** deepen one tier — `proxy-old`→`server-old`, `proxy-new`→`server-new`, `switch`→`proxy-old`+`proxy-new`.
nginx resolves `upstream ... server <name>` at parse time and aborts if Docker DNS can't answer
yet (v1 Pitfall 4 / RESEARCH Pitfall 1). This cascade makes `up -d --wait` deterministic (MIG-01).

### Config-read + JSON-row-parse (status)
**Source:** `status.py:read_config` (87-136) parses `default <x>;`; `read_log` (139-169) skips torn lines.
**Apply to:** unchanged — the `map ... { default old; }` shape and the `$active_backend` variable
spelling are preserved in `active-proxy.conf`, so neither reader changes. Only `_render_row` gains `remote`.

### Evidence truncation into the writer tier (never the reader)
**Source:** `flip.sh:181-182` and `Makefile:22,198` — `exec -T proxy sh -c ': > access.log'`.
**Apply to:** re-point to `exec -T switch` — the switch now owns the rw evidence mount; status stays `:ro`.
Truncate, never unlink (nginx holds the O_APPEND descriptor).

---

## No Analog Found

None. Every file in this phase has a direct v1 analog in-repo. The only genuinely new
*behaviour* is a single added JSON field (`remote`/`$remote_addr`) whose mechanism
(`$remote_addr` capture, `escape=json`, status render) is entirely inherited from v1 —
it is a one-line addition to an existing verified format, not a new pattern.

## Metadata

**Analog search scope:** repo root — `proxy/`, `status/`, `scripts/`, `compose.yaml`, `Makefile`.
**Files scanned:** `proxy/nginx.conf`, `proxy/active-backend.conf`, `compose.yaml`, `status/status.py`, `scripts/flip.sh`, `Makefile`, `scripts/smoke.sh` (structure + reference grep).
**Pattern extraction date:** 2026-07-22
</content>
</invoke>

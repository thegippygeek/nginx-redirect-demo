# Phase 6: The SSH Stream Flip and Pre-Flip Validation - Pattern Map

**Mapped:** 2026-07-22
**Files analyzed:** 4 (2 modified core, 1 modified test, 1 modified script; 2 confirmed no-op)
**Analogs found:** 4 / 4 — pure re-homing, every file has a DIRECT analog (live Phase-5 sibling or the v1 stream block preserved on disk / in git `3b7dc6c`)

This phase is re-homing + reconciliation, not construction. Copy the proven idiom, retarget two strings, fix stale references. No file lacks a clean analog.

## File Classification

| Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---------------|------|-----------|----------------|---------------|
| `switch/nginx.conf` (ADD stream block) | config | streaming (L4 TCP relay) | `proxy/nginx.conf` `stream{}` block (on disk L201-293; git `3b7dc6c`) | exact — verbatim v1 block, 2 string deltas |
| `scripts/smoke.sh` (reconcile + re-enable `section_ssh`/`section_hostkey`) | test | request-response / event-driven | the deferred sections' own bodies + Phase-5's already-reconciled `section_proxy`/`section_cutover` as style template | exact (self) + role-match (style) |
| `scripts/verify.sh` (add `--target app-new` mode) | test/utility | request-response | its own current v1 body (L91-186) | exact (self) |
| `scripts/flip.sh` | script | event-driven | **no change** — already switch-homed (L28/L121) | no-op (confirmed) |
| `compose.yaml` | config | — | **no change** — no `:22` publish (D-15); alias already live | no-op (confirmed) |

## Pattern Assignments

### `switch/nginx.conf` — ADD a stream block (config, streaming)

**Analog:** `proxy/nginx.conf` `stream { ... }` block, lines 201-293 (still verbatim on disk; git rev `3b7dc6c`). This is v1's battle-tested block whose comments encode measured decisions (D-40, D-46, IPv4-wildcard gotcha). Copy it, change exactly two strings.

**Copy-from excerpt (verbatim v1, `proxy/nginx.conf:201-293`) with the only two deltas marked:**
```nginx
stream {
    log_format demo_stream '$remote_addr -> :$server_port ssh backend=$stream_label '
                           'selector=$active_backend upstream=$upstream_addr status=$status '
                           'bytes=$upstream_bytes_sent/$upstream_bytes_received sess=$session_time';

    # STDOUT ONLY (D-46): the JSON evidence sink is parsed by the status service,
    # which SKIPS non-JSON lines. A stream line there is invisible rot.
    access_log /dev/stdout demo_stream;

    upstream old { server proxy-old:22; }   # DELTA 1a: was server-old:22
    upstream new { server proxy-new:22; }   # DELTA 1b: was server-new:22

    # THE SAME FILE the http block includes — D-39. A map is valid in both contexts.
    include /etc/nginx/demo/active-proxy.conf;   # DELTA 2: was demo/active-backend.conf

    map $active_backend $stream_label {
        default "?";
        old     OLD;
        new     NEW;
    }

    server {
        listen 22;
        proxy_pass $active_backend;
    }
}
```

**The ONLY deltas (3 string edits, 2 kinds):**
1. Upstreams `server-old:22`/`server-new:22` → `proxy-old:22`/`proxy-new:22` (mirrors the http block's own Phase-5 re-point at `switch/nginx.conf:72-73`).
2. Include path `demo/active-backend.conf` → `demo/active-proxy.conf` (mirrors http block include at `switch/nginx.conf:78`).

**Everything else copies verbatim** — the log_format, the `/dev/stdout` access_log, the `map $active_backend $stream_label`, `listen 22; proxy_pass $active_backend;`, and all the load-bearing comments.

**MUST NOT (from the analog's own comments + RESEARCH Pitfall 1):**
- `access_log` stays `/dev/stdout demo_stream` — NEVER `/var/log/demo/access.log` (D-46, corrupts the JSON evidence sink the status service parses).
- No `worker_shutdown_timeout` on the switch (D-40 in-flight-session behaviour; `proxy/nginx.conf:165-191`).
- No `ports: ["...:22:22"]` on the switch (D-15/D-38, T-01-02).
- No `$backend_is_valid` stream analogue (deliberate — a bad selector logs status=500; `proxy/nginx.conf:281-288`).

**Sibling proof (D-39, already live):** the switch's EXISTING http block already includes the SAME map file at `switch/nginx.conf:78` (`include /etc/nginx/demo/active-proxy.conf;`). After this edit the include appears EXACTLY TWICE in `switch/nginx.conf` — once in http, once in stream — which is what the reconciled `section_ssh` D-39 assertion greps for. Placement: add the `stream{}` block at top level as a sibling of `http{}` (after the http block closes at L167, before/after the trailing comment).

**Health-gating comes free:** the switch's existing `depends_on: {proxy-old, proxy-new: service_healthy}` (`compose.yaml:111-113`) and `flip.sh`'s dual-proxy health probe (`flip.sh:86-87`) already gate the parse-time upstream resolution (RESEARCH Pitfall 3).

---

### `scripts/smoke.sh` — reconcile + re-enable `section_ssh` / `section_hostkey` (test)

**Analog A (self):** the deferred section bodies + shared helpers, currently intact but gated out of the `all` runner.
**Analog B (style template):** Phase-5's already-reconciled `section_proxy` / `section_cutover` show how to speak the switch topology (`docker compose exec -T switch ...`, `/active-proxy` endpoint).

**Shared helpers to reconcile (the real re-home cost — RESEARCH Pitfall 4 table):**

Copy-from (current v1, stale) → reconcile-to (switch):

```sh
# selector_now()  L1080
sed -n '...' proxy/active-backend.conf | head -1       # -> switch/active-proxy.conf

# restore_ssh_state()  L1112-1117  and  finish_ssh_state()  L1121-1126
cp proxy/active-backend.conf "$_sshbak"                 # -> switch/active-proxy.conf
docker compose exec -T proxy nginx -s reload            # -> exec -T switch nginx -s reload
```

**Full stale-reference reconciliation (verbatim from RESEARCH Pitfall 4):**

| Location(s) | Current (v1) | Reconcile to (switch) |
|-------------|--------------|------------------------|
| `selector_now()` L1080 | `proxy/active-backend.conf` | `switch/active-proxy.conf` |
| `restore_ssh_state`/`finish_ssh_state` L1114-1123 | `proxy/active-backend.conf`, `exec -T proxy nginx -s reload` | `switch/active-proxy.conf`, `exec -T switch nginx -s reload` |
| SSH-01 listener L1331 | `exec -T proxy nc -z 127.0.0.1 22` | `exec -T switch nc -z 127.0.0.1 22` |
| SSH-02 / D-39 L1351-1372 | `proxy/nginx.conf`, `demo/active-backend.conf`, `proxy/active-backend.conf` | `switch/nginx.conf`, `demo/active-proxy.conf`, `switch/active-proxy.conf` |
| D-46 L1401-1405 | `proxy/nginx.conf` | `switch/nginx.conf` |
| EVID-01 stream L1417,1423 | `docker compose logs proxy` | `docker compose logs switch` |
| oracle probes L1506, L1633, L2199 | `exec -T proxy curl ... :8081/active-backend` | `exec -T switch curl ... :8081/active-proxy` (**endpoint renamed** `/active-backend` → `/active-proxy`) |

**Do NOT touch** the direct-to-backend group (BACK-04/BACK-05 banner/host-key vs `server-old`/`server-new`, e.g. L1198-1205) — backends are unchanged. Only the proxied-hop group and shared helpers move.

**Capture idiom to preserve (analog `smoke.sh:1173-1205`, also `verify.sh:117-138`):** assign the ssh invocation via command substitution with `2>&1`, read `$?` on the NEXT line, grep the captured variable — NEVER pipe the invocation (`ssh ... | head` reports the pipe's last status; a host-key failure reads as exit 0). Keep `timeout 10` wrapping every invocation.

**Add VAL-01/VAL-02 pre-flip assertions (new, but mechanically identical to existing probes; source RESEARCH Pattern 2):**
```sh
# BOTH probes from the client container — app-new.demo.test is Docker-DNS-only (compose.yaml alias on proxy-new), port 80 not 9092.
docker compose exec -T client curl -fsS http://app-new.demo.test/whoami        # expect: NEW server-new
docker compose exec -T client timeout 10 ssh $SSH_OPTS demo@app-new.demo.test true   # banner: NEW server-new
# concurrently, through the switch, still OLD:
curl -fsS localhost:9092/whoami                                                # expect: OLD server-old
```

**Re-enable in the `all` runner (RESEARCH Pitfall 5):** uncomment `# section_ssh` (L2261) and `# section_hostkey` (L2276), removing the `# Phase 6 (SW-03)` deferral markers (L2256-2259, L2272-2276). Preserve ordering: `section_ssh` after `section_cutover` (leaves rig on OLD); `section_hostkey` LAST (most destructive — flips, regenerates server-new host keys, restores on exit). The dispatch cases at L2245/L2247 (`ssh)`/`hostkey)`) already exist and are untouched.

---

### `scripts/verify.sh` — add `--target app-new` mode (test/utility)

**Analog:** its own current body. HTTP probe `verify.sh:104-113`, SSH probe `verify.sh:135-149`, exit vocabulary `verify.sh:9-19` (0 agree+match, 1 mismatch/unreadable, 2 usage, 3 protocols disagree), `VERIFY_SSH_HOST` test seam `verify.sh:33`.

**Copy-from (current defaults, `verify.sh:32-33`):**
```sh
HTTP_URL=http://localhost:9092/whoami
SSH_TARGET=${VERIFY_SSH_HOST:-app.demo.test}
```

**Delta for `--target app-new` mode (RESEARCH Pitfall 2 — different context AND port):**
- BOTH probes run from inside the client container (not host): HTTP `docker compose exec -T client curl -fsS http://app-new.demo.test/whoami` (port **80**, not 9092), SSH target `demo@app-new.demo.test`.
- Expectation fixed to **NEW** (proxy-new is static).
- Keep the existing positional `<old|new>` for through-switch mode as default (`--target switch`). Preserve the exit vocabulary and the capture-then-read-`$?` idiom (L135-136) unchanged. Recommended surface: a Make target (e.g. `make verify-new-stack`).

---

## Shared Patterns

### The one shared map file drives both protocols (D-39)
**Source:** `switch/nginx.conf:78` (http include) — the new stream block includes the identical path.
**Apply to:** the `switch/nginx.conf` stream block AND the reconciled SSH-02/D-39 assertion.
```nginx
include /etc/nginx/demo/active-proxy.conf;   # appears EXACTLY TWICE in switch/nginx.conf after Phase 6
```
`$active_backend` in http and in stream are independent variables in independent namespaces; a `map` is valid in both contexts, an `upstream` is not — which is why the SELECTOR (not the target) lives in the shared file.

### One-word flip, no SSH change to flip.sh
**Source:** `scripts/flip.sh:28,121` — already edits `switch/active-proxy.conf` and reloads the switch.
**Apply to:** confirm flip.sh is a no-op. The single reload of the switch flips BOTH the http and the new stream context because both include the one map file.
```sh
CONF=switch/active-proxy.conf                 # flip.sh:28
docker compose exec -T switch nginx -s reload # flip.sh:121  -> flips HTTP:9092 AND SSH:22
```

### The non-piped ssh capture idiom
**Source:** `verify.sh:135-138` and `smoke.sh:1198-1205`.
**Apply to:** every SSH probe added or reconciled (VAL-02, verify.sh app-new, section_ssh proxied group).
```sh
OUT=$(docker compose exec -T client timeout 10 ssh $OPTS demo@$TARGET hostname 2>&1)
RC=$?                                          # read on the NEXT line, never after a pipe
printf '%s\n' "$OUT" | grep -qx 'server-new'   # grep the VARIABLE, not the invocation
```

### Pre-flip validation via the Docker-DNS alias (bypasses the switch)
**Source:** `compose.yaml:144-149` (`app-new.demo.test` alias on proxy-new) + `proxy-new/nginx.conf` (:80 http, :22 stream, both live since Phase 5).
**Apply to:** VAL-01, VAL-02, verify.sh `--target app-new`. Reachable ONLY from the client container; HTTP on port 80.

## No Analog Found

None. This is pure re-homing — every file maps to a live Phase-5 sibling or the v1 stream block preserved verbatim on disk (`proxy/nginx.conf:201-293`) and in git (`3b7dc6c`). The `proxy/` directory MUST remain untouched (v1 preservation is Phase 7 / MIG-03).

## Metadata

**Analog search scope:** `switch/`, `proxy/`, `proxy-new/`, `scripts/`, `compose.yaml`, git history of `proxy/nginx.conf`.
**Files scanned:** switch/nginx.conf, proxy/nginx.conf, scripts/verify.sh, scripts/smoke.sh (helpers + all-runner), scripts/flip.sh, compose.yaml.
**Pattern extraction date:** 2026-07-22
</content>
</invoke>

---
phase: 05-the-switch-and-two-static-proxies-http-cutover-re-homed
plan: 01
subsystem: infra
tags: [nginx, docker-compose, reverse-proxy, stream-proxy, evidence-log]

# Dependency graph
requires:
  - phase: 01-foundation
    provides: proxy/nginx.conf http block, active-backend.conf selector idiom, :8081 health/oracle idiom
  - phase: 03
    provides: stream block idiom (inert SSH relay pattern)
provides:
  - switch/nginx.conf — the flip surface + evidence writer, upstreams re-pointed to the static proxies
  - switch/active-proxy.conf — the 5-line presenter-edited flip selector
  - proxy-old/nginx.conf — static transparent proxy to server-old (HTTP :80 + inert SSH :22)
  - proxy-new/nginx.conf — static transparent proxy to server-new (HTTP :80 + inert SSH :22)
  - EV2-01 remote/$remote_addr field on the switch's JSON evidence format
affects: [05-02 compose wiring + end-to-end HTTP-lands-on-OLD, 05-03 the flip, 06 switch SSH:22]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Three-tier topology: front switch selects between two static single-upstream proxies"
    - "Static transparent proxy: proxy_pass http://backend (fixed name, no map, no trailing slash)"
    - "Inert-from-birth SSH stream block on the static proxies (configured now, wired Phase 6)"
    - "Backend-owned identity across two hops: no tier emits add_header X-Backend"

key-files:
  created:
    - switch/nginx.conf
    - switch/active-proxy.conf
    - proxy-old/nginx.conf
    - proxy-new/nginx.conf
  modified: []

key-decisions:
  - "Selector variable stays $active_backend and old/new labels retained for v1 continuity; the map now selects a proxy, not a backend (assumption_delta: promote)"
  - "503 guard message filename updated active-backend.conf -> active-proxy.conf for presenter honesty (the mechanism is preserved byte-for-byte)"
  - "nginx -t verification requires a writable /var/log/demo — supplied via --tmpfs since that dir is a runtime compose volume absent from the isolated test container"
  - "REQUIREMENTS.md checkboxes left unmarked — these are runtime requirements not fully delivered by a config-only plan; completion is gated on 05-02 wiring + 05-03 flip"

patterns-established:
  - "Static single-upstream transparent proxy (proxy-old/proxy-new) as a reduction of v1's flip-in-place proxy"
  - "EV2-01 remote field: $remote_addr at the front switch is the true client address in the two-hop chain"

requirements-completed: []  # config foundation delivered; see 'Requirements' section — completion gated on 05-02/05-03

coverage:
  - id: D1
    description: "switch/nginx.conf loads under nginx -t with upstreams re-pointed to proxy-old:80 / proxy-new:80, carries the EV2-01 remote field, keeps escape=json, the literal 9093 redirect, the 503 guard, no identity add_header, and no stream block"
    requirement: "SW-01"
    verification:
      - kind: other
        ref: "docker run --rm --tmpfs /var/log/demo --add-host proxy-old:127.0.0.1 --add-host proxy-new:127.0.0.1 -v $PWD/switch/nginx.conf:/etc/nginx/nginx.conf:ro -v $PWD/switch:/etc/nginx/demo:ro nginx:1.30-alpine nginx -t"
        status: pass
    human_judgment: false
  - id: D2
    description: "switch/active-proxy.conf is the byte-identical 5-line flip surface (map $server_port $active_backend { default old; }) with both presenter comments intact"
    requirement: "SW-02"
    verification:
      - kind: other
        ref: "test $(wc -l < switch/active-proxy.conf) -eq 5 && test $(grep -c '^#' switch/active-proxy.conf) -eq 2"
        status: pass
    human_judgment: false
  - id: D3
    description: "proxy-old/nginx.conf and proxy-new/nginx.conf load under nginx -t, forward one fixed HTTP backend each (server-old:80 / server-new:80), carry an inert SSH stream (server-old:22 / server-new:22), expose a :8081 health listener, and emit no identity add_header"
    requirement: "PROX-01"
    verification:
      - kind: other
        ref: "docker run --rm --add-host server-old:127.0.0.1 -v $PWD/proxy-old/nginx.conf:/etc/nginx/nginx.conf:ro nginx:1.30-alpine nginx -t && docker run --rm --add-host server-new:127.0.0.1 -v $PWD/proxy-new/nginx.conf:/etc/nginx/nginx.conf:ro nginx:1.30-alpine nginx -t"
        status: pass
    human_judgment: false
  - id: D4
    description: "No tier emits an identity response header of its own — the backend's X-Backend must survive the two-hop chain untouched (EV2-02 / T-05-01, block_on: high). Config-level absence proven here; the runtime single-X-Backend assertion lands in 05-02."
    requirement: "EV2-02"
    verification:
      - kind: other
        ref: "grep -ci add_header across switch/nginx.conf, proxy-old/nginx.conf, proxy-new/nginx.conf (non-comment) = 0"
        status: pass
    human_judgment: true
    rationale: "EV2-02 is a block_on:high integrity threat (T-05-01). Config absence of add_header is necessary but not sufficient — the runtime assertion that exactly one X-Backend survives a transparent hop is deferred to 05-02 and must be human-confirmed before seal."

# Metrics
duration: 12min
completed: 2026-07-22
status: complete
---

# Phase 05 Plan 01: The Switch and Two Static Proxies (config authoring) Summary

**Four nginx configs authored and each proven under `nginx -t`: a front `switch` (flip surface + evidence writer with the new EV2-01 `remote` field, upstreams re-pointed to the static proxy tier) and two static single-upstream transparent proxies (`proxy-old`→server-old, `proxy-new`→server-new) each carrying an inert SSH stream.**

## Performance

- **Duration:** ~12 min
- **Started:** 2026-07-22T01:22Z (approx)
- **Completed:** 2026-07-22T01:34Z (approx)
- **Tasks:** 2
- **Files modified:** 4 created

## Accomplishments
- `switch/nginx.conf`: v1's `proxy/nginx.conf` http block re-homed — upstreams `old`→`proxy-old:80`, `new`→`proxy-new:80`; the EV2-01 `remote`/`$remote_addr` field added to the JSON evidence format (third field, `escape=json` preserved); include renamed to `active-proxy.conf`; oracle location `/active-backend`→`/active-proxy`; literal 9093 redirect and the `$backend_is_valid`→503 guard preserved; NO stream block, NO identity `add_header`.
- `switch/active-proxy.conf`: the byte-identical 5-line presenter-edited flip surface (retitled header only).
- `proxy-old/nginx.conf` + `proxy-new/nginx.conf`: static transparent proxies (`proxy_pass http://backend`, fixed name, no map, no trailing slash), a `:8081`/`nginx-health` listener, and an inert SSH `stream` block relaying `:22` to their one fixed backend (configured now per A2 so PROX-01/02 "never reconfigured" holds from birth). Neither tier emits an identity header.
- All four configs pass `nginx -t`; every integrity grep (no `add_header` on any tier, `remote` field present, literal redirect, no stream on the switch, 5-line flip file) passes.

## Task Commits

1. **Task 1: The switch config — upstreams re-pointed, +remote field** - `7844883` (feat)
2. **Task 2: The two static transparent proxies — inert SSH stream** - `1f01b20` (feat)

**Plan metadata:** committed separately with this SUMMARY.

## Files Created/Modified
- `switch/nginx.conf` - Front flip surface + evidence writer; upstreams point at the static proxy tier; carries EV2-01 remote field
- `switch/active-proxy.conf` - The only file the presenter edits to cut over (5 lines)
- `proxy-old/nginx.conf` - Static transparent proxy → server-old (HTTP :80 + inert SSH :22 + :8081 health)
- `proxy-new/nginx.conf` - Mirror → server-new (two string deltas)

## Decisions Made
- **Selector vocabulary promoted, not redesigned:** the `map` now selects a proxy but `$active_backend` and the `old`/`new` labels are retained (assumption_delta: promote) so `status.py:read_config` and `flip.sh` need no parser change.
- **503 guard message filename corrected** from `active-backend.conf` to `active-proxy.conf` — the guard mechanism is preserved verbatim; only the human-readable filename in the diagnostic was updated so a presenter hitting a typo'd selector is pointed at the file that actually exists. (Rule 1 correctness — wrong filename reference.)
- **REQUIREMENTS.md checkboxes deliberately left unmarked** — see Requirements section.

## Requirements

This plan's frontmatter lists `[SW-01, SW-02, PROX-01, PROX-02, EV2-01, EV2-02]`, but each of these describes **running, verified behaviour** (a service reachable at `app.demo.test`, a proxy that "statically forwards during the demo", "the log the status page reads", "propagates back through the proxy chain"). This plan delivers only the config artifacts and proves they load under `nginx -t`; wiring into the running rig and proving HTTP lands on OLD end-to-end is 05-02, and the flip is 05-03 (per the plan's own objective). Marking these Pending→Complete now would be dishonest, so the REQUIREMENTS.md checkboxes are left unchanged. The config foundation for all six is in place and traceable via the `coverage` block above.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Supplied /var/log/demo to the switch nginx -t verification**
- **Found during:** Task 1 (switch config verification)
- **Issue:** The plan's exact acceptance command mounts the `switch` dir but not `/var/log/demo`. The switch inherits v1's evidence sink `access_log /var/log/demo/access.log evidence;`, and `nginx -t` opens that file during the test — it failed with `open() "/var/log/demo/access.log" failed (2: No such file or directory)` because that directory is a runtime compose volume absent from the isolated test container. Syntax itself was reported OK.
- **Fix:** Added `--tmpfs /var/log/demo` to the verification `docker run` (verification-environment fix only; the config's log path is correct and matches v1 intentionally).
- **Files modified:** none (verification command only)
- **Verification:** `nginx -t` then reports `test is successful`, exit 0.
- **Committed in:** n/a (no file change; documented here)

**2. [Rule 1 - Bug] Corrected the 503 guard's filename reference**
- **Found during:** Task 1
- **Issue:** v1's 503 message names `active-backend.conf`; the switch's file is `active-proxy.conf`, so the diagnostic would point a presenter at a nonexistent file.
- **Fix:** Updated the literal string in the `return 503` to reference `active-proxy.conf`. Guard mechanism unchanged.
- **Files modified:** switch/nginx.conf
- **Verification:** `nginx -t` passes; no grep asserts the message body.
- **Committed in:** `7844883` (Task 1 commit)

---

**Total deviations:** 2 (1 blocking verification-env fix, 1 correctness filename fix)
**Impact on plan:** Both necessary; no scope creep. All plan artifacts delivered exactly as specified.

## Issues Encountered
None beyond the deviations above.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- The four configs are authored and load-clean; 05-02 can now wire them into `compose.yaml` (split the single `proxy` service into `switch` + `proxy-old` + `proxy-new`, move the `app.demo.test` alias to the switch, cascade `depends_on`) and prove HTTP lands on OLD end-to-end.
- **Block-on-high carry-forward for 05-02:** EV2-02 / T-05-01 requires a runtime assertion that exactly one `X-Backend` survives a transparent hop (config absence of `add_header` is proven here but not sufficient to seal).
- The switch's own SSH:22 stream is deliberately absent (SW-03 / Phase 6); the static proxies' SSH streams are configured but inert until the switch is wired.

## Self-Check

- **Created files:**
  - FOUND: switch/nginx.conf
  - FOUND: switch/active-proxy.conf
  - FOUND: proxy-old/nginx.conf
  - FOUND: proxy-new/nginx.conf
- **Commits:**
  - FOUND: 7844883 (Task 1)
  - FOUND: 1f01b20 (Task 2)

## Self-Check: PASSED

---
*Phase: 05-the-switch-and-two-static-proxies-http-cutover-re-homed*
*Completed: 2026-07-22*

---
phase: 02-the-live-http-cutover
plan: 01
subsystem: infra
tags: [nginx, docker-compose, posix-sh, make, access-log, json-logging, graceful-reload]

# Dependency graph
requires:
  - phase: 01-demo-up-http-lands-on-old
    provides: "proxy/nginx.conf with upstream old/new, the map-based active-backend.conf include, the $backend_is_valid guard, the X-Backend/X-Backend-Host identity headers, and the smoke.sh section idiom"
provides:
  - "scripts/flip.sh — the six-step cutover pipeline (health-gate both backends, rewrite one word, diff, nginx -t, reload with exit-code check, prove via the oracle, settle, confirm)"
  - "A second access_log sink writing JSON-escaped evidence to /var/log/demo/access.log on the shared named volume demo-logs"
  - "The unpublished :8081 listener with logging off: compose healthcheck target, reload oracle, and liveness probe for the status service"
  - "make flip / flip-old / flip-new / clear-evidence / logs-demo, plus up truncating the evidence log and logs covering all three services"
  - "section_cutover() in scripts/smoke.sh with settle_flip() and restore_flip_state() helpers — 23 assertions"
affects: [02-02 status service, 02-03 status page, 02-04 smoke/README completion, 03 ssh stream cutover]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Dual access_log fan-out: one human sink on stdout, one machine sink on a volume — an addition, never a migration"
    - "Reload oracle: the running config returns its own selector on an unpublished listener, so 'did the reload take' has a source that cannot lie"
    - "Health-gate before mutate: refuse and exit non-zero without touching the config file, so a refusal leaves the repo byte-identical"
    - "Evidence reset by truncation, never unlink — nginx holds the descriptor with O_APPEND"

key-files:
  created:
    - scripts/flip.sh
  modified:
    - proxy/nginx.conf
    - compose.yaml
    - Makefile
    - scripts/smoke.sh
    - README.md

key-decisions:
  - "The evidence log is mounted at /var/log/demo, never the image's own log directory — a volume mounted there pre-populates the stdout symlink and a reader hangs instead of erroring"
  - "log_format demo left byte-identical; the JSON evidence format is a second sink, so both Phase 1 stdout assertions still pass"
  - "The proxy healthcheck targets :8081/nginx-health, not :9092 — the smoke suite deliberately writes an invalid selector on 9092 and the container would flap unhealthy mid-suite"
  - "flip.sh truncates the evidence log LAST, after the confirming request: that request belongs to the take that is ending"
  - "worker_shutdown_timeout recorded as a Phase 3 question in a comment, never set as a directive"

patterns-established:
  - "settle_flip(): poll the :8081 oracle then sleep 200 ms — every timing-sensitive assertion calls it rather than re-deriving the wait"
  - "restore_flip_state()/finish_flip_state(): trap-based rig restoration mirroring guard_check()'s discipline for destructive sections"

requirements-completed: [CUT-01, CUT-02, CUT-03, CUT-05, EVID-01]

coverage:
  - id: D1
    description: "Flipping rewrites exactly one word in active-backend.conf, reloads cleanly, and leaves the file at five lines with both presenter comments"
    requirement: "CUT-01"
    verification:
      - kind: integration
        ref: "sh scripts/smoke.sh cutover#CUT-01 exactly one line differs from the pre-flip baseline"
        status: pass
      - kind: integration
        ref: "sh scripts/smoke.sh cutover#CUT-01 the include is still 5 lines with both presenter comments"
        status: pass
    human_judgment: false
  - id: D2
    description: "The identical command string returns OLD before the flip and NEW after it, from both the host and the client container via app.demo.test"
    requirement: "CUT-02"
    verification:
      - kind: integration
        ref: "sh scripts/smoke.sh cutover#CUT-02 the identical command string returns OLD, then NEW"
        status: pass
      - kind: integration
        ref: "sh scripts/smoke.sh cutover#CUT-02 the same command from the client container: OLD, then NEW"
        status: pass
    human_judgment: false
  - id: D3
    description: "The flip is decisive — twenty consecutive post-settle requests yield zero OLD observations"
    requirement: "CUT-03"
    verification:
      - kind: integration
        ref: "sh scripts/smoke.sh cutover#CUT-03 twenty consecutive post-settle requests yield zero OLD"
        status: pass
    human_judgment: false
  - id: D4
    description: "flip-old -> flip-new -> flip-old restarts no container, and flip-old clears the evidence for the next take"
    requirement: "CUT-05"
    verification:
      - kind: integration
        ref: "sh scripts/smoke.sh cutover#CUT-05 flip-old -> flip-new -> flip-old restarts no container"
        status: pass
      - kind: integration
        ref: "sh scripts/smoke.sh cutover#CUT-05 flip.sh old leaves the evidence log at 0 bytes"
        status: pass
    human_judgment: false
  - id: D5
    description: "The flip refuses when either backend is down, names it, exits non-zero, and leaves the config byte-identical"
    requirement: "CUT-01"
    verification:
      - kind: integration
        ref: "sh scripts/smoke.sh cutover#D-35 the config file is byte-identical after the refusal"
        status: pass
      - kind: integration
        ref: "sh scripts/smoke.sh cutover#D-35 the refusal names the backend that is not answering"
        status: pass
    human_judgment: false
  - id: D6
    description: "Both evidence sinks receive every request exactly once, healthcheck traffic reaches neither, and the JSON file survives truncation and concurrency"
    requirement: "EVID-01"
    verification:
      - kind: integration
        ref: "sh scripts/smoke.sh proxy#--- 17 passed, 0 failed --- (Phase 1 stdout regression guard)"
        status: pass
      - kind: integration
        ref: "sh scripts/smoke.sh cutover#EVID-01 one request appears exactly once in EACH of the two sinks"
        status: pass
      - kind: integration
        ref: "sh scripts/smoke.sh cutover#EVID-01 ten :8081 probes add zero evidence lines"
        status: pass
      - kind: integration
        ref: "sh scripts/smoke.sh cutover#EVID-01 thirty parallel requests produce exactly thirty complete lines"
        status: pass
    human_judgment: false
  - id: D7
    description: "The presenter narration reads correctly on stage: the printed diff is legible, the flip lands as an event, and the log views carry the moment across a room"
    verification: []
    human_judgment: true
    rationale: "Stage legibility and whether the flip reads as an event rather than a flicker require a human observer at projection distance — 02-VALIDATION lists this as manual-only."

# Metrics
duration: 35 min
completed: 2026-07-21
status: complete
---

# Phase 2 Plan 01: The Flip Pipeline and the Dual Evidence Log Summary

**A six-step `scripts/flip.sh` cutover (health-gate both backends → one-word rewrite → diff → `nginx -t` → reload with exit-code check → `:8081` oracle proof → settle → confirm), backed by a second JSON-escaped `access_log` sink on a shared named volume and an unpublished oracle/healthcheck listener.**

## Performance

- **Duration:** 35 min
- **Started:** 2026-07-21T08:20Z
- **Completed:** 2026-07-21T08:55Z
- **Tasks:** 3
- **Files modified:** 5 (1 created, 4 modified)

## Accomplishments

- **The money shot works end to end on this machine.** `make flip-new` prints the one-word diff, reloads gracefully, proves the reload landed, and the identical `curl http://localhost:9092/whoami` returns `NEW server-new`. `make flip-old` puts it back and clears the evidence. No container restarts in either direction.
- **The dual evidence sink shipped without breaking Phase 1.** `sh scripts/smoke.sh proxy` still reports exactly `--- 17 passed, 0 failed ---` — the single most important assertion in the phase. `log_format demo` and `access_log /dev/stdout demo;` are byte-identical to Phase 1.
- **The evidence file is a real regular file on the shared `demo-logs` volume at `/var/log/demo/access.log`**, one JSON object per line, ready for 02-02's status service. It carries `t`, `ms`, `path`, `req`, `status`, `backend`, `bhost`, `upstream`, `host`, `port`.
- **The unpublished `:8081` listener** answers `/nginx-health` (the proxy's first-ever compose healthcheck — the Phase 1 verifier's flagged gap) and `/active-backend` (the reload oracle), and writes to neither sink.
- **The smoke suite grew from 42 to 65 assertions**, all green, with a new `cutover` section of 23.

## Task Commits

1. **Task 1: Wave 0 — the cutover test section, red before anything exists** — `a5c2e2b` (test) — 15 FAILs, exit 1, exactly as required
2. **Task 2: The second evidence sink and the unpublished oracle listener** — `3e64dfd` (feat)
3. **Task 3: The flip pipeline and the presenter's command surface** — `4a9f69d` (feat) — the GREEN gate against Task 1's RED

_TDD gate sequence: `test(02-01)` → `feat(02-01)`. No refactor commit was needed; the implementation landed green against the pre-existing red section without restructuring._

## Files Created/Modified

- `scripts/flip.sh` (new, 175 lines) — the cutover pipeline. Takes `old`, `new` or `toggle`. Health-gates both backends before touching anything, rewrites the one word, prints a labelled unified diff, validates, reloads and checks the exit code, polls the `:8081` oracle up to 5 s, settles 200 ms, issues one confirming request, and — for `old` only — truncates the evidence log last.
- `proxy/nginx.conf` — added `log_format evidence` (JSON-escaped), the second `access_log`, and the unpublished `:8081` server block. The Phase 3 `worker_shutdown_timeout` question is recorded beside the reload-discipline comment as prose only.
- `compose.yaml` — top-level `demo-logs` volume, mounted rw into `proxy` at `/var/log/demo`; proxy healthcheck against `:8081/nginx-health`.
- `Makefile` — `flip`, `flip-old`, `flip-new`, `clear-evidence`, `logs-demo`; `up` now truncates the evidence log; `logs` now covers proxy and both backends (D-32).
- `scripts/smoke.sh` — `section_cutover()` (23 assertions), `settle_flip()`, `restore_flip_state()`, `finish_flip_state()`; `cutover` registered in the dispatcher, the `all` fan-out and the usage string.
- `README.md` — a presenter section on the cutover: the three commands, the printed diff, the live-edit alternative, the refusal, the two log views, and the between-takes reset.

## Decisions Made

- **Truncation is the last step of `flip.sh old`, not the first.** The confirming request from step 6 belongs to the take that is ending, not the one about to start, and the plan's acceptance criterion requires the file to be 0 bytes after the command returns. Putting the truncation first would have left one line behind.
- **`diff -u -L` with human labels** rather than the raw `mktemp` path. The audience sees `proxy/active-backend.conf (before)` / `(after)`, not `/var/folders/.../tmp.XXXX`. Verified working on this machine's BSD diff.
- **The smoke assertions read the evidence file by copying it out of the container to a host temp file** rather than nesting `docker compose exec -T proxy sh -c '...'` inside `assert`'s own `sh -c`. Two layers of quoting around JSON field patterns is a bug factory; one layer is readable.
- **Container identity for the `StartedAt` assertion comes from `docker compose ps -q`** rather than the literal `demo-proxy-1` names. Equivalent property, immune to a project-name change.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] The `escape=json` acceptance criterion collided with the explanatory comment**

- **Found during:** Task 2 (the evidence sink)
- **Issue:** The plan asserts `grep -c 'escape=json' proxy/nginx.conf` is exactly `1`. The comment explaining why the escaping is a security control used the literal token, making the count 2 — a false failure of an otherwise-correct config.
- **Fix:** Reworded the comment to "The JSON escaping below is a security control" so only the directive itself carries the token. The same care was applied pre-emptively to `access_log off`, `listen 8081` and `/var/log/demo/access.log`, all of which have exactly-one criteria.
- **Files modified:** `proxy/nginx.conf`
- **Verification:** `grep -c 'escape=json' proxy/nginx.conf` → 1; all other exactly-one criteria re-checked
- **Committed in:** `3e64dfd`

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** Cosmetic wording only. No behavioural change; the directive and the comment say the same thing.

## Issues Encountered

- **The `set -e` acceptance criterion cannot be satisfied literally.** Task 1 requires `grep -c 'set -e' scripts/smoke.sh` to be `0`, but Phase 1's own header comment reads ``Deliberately NOT `set -e`: every assertion runs...`` and pre-dates this plan. The criterion's intent — no *active* `set -e` — is met and was verified as `grep -v '^[[:space:]]*#' scripts/smoke.sh | grep -c 'set -e'` → `0`. Deleting Phase 1's explanatory comment to satisfy a literal grep would have been the wrong trade.
- **`section_cutover` stops and restarts `server-new`** as part of the D-35 assertion, so `make status` shows a younger uptime for that container after a suite run. This is by design and does not affect the CUT-05 no-restart assertion, which brackets only the three flips.

## User Setup Required

None — no external service configuration required. No language-ecosystem packages were installed in this plan; no `package.json`, `requirements.txt` or `Cargo.toml` exists or was introduced.

## Verification Results

| Check | Result |
|-------|--------|
| `sh scripts/smoke.sh proxy` (Phase 1 regression guard) | `--- 17 passed, 0 failed ---` |
| `sh scripts/smoke.sh cutover` | `--- 23 passed, 0 failed ---` |
| `sh scripts/smoke.sh` (all four sections) | `--- 65 passed, 0 failed ---` |
| `make reset && make test` from cold | green — the evidence volume's lifecycle holds |
| `docker compose exec -T proxy nginx -t` | passes |
| `docker compose ps proxy --format '{{.Health}}'` | `healthy` |
| `make flip-new` then `make flip-old` end to end | `NEW server-new` then `OLD server-old`, evidence cleared |
| `make -n flip flip-old flip-new clear-evidence logs logs-demo` | exit 0 under GNU Make 3.81 |
| `docker compose port proxy 8081` | no output — the oracle is unpublished |

Final state: stack running, all four services healthy, selector on **OLD**.

## Next Phase Readiness

**Ready for 02-02 (the status service).** Everything that plan needs now exists and is asserted:

- `/var/log/demo/access.log` — a real regular file on the named volume `demo-logs` (project-qualified `demo_demo-logs`), one JSON object per line, no symlink anywhere on the path.
- `http://proxy:8081/nginx-health` — the independent proxy-liveness probe Pitfall 6 requires, reachable over the Docker network and costing no evidence line.
- `proxy/active-backend.conf` — unchanged in shape, still five lines, ready to be bind-mounted `:ro` for the D-27 intent reading.
- The filter contract is settled: `port == "9092" and backend != ""`. The 9093 redirect logs `"port":"9093"` with an empty `backend`, and the `$backend_is_valid` 503 logs an empty `backend` too.

No blockers. Two notes for 02-02: the status volume mount must be `:ro`, and the status service must **not** declare `depends_on: proxy: {condition: service_healthy}` — it is most valuable precisely when the proxy is dead.

## Self-Check: PASSED

All seven key files verified present on disk. All three task commits (`a5c2e2b`, `3e64dfd`, `4a9f69d`) verified present in git history.

---
*Phase: 02-the-live-http-cutover*
*Completed: 2026-07-21*

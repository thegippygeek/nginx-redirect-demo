---
phase: 02-the-live-http-cutover
plan: 02
subsystem: evidence-service
tags: [python-stdlib, http-server, docker-compose, json-logs, stateless, nginx]

# Dependency graph
requires:
  - phase: 02-the-live-http-cutover
    plan: 01
    provides: "/var/log/demo/access.log as a real regular file on the demo-logs volume (one JSON object per line), the unpublished :8081/nginx-health liveness target with access_log off, the port==9092 and backend!=\"\" filter contract, scripts/flip.sh and settle_flip()"
provides:
  - "status/status.py — a stateless evidence service: build() recomputes the whole contract from active-backend.conf + the evidence log + an active proxy liveness probe, on every request"
  - "GET /api/status — the 15-key JSON contract 02-03 renders, including the server-side boundary.row_index and since_flip_s"
  - "GET /healthz (plain text) and GET / (serves /app/index.html, 404 until 02-03 ships it)"
  - "The `status` compose service: python:3.13-alpine, no build step, three read-only mounts, 127.0.0.1:9094 only, no health dependency on the proxy"
  - "27 new assertions in section_cutover() covering EVID-02, EVID-03, CUT-05 and threats T-02-04/05/06/09"
  - "status_get/jfield/jnest/jrow0/jrows and manual_flip() smoke helpers"
affects: [02-03 status page, 02-04 smoke/README completion, 03 ssh stream cutover]

# Tech tracking
tech-stack:
  added:
    - "python:3.13-alpine (Docker Official Image, 74.1 MB, Python 3.13.14) — image only; zero language-ecosystem packages installed"
  patterns:
    - "Stateless derivation: no counter, no cursor, no cache, no remembered last value — everything re-derived per request, so D-36's truncation resets all four readings atomically"
    - "Three-input availability gate: config unreadable OR log unreadable OR proxy not answering -> full UNAVAILABLE, every reading blanked"
    - "Late-bound configuration: paths resolved at call time, never as parameter defaults, so build() is drivable against fixtures"
    - "Main-guarded bind: importing the module runs no I/O and starts no listener"
    - "Contract-shaped smoke reading: anchored indent + quoted key, no JSON tool on the host (ENV-03)"

key-files:
  created:
    - status/status.py
  modified:
    - compose.yaml
    - scripts/smoke.sh
    - .gitignore

key-decisions:
  - "The status container mounts ./proxy as a DIRECTORY, not active-backend.conf as a single file — D-34 documents live-editing that file in an editor, and an inode replacement would freeze a single-file mount on stale content"
  - "The healthcheck probes 127.0.0.1, not localhost: busybox wget resolves localhost to ::1 and does not retry the next address family"
  - "json.dumps uses ensure_ascii=False so the UI-SPEC \"{path} — {reason}\" detail carries a real em dash rather than a backslash-u escape"
  - "boundary.row_index is derived FROM the window actually built, not computed separately, so it cannot disagree with the rows it describes"
  - "A boundary older than 60 s that has migrated past the 8-row window is reported as null rather than pointing at rows that are not there"

patterns-established:
  - "manual_flip() in smoke.sh: rewrite the selector and reload WITHOUT flip.sh, so a deliberately-constructed multi-transition window survives D-36's truncation"
  - "Negative mount assertions are paired with a positive readability check, so a missing service cannot satisfy the negation vacuously"

requirements-completed: [EVID-01, EVID-02, EVID-03, CUT-05]

coverage:
  - id: D1
    description: "GET /api/status returns config and traffic as two independently sourced keys — config from active-backend.conf, traffic from the evidence log — never a single merged value (D-27)"
    requirement: "EVID-02"
    verification:
      - kind: integration
        ref: "sh scripts/smoke.sh cutover#EVID-02 /api/status carries config AND traffic as two independently sourced keys"
        status: pass
      - kind: unit
        ref: "build() fixture#cfg NEW, traffic OLD, proxy up -> OK / PENDING with BOTH values present"
        status: pass
    human_judgment: false
  - id: D2
    description: "Editing active-backend.conf without reloading reports sync PENDING with config != traffic; reloading reports IN_SYNC"
    requirement: "EVID-02"
    verification:
      - kind: integration
        ref: "sh scripts/smoke.sh cutover#EVID-02 config edited without a reload: sync PENDING, config NEW, traffic still OLD"
        status: pass
      - kind: integration
        ref: "sh scripts/smoke.sh cutover#EVID-02 the reload closes the gap: sync IN_SYNC with config == traffic == NEW"
        status: pass
    human_judgment: false
  - id: D3
    description: "Stopping the proxy reaches UNAVAILABLE within 5 s with every reading blanked, even though the evidence file is still perfectly readable — the active liveness probe is the input that catches it (D-28)"
    requirement: "EVID-02"
    verification:
      - kind: integration
        ref: "sh scripts/smoke.sh cutover#EVID-02 stopping the proxy reaches UNAVAILABLE within 5 s"
        status: pass
      - kind: integration
        ref: "sh scripts/smoke.sh cutover#EVID-02 the UNAVAILABLE reading blanks BOTH readings and names proxy as the source"
        status: pass
      - kind: integration
        ref: "sh scripts/smoke.sh cutover#D-28 the evidence file is still readable — the proxy probe is what caught it"
        status: pass
      - kind: integration
        ref: "sh scripts/smoke.sh cutover#D-25 stopping the proxy does NOT stop the status service"
        status: pass
    human_judgment: false
  - id: D4
    description: "A readable log with an unreadable config collapses to FULL UNAVAILABLE with sync CANNOT_DETERMINE — never a half-lit page (UI-SPEC 3a)"
    requirement: "EVID-02"
    verification:
      - kind: integration
        ref: "sh scripts/smoke.sh cutover#EVID-02 an unreadable config yields FULL UNAVAILABLE — never a half-lit page"
        status: pass
      - kind: integration
        ref: "sh scripts/smoke.sh cutover#EVID-02 the unreadable config reports sync CANNOT_DETERMINE, failing_source config"
        status: pass
      - kind: unit
        ref: "build() fixture#log unreadable, config readable -> UNAVAILABLE / failing_source log"
        status: pass
    human_judgment: false
  - id: D5
    description: "The recent-requests table is honest: a uniquely-pathed :9092 request is rows[0] with the backend that answered it, while :9093 redirects, the 503 guard and healthcheck probes contribute nothing"
    requirement: "EVID-03"
    verification:
      - kind: integration
        ref: "sh scripts/smoke.sh cutover#EVID-03 a uniquely-pathed :9092 request is rows[0] with the backend that answered it"
        status: pass
      - kind: integration
        ref: "sh scripts/smoke.sh cutover#EVID-03 a request to :9093 leaves the counters and rows untouched"
        status: pass
      - kind: integration
        ref: "sh scripts/smoke.sh cutover#EVID-03 three healthcheck intervals with no user traffic change no reading"
        status: pass
      - kind: unit
        ref: "build() fixture#rows on :9093 and rows with an empty backend are excluded everywhere"
        status: pass
    human_judgment: false
  - id: D6
    description: "The flip boundary is the MOST RECENT transition only — exactly one object, never a list — with row_index = min(3, post_flip_row_count) computed server-side per 02-UI-SPEC.md:456"
    requirement: "EVID-03"
    verification:
      - kind: integration
        ref: "sh scripts/smoke.sh cutover#EVID-03 after a flip the boundary reports from OLD to NEW"
        status: pass
      - kind: integration
        ref: "sh scripts/smoke.sh cutover#EVID-03 boundary.row_index is 1 with one post-flip row (min(3, post_flip_row_count))"
        status: pass
      - kind: integration
        ref: "sh scripts/smoke.sh cutover#EVID-03 boundary.row_index pins at 3 once post-flip rows exceed the ceiling"
        status: pass
      - kind: integration
        ref: "sh scripts/smoke.sh cutover#EVID-03 two transitions in the window yield exactly ONE boundary, the most recent"
        status: pass
      - kind: unit
        ref: "build() fixture#row_index == min(3, post_flip=N) and equals the rows above it, for N in 1,2,3,6"
        status: pass
    human_judgment: false
  - id: D7
    description: "sh scripts/flip.sh old resets counters, table, boundary and the since-flip clock atomically — the between-takes reset (D-36)"
    requirement: "CUT-05"
    verification:
      - kind: integration
        ref: "sh scripts/smoke.sh cutover#CUT-05 flip.sh old resets counters, table, boundary and clock atomically"
        status: pass
      - kind: integration
        ref: "sh scripts/smoke.sh cutover#CUT-05 the reset reports sync AWAITING_FIRST_REQUEST, not a stale IN_SYNC"
        status: pass
    human_judgment: false
  - id: D8
    description: "A torn trailing evidence line is skipped silently; /api/status still returns 200 with the complete rows"
    requirement: "EVID-01"
    verification:
      - kind: integration
        ref: "sh scripts/smoke.sh cutover#EVID-01 a torn trailing line is skipped silently; /api/status still returns 200"
        status: pass
      - kind: integration
        ref: "sh scripts/smoke.sh cutover#EVID-01 the complete rows preceding the torn line are still returned"
        status: pass
      - kind: unit
        ref: "read_log() fixture#read_log skips a torn final line and returns the complete rows"
        status: pass
    human_judgment: false
  - id: D9
    description: "The service that reports the evidence provably cannot alter it, is published on loopback only, and touches no container-runtime socket (T-02-04/05/06)"
    verification:
      - kind: integration
        ref: "sh scripts/smoke.sh cutover#T-02-04 the status container CANNOT truncate the evidence it reports"
        status: pass
      - kind: integration
        ref: "sh scripts/smoke.sh cutover#T-02-04 the status container CANNOT alter the config it reports"
        status: pass
      - kind: integration
        ref: "sh scripts/smoke.sh cutover#T-02-05 the status port is published on loopback only"
        status: pass
      - kind: integration
        ref: "sh scripts/smoke.sh cutover#T-02-06 no container-runtime socket is mounted anywhere"
        status: pass
    human_judgment: false
  - id: D10
    description: "build() is importable and drivable without starting the HTTP service — the bind and serve call sit under a main guard"
    verification:
      - kind: command
        ref: "timeout 10 python3 -c \"import sys; sys.path.insert(0,'status'); import status; print(status.build)\""
        status: pass
    human_judgment: false
  - id: D11
    description: "The UNAVAILABLE detail line names the failing path and reason legibly at projection distance, and the four states are distinguishable on a projector"
    verification: []
    human_judgment: true
    rationale: "Whether the detail string diagnoses fast enough to be useful mid-demo, and whether the state transitions read as events from the back of a room, need a human at projection distance — the page that renders them ships in 02-03, and 02-VALIDATION lists projector legibility as manual-only."

# Metrics
duration: 25 min
completed: 2026-07-21
status: complete
---

# Phase 2 Plan 02: The Stateless Evidence Service Summary

**A fourth container that recomputes the entire world from two files plus one active proxy liveness probe on every request and exposes it as a 15-key JSON contract — so D-27's two readings, D-28's honest UNAVAILABLE and D-36's atomic reset stop being intentions and become mechanically assertable.**

## Performance

- **Duration:** 25 min
- **Started:** 2026-07-21T08:45Z
- **Completed:** 2026-07-21T09:10Z
- **Tasks:** 3
- **Files modified:** 4 (1 created, 3 modified)

## Accomplishments

- **The D-27 gap is now observable on this machine.** Editing `proxy/active-backend.conf` without reloading makes `/api/status` report `config: NEW` / `traffic: OLD` / `sync: PENDING`; `nginx -s reload` plus one request closes it to `IN_SYNC`. Demonstrated live during execution and asserted twice in the suite. The two readings are separately sourced and never merged — the simplification D-27 explicitly forbids is structurally impossible here, because `read_config` and `read_log` share no state.
- **D-28's honest UNAVAILABLE is real, and the third input is what earns it.** `docker compose stop proxy` drives `state: UNAVAILABLE`, `failing_source: proxy`, `sync: CANNOT_DETERMINE` and every reading blanked — while the evidence file is still perfectly readable, which the suite asserts in the same breath. A file-only design would have kept rendering a confident `TRAFFIC SHOWS OLD` indefinitely. The status service also stays *running* while the proxy is dead, which is when it matters most.
- **The service provably cannot alter what it reports.** All three mounts are `:ro`; `docker compose exec -T status sh -c ': > /var/log/demo/access.log'` fails with `Read-only file system`, and so does the config equivalent. No container-runtime socket exists anywhere in the project.
- **`boundary.row_index` implements 02-UI-SPEC.md:456 exactly**, derived from the window actually built rather than computed twice: 1 with one post-flip row, migrating to 3 and pinning there, verified both against live traffic and across fixtures at post-flip counts 1, 2, 3 and 6.
- **The suite grew from 65 to 94 assertions**, all green, with the `proxy` section still at exactly `--- 17 passed, 0 failed ---`. `make reset && make test` from cold is green.
- **Zero language-ecosystem packages.** Python standard library only, no `requirements.txt`, no Dockerfile, no build step — the script is bind-mounted onto a stock Docker Official Image, mirroring how `proxy` already consumes an image plus bind-mounted config.

## Task Commits

1. **Task 1: Wave 0 — the evidence-service assertions, red before the service exists** — `de6b0d2` (test) — 25 FAILs including EVID-02, EVID-03 and CUT-05; exit 1
2. **Task 2: The stateless evidence service** — `ab9584e` (feat) — driven green against 22 fixture behaviours
3. **Task 3: Wire the fourth container and turn the evidence assertions green** — `429d3b2` (feat) — the GREEN gate: 94 passed, 0 failed
4. *(housekeeping)* **Ignore host-side `__pycache__`** — `25865b0` (chore)

_TDD gate sequence: `test(02-02)` → `feat(02-02)`. No refactor commit was needed._

## Files Created/Modified

- **`status/status.py`** (new, ~430 lines) — four small pure readers and one composer. `read_config` strips comments *before* matching (the canonical file's second line is presenter prose containing both backend words) and reports non-`default` map entries as `extra_map_entries` for Phase 3's port-keyed override. `read_log` re-reads the whole file each call and skips unparseable lines. `probe_proxy` GETs `http://proxy:8081/nginx-health` with a short timeout. `build()` gates on all three, then filters to `port == "9092" and backend != ""`, tallies, takes the last served row as `traffic`, scans backwards for the most recent transition, and windows the rows with the boundary pin. `BaseHTTPRequestHandler` over `ThreadingHTTPServer`, three GET routes, `log_message` overridden, bind and `serve_forever()` under `if __name__ == "__main__":`.
- **`compose.yaml`** — the `status` service. `python:3.13-alpine`, `command: ["python3","-u","/app/status.py"]`, three read-only mounts, `127.0.0.1:9094:9094`, a busybox-`wget` healthcheck, and deliberately no `depends_on` the proxy.
- **`scripts/smoke.sh`** — 27 new assertions in `section_cutover()`; `status_get`, `jfield`, `jnest`, `jrow0`, `jrows` and `manual_flip` helpers; `restore_flip_state`'s trap now also brings `proxy` and `status` back up, because this section stops the proxy on purpose.
- **`.gitignore`** — `__pycache__/`.

## Decisions Made

- **The status container mounts `./proxy` as a directory, not `active-backend.conf` as a single file.** The plan and RESEARCH Pattern 8 both specified the single-file form, but D-34 documents editing that file live in an editor as the more dramatic presenter option, and RESEARCH Pitfall 10 records that an editor replacing the file's inode leaves a single-file mount holding stale content forever. The failure mode is specifically bad here: the page would report a cutover that had already landed as permanently `PENDING`. The mount path, and therefore every acceptance criterion, is unchanged. The proxy already mounts the same directory for the same reason.
- **`json.dumps(..., ensure_ascii=False)`.** The default escapes the em dash in the UI-SPEC error-detail copy into a backslash-u sequence, so `curl | grep` and the smoke assertions see the escape rather than the dash. The charset is declared on the response.
- **`row_index` is read off the window that was built**, not derived a second time. "The number of rows rendered above the boundary" then holds by construction rather than by agreement between two calculations.
- **A boundary that has migrated past the 8-row window is reported as `null`.** Once the 60 s pin releases, continuing to report a boundary the rows no longer contain would have the page draw a rule with nothing on one side of it.
- **The listener binds `0.0.0.0` inside the container.** The loopback restriction belongs on the host publishing (`127.0.0.1:9094:9094`), where it is asserted by `docker compose port`; binding loopback inside the container would make the published port unreachable and defeat T-02-05's assertion rather than strengthen it.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] The readers froze their paths at import, making `build()` undrivable against fixtures**

- **Found during:** Task 2
- **Issue:** `read_config(path=CONF_PATH)` and friends bound the module globals as *parameter defaults*, which Python evaluates once at definition time. Pointing the module at fixture files had no effect, so eight of the plan's own `build()` acceptance criteria could not be exercised at all — and the plan explicitly requires the readers to be drivable directly.
- **Fix:** Signatures take `None` and resolve the global at call time.
- **Files modified:** `status/status.py`
- **Verification:** all 22 fixture behaviours green, including the four states and the `:9093`/empty-backend filter
- **Committed in:** `ab9584e`

**2. [Rule 3 - Blocking] The healthcheck failed against a perfectly healthy service**

- **Found during:** Task 3
- **Issue:** `wget -q -O- http://localhost:9094/healthz` returned `can't connect to remote host: Connection refused` while the service was answering fine on the published port. busybox resolves `localhost` to `::1` first and does not retry the next address family the way curl does. RESEARCH flagged the curl-vs-wget substitution but not this second-order consequence — the other services get away with `localhost` only because they probe with curl.
- **Fix:** Probe `http://127.0.0.1:9094/healthz`, with a comment recording why, alongside the existing comment recording why it is not curl.
- **Files modified:** `compose.yaml`
- **Verification:** `docker compose ps status --format '{{.Health}}'` → `healthy`; `docker compose up -d --wait` completes
- **Committed in:** `429d3b2`

**3. [Rule 1 - Bug] The UNAVAILABLE detail shipped as an escape sequence, not text**

- **Found during:** Task 3
- **Issue:** `json.dumps` defaults to `ensure_ascii=True`, so UI-SPEC's `"{path} — {reason}"` detail went out as a backslash-u escape. The T-02-09 assertion failed, and any presenter running `curl | grep` mid-demo would have seen the escape.
- **Fix:** `ensure_ascii=False` plus `charset=utf-8` on the response.
- **Files modified:** `status/status.py`
- **Verification:** `curl -sS .../api/status | grep '"detail"'` shows a real em dash; T-02-09 green
- **Committed in:** `429d3b2`

**4. [Rule 2 - Missing critical] Two assertions passed vacuously while the service did not exist**

- **Found during:** Task 1 (RED gate review)
- **Issue:** `! docker compose exec -T status ...` is satisfied by there being no `status` service at all, so the read-only mount assertions would have gone green without ever testing a mount. The `:9093` assertion had the same shape with an empty row count.
- **Fix:** Each negation is paired with a positive readability check, and the `:9093` assertion requires a non-zero starting row count.
- **Files modified:** `scripts/smoke.sh`
- **Verification:** both went red before Task 3 and green after
- **Committed in:** `de6b0d2`

**5. [Rule 3 - Blocking] `restore_flip_state`'s trap did not restore what this plan breaks**

- **Found during:** Task 1
- **Issue:** The trap installed by 02-01 brings back `server-old` and `server-new`. This plan's section stops the *proxy* on purpose, so an interrupted run would have left the rig with no proxy.
- **Fix:** The trap now also brings up `proxy` and `status`.
- **Files modified:** `scripts/smoke.sh`
- **Verification:** section runs to completion leaving all five services up
- **Committed in:** `de6b0d2`

---

**Total deviations:** 5 auto-fixed (2 bugs, 1 missing-critical, 2 blocking)
**Impact on plan:** No change to the contract, the architecture or any acceptance criterion. Deviations 1-3 were defects the plan's own criteria caught; 4-5 hardened tests the plan asked for.

## Authentication Gates

None — nothing in this plan touches an authenticated service.

## Issues Encountered

- **The `build:` acceptance criterion cannot be satisfied literally.** Task 3 requires `grep -v '^[[:space:]]*#' compose.yaml | grep -c 'build:'` to be `1`. It was already `3` at HEAD before this plan: `server-old` has `build: ./backend`, `client` has `build: ./client`, and `server-new`'s `image:` line carries a trailing `# no build:` comment that a line-start comment filter does not strip. The criterion's intent — the status service has no build step — is met and was verified directly: `docker compose config` reports no `build` key for `status`, and the only two build keys are the two that pre-date this plan.
- **The "config unreadable" assertion moves the file aside rather than `chmod 000`.** The container runs as root, and root ignores permission bits, so a mode-based test would have passed vacuously. Absence exercises the identical `OSError` path and produces the identical `{path} — {reason}` detail the plan's own Task 2 criterion specifies for a nonexistent path.
- **The `cutover` section now takes noticeably longer** (~4 min), dominated by the mandated 10-second healthcheck-silence window and a proxy stop/start cycle. This is inherent to what is being proven, not incidental.

## Known Stubs

`GET /` returns 404 because `/app/index.html` does not exist yet — 02-03 ships it. This is deliberate and specified by the plan: "a 404 for a file that genuinely does not exist is the correct answer, not a stub." No placeholder file was created, and no reading is faked anywhere.

## Verification Results

| Check | Result |
|-------|--------|
| `sh scripts/smoke.sh cutover` | `--- 51 passed, 0 failed ---` (exit 0) |
| `sh scripts/smoke.sh proxy` (Phase 1 regression guard) | `--- 17 passed, 0 failed ---` |
| `sh scripts/smoke.sh` (all four sections) | `--- 94 passed, 0 failed ---` |
| `make reset && make test` from cold | `--- 94 passed, 0 failed ---` |
| `docker compose ps` | five services, `proxy`/`server-old`/`server-new`/`status` all `healthy` |
| `docker compose port status 9094` | `127.0.0.1:9094` |
| `curl http://localhost:9094/api/status` | all 15 contract keys present; `state OK`, `config OLD`, `traffic OLD`, `sync IN_SYNC` |
| `curl -o /dev/null -w '%{http_code}' .../healthz` | `200` |
| `curl -o /dev/null -w '%{http_code}' .../` and `.../nope` | `404`, `404` (index.html ships in 02-03) |
| Live PENDING demonstration | edit without reload → `config NEW / traffic OLD / sync PENDING`; reload + request → `IN_SYNC` |
| `docker compose exec -T status sh -c ': > /var/log/demo/access.log'` | `Read-only file system`, non-zero |
| `timeout 10 python3 -c "... import status; print(status.build)"` | exits 0 — no module-scope bind |
| `build()` fixture driver (22 behaviours) | all pass |

Final state: stack running, all five services up and healthy, selector on **OLD**, evidence log cleared by the closing `flip.sh old`, working tree clean.

## Next Phase Readiness

**Ready for 02-03 (the status page).** The renderer's entire input now exists, is stable and is asserted:

- `GET http://localhost:9094/api/status` — the 15-key contract in `02-02-PLAN.md` `<api_contract>`, served with `Cache-Control: no-store` and `charset=utf-8`.
- `GET /` already serves `/app/index.html` from the read-only `./status:/app:ro` mount, so 02-03 adds one file and nothing else — no compose change, no restart.
- `boundary.row_index` and `since_flip_s` are computed server-side. **The page must consume both verbatim.** Re-deriving `row_index` client-side duplicates the windowing logic in two places, and a client-side since-flip interval keeps counting while the service is dead — exactly the stale-but-plausible failure D-28 forbids.
- Every log-derived cell (`rows[].path` in particular) is attacker-controlled and reaches the projector verbatim. Render with `element.textContent`, never `innerHTML` (RESEARCH Pitfall 8, verified vector).
- `state` is the single switch for all four UI-SPEC states: `OK`, `NO_TRAFFIC`, `UNAVAILABLE`, plus `EVIDENCE_CLEARED` which is `NO_TRAFFIC` with a client-side 10 s confirmation. Under `UNAVAILABLE` every reading is already `null`/`[]`, so a renderer keyed off `state` cannot accidentally paint a half-lit page.

No blockers.

## Self-Check: PASSED

`status/status.py` verified present on disk; `compose.yaml`, `scripts/smoke.sh` and `.gitignore` verified modified. All four commits (`de6b0d2`, `ab9584e`, `429d3b2`, `25865b0`) verified present in git history.

---
*Phase: 02-the-live-http-cutover*
*Completed: 2026-07-21*

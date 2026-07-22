> **SUPERSEDED HOSTNAME:** every `app.demo.local` reference below reads `app.demo.test` as of 2026-07-21. `.local` is RFC 6762-reserved for multicast DNS; macOS routed it to an unreachable mDNS resolver under Tailscale, stalling every `getaddrinfo` for 5s. See `01-CONTEXT.md` D-22. This document is left otherwise unedited as a historical record.

---
phase: 01-demo-up-http-lands-on-old
plan: 02
subsystem: infra
tags: [nginx, reverse-proxy, docker-compose, docker-dns, log-format, make, posix-sh]

# Dependency graph
requires:
  - "01-01: both backends expose Docker healthchecks (the `depends_on: service_healthy` gate depends on them)"
  - "01-01: backends set `X-Backend` (the proxy log's `backend=` field is derived from it)"
  - "01-01: `scripts/smoke.sh` section dispatcher and the Makefile target vocabulary"
provides:
  - "`proxy` service on `127.0.0.1:9092` — the migration endpoint, joined to the same single `docker compose up`"
  - "`proxy/active-backend.conf` — the canonical five-line flip include (two presenter comment lines + a three-line `map`); Phase 2 flips `old` to `new` here and nowhere else"
  - "`proxy/nginx.conf` — `upstream old`/`upstream new`, variable `proxy_pass`, the `demo` log format, and the `$backend_is_valid` 503 guard"
  - "Compose network alias `app.demo.local` on the proxy — the client container resolves the real hostname straight to the proxy through Docker DNS"
  - "`log_format demo` with `backend=$upstream_http_x_backend` — the exact field Phase 2's EVID-01 consumes"
  - "`make reload` — the test-then-reload-then-verify discipline Phase 2's `make flip` inherits"
  - "`make reset` restoring the FULL annotated five-line include (completes D-21)"
  - "`sh scripts/smoke.sh proxy` — 17 green assertions"
affects: [01-03-redirect, phase-02-cutover, phase-03-ssh-stream]

# Tech tracking
tech-stack:
  added:
    - "nginx:1.30-alpine as the proxy — same pinned image as the backends, so there is one nginx version to explain on stage"
  patterns:
    - "Selector-in-the-include, target-in-the-main-config: a `map` (not an `upstream`) in the shared file, so Phase 3's `stream` block can include THE SAME FILE without restructuring (D-12 + D-13)"
    - "Validity guard beside the selector, never inside it: `$backend_is_valid` lives in `nginx.conf` so the file the audience reads stays five lines"
    - "Identity honesty: zero `add_header` in the proxy — every OLD/NEW claim originates from the backend that served the request"
    - "Health-gated `depends_on` as a hard startup requirement, because nginx resolves upstream hostnames at config-parse time"
    - "Directory bind mount (`./proxy:/etc/nginx/demo:ro`) rather than a single-file mount, so editor inode replacement cannot serve stale config"
    - "Destructive smoke checks wrapped in a `cp` + `trap` so an interrupted run restores the rig"

key-files:
  created:
    - proxy/nginx.conf
    - proxy/active-backend.conf
  modified:
    - compose.yaml
    - scripts/smoke.sh
    - Makefile

key-decisions:
  - "`active-backend.conf` line 2 was reworded from \"That's it.\" to \"Nothing else.\" so the `make reset` restore recipe can stay a single-quoted `printf` in GNU Make 3.81. An apostrophe inside the canonical content would have forced `'\\''` escaping in the recipe and put the byte-identity guarantee at risk for a purely cosmetic word."
  - "The 503 guard uses a server-level `if ($backend_is_valid = 0)` with `default_type text/plain`, so the invalid value and the two legal values are readable as plain text in a browser mid-demo, not downloaded as an octet stream."
  - "`smoke.sh`'s Pitfall 3 check is deliberately destructive and self-restoring (backup + `trap` on EXIT/INT/TERM, plus an explicit reload after restore) — the 503 behaviour cannot be proven without actually writing an invalid selector."
  - "Only 9092 is published on the proxy. The 9093 redirect listener is plan 01-03's to add; publishing it early would have made `docker compose ps` assert a port with nothing behind it."
  - "The proxy has no healthcheck. `depends_on` gates it behind the backends, and nginx failing to parse its config is already a hard container failure that `--wait` surfaces."

requirements-completed: [ENV-04, HTTP-01, HTTP-02]

coverage:
  - id: D1
    description: "The `stream` module is compiled into the proxy image, so Phase 3's port 22 proxying is possible without a rebuild — while Phase 1 ships no stream block at all."
    requirement: ENV-04
    verification:
      - kind: integration
        ref: "scripts/smoke.sh proxy#ENV-04 proxy nginx built --with-stream"
        status: pass
      - kind: other
        ref: "docker compose exec -T proxy nginx -V 2>&1 | tr ' ' '\\n' | grep -- --with-stream -> --with-stream, _realip, _ssl, _ssl_preread"
        status: pass
    human_judgment: false
  - id: D2
    description: "A request to localhost:9092/whoami from the host lands on server-old and returns the OLD identity supplied by the backend itself."
    requirement: HTTP-01
    verification:
      - kind: integration
        ref: "scripts/smoke.sh proxy#HTTP-01 localhost:9092/whoami == 'OLD server-old'"
        status: pass
      - kind: integration
        ref: "scripts/smoke.sh proxy#D-11 X-Backend: OLD through the proxy"
        status: pass
    human_judgment: false
  - id: D3
    description: "The client container reaches the active backend through the REAL hostname app.demo.local:9092, resolved by Docker DNS straight to the proxy container — never via localhost."
    requirement: HTTP-01
    verification:
      - kind: integration
        ref: "scripts/smoke.sh proxy#HTTP-01 client -> app.demo.local:9092/whoami == 'OLD server-old'"
        status: pass
      - kind: integration
        ref: "scripts/smoke.sh proxy#HTTP-02 evidence: proxy log records app.demo.local:9092"
        status: pass
    human_judgment: false
  - id: D4
    description: "The proxied request is transparent: zero redirects and an effective URL byte-identical to the requested one."
    requirement: HTTP-02
    verification:
      - kind: integration
        ref: "scripts/smoke.sh proxy#HTTP-02 proxied request performs 0 redirects"
        status: pass
      - kind: integration
        ref: "scripts/smoke.sh proxy#HTTP-02 effective URL unchanged through the proxy"
        status: pass
    human_judgment: false
  - id: D5
    description: "The proxy never asserts a backend identity it did not observe — no add_header exists in any non-comment line of the proxy config, so the X-Backend the client sees and the backend= the log records both originate from the serving backend."
    verification:
      - kind: integration
        ref: "scripts/smoke.sh proxy#HTTP-01 honesty: no add_header in proxy/nginx.conf"
        status: pass
    human_judgment: false
  - id: D6
    description: "The access log exposes which backend served each request via backend=$upstream_http_x_backend — the Phase 2 EVID-01 precondition."
    verification:
      - kind: integration
        ref: "scripts/smoke.sh proxy#EVID-01 precondition: proxy log carries backend=OLD"
        status: pass
      - kind: other
        ref: "docker compose logs proxy -> '172.19.0.5 -> app.demo.local:9092 \"GET /whoami HTTP/1.1\" 200 upstream=172.19.0.2:80 backend=OLD rt=0.000 urt=0.000'"
        status: pass
    human_judgment: false
  - id: D7
    description: "A typo'd flip value passes nginx -t and reloads cleanly, then returns a legible 503 naming the invalid value rather than a bare 502."
    verification:
      - kind: integration
        ref: "scripts/smoke.sh proxy#Pitfall 3 invalid selector returns 503, not a bare 502"
        status: pass
      - kind: integration
        ref: "scripts/smoke.sh proxy#Pitfall 3 503 body names the offending value"
        status: pass
      - kind: integration
        ref: "scripts/smoke.sh proxy#Pitfall 3 restore: 9092 serves 200 again"
        status: pass
    human_judgment: false
  - id: D8
    description: "The proxy starts cleanly from a cold docker compose up on every attempt — the health-gated depends_on prevents the parse-time upstream resolution failure."
    verification:
      - kind: integration
        ref: "3x (docker compose down -v && docker compose up -d --build --wait) -> all Healthy, 0 occurrences of 'host not found in upstream'"
        status: pass
    human_judgment: false
  - id: D9
    description: "make reset restores proxy/active-backend.conf to its full canonical five-line content including both presenter-facing comment lines, so D-12's on-screen annotation survives D-21's routine between-takes reset."
    verification:
      - kind: integration
        ref: "corrupt file -> make reset -> cmp against Task 1 canonical content: no difference; line count 5; 'only file' and 'default old' both present"
        status: pass
      - kind: other
        ref: "make -n reset -> printf rewrite appears between 'docker compose down -v' and 'docker compose up'"
        status: pass
    human_judgment: false
  - id: D10
    description: "Config changes are picked up by a graceful reload, never a container restart (D-14), and the reload is gated on nginx -t first."
    verification:
      - kind: integration
        ref: "scripts/smoke.sh proxy#D-14 nginx -t passes inside the proxy container"
        status: pass
      - kind: other
        ref: "make reload -> 'test is successful' then 'signal process started' then 'OLD server-old'; make -n reload contains no 'docker compose restart'"
        status: pass
    human_judgment: false
  - id: D11
    description: "proxy/active-backend.conf is a self-contained five-line file whose only meaningful token is `old`, readable in full on screen during the Phase 2 flip."
    verification:
      - kind: other
        ref: "awk 'END{print NR}' proxy/active-backend.conf -> 5; grep -qi 'only file'; grep -q 'map $server_port $active_backend'; grep -q 'default old'"
        status: pass
    human_judgment: true
    rationale: "The line count, the annotation and the single meaningful token are asserted mechanically, but D-12's substance is that the file reads clearly on a projector at the flip moment. Whether the two comment lines actually land with an audience is a presenter judgment no command can make."

# Metrics
duration: 5 min
completed: 2026-07-21
status: complete
---

# Phase 01 Plan 02: Proxy In, 9092 Lands on OLD Summary

**nginx joins the same `docker compose up` on `127.0.0.1:9092`, resolving `app.demo.local` for the client container through a Docker network alias and landing every request on `server-old` with the URL untouched — steered by a five-line `map` include that Phase 2 flips with one word and Phase 3 reuses from a `stream` context unchanged.**

## Performance

- **Duration:** 5 min
- **Started:** 2026-07-21T06:09:13Z
- **Completed:** 2026-07-21T06:13:46Z
- **Tasks:** 2
- **Files:** 2 created, 3 modified

## Accomplishments

- **The walking skeleton's spine is connected.** One real HTTP request now traverses nginx, lands on an identified backend, and is observable in the log: `172.19.0.5 -> app.demo.local:9092 "GET /whoami HTTP/1.1" 200 upstream=172.19.0.2:80 backend=OLD`. Both the host path (`localhost:9092`) and the client-container path (`app.demo.local:9092`) return `OLD server-old`.
- **The flip mechanism is settled, and it is five lines.** `proxy/active-backend.conf` holds the SELECTOR (`map $server_port $active_backend { default old; }`) while `nginx.conf` holds the TARGETS (`upstream old` / `upstream new`). That inversion is what lets Phase 2 flip one word and Phase 3 `include` the identical file from a `stream` block where the ports are 22 rather than 80 — an `upstream` in the shared file could never have done both.
- **The demo cannot silently lie about which backend answered.** `grep -ci add_header` over the non-comment lines of `proxy/nginx.conf` returns 0. The `X-Backend: OLD` the client sees and the `backend=OLD` in the log are the same value, produced by the container that actually served the request and forwarded verbatim by `proxy_pass`.
- **The mid-stage 502 is defused before it can happen.** With `default nwe;` written into the include, `nginx -t` passes and `nginx -s reload` succeeds — exactly the trap RESEARCH reproduced — but 9092 now answers `503` with a body naming `nwe` and the two legal values, instead of a mystery 502. Asserted end to end, destructively, with a trap-guarded restore.
- **Cold starts are deterministic.** Three consecutive `down -v` / `up --build --wait` cycles produced zero `host not found in upstream` failures. The health-gated `depends_on` on both backends is doing real work: nginx resolves upstream hostnames at config-PARSE time and aborts hard if DNS cannot answer yet.
- **`make reset` now honours D-21 in full.** It rewrites the complete annotated five-line include between `down -v` and `up`, verified byte-identical to the Task 1 original by `cmp` after deliberately corrupting the file. A reset that restored only the `map` body would have stripped the presenter-facing comments on the very first run and left Phase 2 demoing an unlabelled file.

## Task Commits

1. **Task 1: The proxy config — flip include, transparent 9092, log format, validity guard** — `894ae92` (feat)
2. **Task 2: Proxy joins the stack — 9092 lands on OLD through a real hostname** — `b790881` (feat)

Both tasks carry `tdd="true"`. Their `<behavior>` blocks are assertions about a running rig rather than unit-testable pure functions, so the RED/GREEN cycle was expressed through the plan-01-01 smoke stub: `section_proxy()` shipped in Wave 1 as an unconditional `fail "proxy: not implemented yet — plan 01-02"` (the RED state, committed in `ace3d14`), and this plan turned it green with 17 real assertions. No separate `test(01-02)` commit was created because the failing test already existed on the branch — see TDD Gate Compliance below.

## Files Created/Modified

- `proxy/active-backend.conf` (new) — the canonical five-line flip include: two presenter-facing comment lines plus a three-line `map` keyed on `$server_port`
- `proxy/nginx.conf` (new) — `worker_processes`/`events`, `log_format demo`, stdout access log, `upstream old`/`upstream new` declared before the include, the directory-path include, the `$backend_is_valid` map, and the 9092 server block with the 503 guard and a no-trailing-slash variable `proxy_pass`
- `compose.yaml` — added the `proxy` service (image, two `:ro` mounts, `127.0.0.1:9092:9092`, the `app.demo.local` network alias, health-gated `depends_on` on both backends); `client` gained `depends_on: [proxy]`
- `scripts/smoke.sh` — `section_proxy()` replaces the RED stub with 17 assertions; new `guard_check()` helper carries the trap-protected destructive Pitfall 3 check
- `Makefile` — new `reload` target (`nginx -t` → `nginx -s reload` → smoke request); `reset` extended with the canonical include rewrite positioned between `down -v` and `up`

## Decisions Made

See `key-decisions` in the frontmatter. The one worth restating: **the canonical file's line 2 was reworded** from the RESEARCH draft's `# Change \`old\` to \`new\` to cut over. That's it.` to `... Nothing else.` The apostrophe in "That's" cannot survive a single-quoted `printf` in a GNU Make 3.81 recipe without `'\''` escaping, and the plan requires the file and the `make reset` recipe to be byte-identical. Rewording one word was strictly safer than escaping a quote in the recipe that guarantees the D-12 annotation. Backticks are preserved and are literal inside the single-quoted `printf`.

## Deviations from Plan

**1. [Rule 3 - Blocking] Reworded `active-backend.conf` line 2 to drop an apostrophe**
- **Found during:** Task 2, writing the `make reset` restore recipe
- **Issue:** The plan requires the `make reset` rewrite to be byte-identical to Task 1's canonical content. RESEARCH's draft line 2 ends `That's it.`; that apostrophe terminates the single-quoted `printf` string in the Make recipe, and the `'\''` workaround would have put the byte-identity guarantee behind fragile quoting under GNU Make 3.81.
- **Fix:** Changed the phrase to `Nothing else.` in both the file and the recipe. Meaning, line count, and the `only file` annotation are unaffected.
- **Files modified:** `proxy/active-backend.conf`, `Makefile`
- **Verification:** `cmp` after a corrupt-then-`make reset` round trip reports no difference; the file is still 5 lines with both comment lines intact.
- **Commit:** `b790881`

**Total deviations:** 1 auto-fixed (1 blocking).
**Impact on plan:** Cosmetic. Every acceptance criterion is expressed as a line count or a case-insensitive `only file` grep, none of which reference the changed words.

## Issues Encountered

None blocking. Two observations worth carrying forward:

- `docker compose up --wait` reports `demo-client-1 Healthy` although `client` still declares no healthcheck — the plan-01-01 caveat holds and was not read as evidence of health gating.
- Ordering in `--wait` output is non-deterministic across runs (`client Healthy` sometimes precedes `server-old Healthy`). Compose reports completion order, not dependency order; the `depends_on` gate is enforced regardless, as the three-cycle cold-start check confirms.

## Verification Results

Plan-level `<verification>`, run from cold, in order:

| # | Check | Result |
|---|-------|--------|
| 1 | `down -v && up -d --build --wait` x3, no `host not found in upstream` | PASS — 3/3 clean, 0 occurrences |
| 2 | `nginx -V \| grep -- --with-stream` (ENV-04) | PASS — `--with-stream` + realip/ssl/ssl_preread |
| 3 | `curl -sS -i http://localhost:9092/whoami` (HTTP-01) | PASS — 200, `X-Backend: OLD`, body `OLD server-old` |
| 4 | `curl -sSL -w 'final=%{url_effective} redirects=%{num_redirects}'` (HTTP-02) | PASS — `final=http://localhost:9092/whoami redirects=0` |
| 5 | `docker compose exec client curl http://app.demo.local:9092/whoami` (D-01/D-02) | PASS — `OLD server-old` |
| 6 | `docker compose logs proxy \| tail -5` | PASS — `app.demo.local:9092` and `backend=OLD` both present |
| 7 | `sh scripts/smoke.sh backends && sh scripts/smoke.sh proxy` | PASS — 13/13 and 17/17, both exit 0 |
| 8 | `cat proxy/active-backend.conf` — five lines, one meaningful token (D-12) | PASS |

Additional acceptance criteria confirmed outside the smoke suite:

- `docker compose config --quiet` exits zero.
- `docker compose ps --format '{{.Ports}}'` lists exactly `127.0.0.1:9090->80`, `127.0.0.1:9091->80`, `127.0.0.1:9092->9092`. No port 22 binding (D-15, T-01-02).
- `make -n reload` prints `nginx -t` before `nginx -s reload` and contains no `docker compose restart`. Executed live: test successful → signal process started → `OLD server-old`.
- `make -n reset` places the `printf` rewrite between `docker compose down -v` and `docker compose up`.
- Round-trip byte identity: file corrupted to `x\ny\nz`, `make reset` run, `cmp` against the Task 1 canonical copy reports no difference; line count 5; `only file` and `default old` both still present.
- Privilege-escalation contract: `grep -cE '^[[:space:]]*[^@#]*(^|[|;&[:space:]])sudo[[:space:]]' Makefile` returns `0`. `make status` still prints the full `/etc/hosts` remediation line. No host system file was touched by this plan.
- `docker run --rm -v $PWD/proxy:/etc/nginx/demo:ro -v $PWD/proxy/nginx.conf:/etc/nginx/nginx.conf:ro --entrypoint nginx nginx:1.30-alpine -t` reports only `host not found in upstream "server-old:80"` — the legitimate out-of-network failure, with no syntax error.
- Full suite `sh scripts/smoke.sh` reports 30 passed, 1 failed — the single failure being plan 01-03's intentional `redirect` stub.

## TDD Gate Compliance

The plan carries `type: execute` at the plan level with `tdd="true"` on both tasks, so the plan-level RED/GREEN/REFACTOR commit sequence does not strictly apply. The RED gate for this plan's behaviour was nonetheless satisfied: `section_proxy()`'s unconditional failure shipped in plan 01-01's `test(01-01)` commit `ace3d14` and was verifiably red on this branch before either task ran. Both tasks then landed as `feat(01-02)` GREEN commits. No `test(01-02)` commit exists, and no REFACTOR commit was needed. A strict reading of the plan-level gate sequence would want a `test(01-02)` commit; the substance — a failing assertion existing before the implementation — was met by the Wave 1 stub, which is exactly what that stub was authored for.

## Threat Mitigations Applied

| Threat | Disposition | Evidence |
|--------|-------------|----------|
| T-01-07 DoS (typo'd selector) | mitigated | `$backend_is_valid` map + `return 503` in `nginx.conf`; asserted end to end by writing `default nwe;`, reloading, and observing 503 with `nwe` named in the body, then 200 after restore |
| T-01-08 DoS (parse-time upstream resolution failure) | mitigated | `depends_on: {server-old: service_healthy, server-new: service_healthy}`; three consecutive cold cycles, zero `host not found in upstream` |
| T-01-09 Spoofing (proxy asserting an unobserved identity) | mitigated | `grep -v '^[[:space:]]*#' proxy/nginx.conf \| grep -ci add_header` returns 0, asserted in the smoke suite so it cannot regress silently |
| T-01-10 Info disclosure (0.0.0.0 binding) | mitigated | Published as `127.0.0.1:9092:9092`; asserted via `docker compose ps --format '{{.Ports}}'` |
| T-01-11 Tampering (forged `Host` to backends) | accepted | Unchanged from the plan — backends serve static content and fixed `return` responses with no host-based routing; `$host` preservation is required for the HTTP-02 log evidence; loopback binding bounds exposure |
| T-01-12 Tampering (config modified from inside the container) | mitigated | Both proxy mounts are `:ro`; host-side editing is unaffected, as the live Pitfall 3 check demonstrates |
| T-01-SC Tampering (package installs) | accepted | Nothing installed. `nginx:1.30-alpine` pulled by pinned tag (digest `sha256:97d490c1…`), a Docker Official Image approved in RESEARCH's legitimacy audit |

No security-relevant surface was introduced beyond the plan's `<threat_model>`. No threat flags raised.

## Known Stubs

One remains, owned by the next plan and unchanged by this one:

- `scripts/smoke.sh` `section_redirect()` — emits `FAIL redirect: not implemented yet — plan 01-03`. `contrast` is still `.PHONY`-only for the same reason.

Nothing in this plan's own scope is stubbed. `sh scripts/smoke.sh proxy` is 17/17 green.

## Flagged Assumptions Carried Forward

All three probe rows were exercised as the plan assumed; none changed status.

1. **ENV-04** — satisfied by proving the module is COMPILED IN (`nginx -V` shows `--with-stream` plus three stream sub-modules). No stream block ships and no `*.stream-template` file exists, so the nginx image's stream machinery stays dormant. A verifier reading ENV-04 as requiring a functioning port-22 proxy would be reading Phase 3 work.
2. **HTTP-01** — "the client" was executed as BOTH the `client` container (Docker DNS on `app.demo.local`) and the host (`localhost:9092`); both paths are asserted and both return `OLD server-old`. No TLS variant. Note the host's browser path additionally needs D-03's `/etc/hosts` entry, which is still absent on this machine (see User Setup Required).
3. **HTTP-02** — executed as URL invariance, not source-IP invariance, and this reading is now load-bearing evidence. `%{num_redirects}=0` and an unchanged `%{url_effective}` are the primary proof; the log's `$host:$server_port` holding `app.demo.local:9092` corroborates. Observed source addresses confirm why the alternative reading is unsatisfiable here: host requests log `172.19.0.1` (the bridge gateway) while client-container requests log the real `172.19.0.5`.

## User Setup Required

Unchanged from plan 01-01, and now genuinely load-bearing for the browser story:

- **D-03 one-time host setup:** `echo '127.0.0.1  app.demo.local' | sudo tee -a /etc/hosts`. `make status` currently reports `hosts: MISSING` and prints this exact line. Every assertion in this plan passes without it — the client container uses Docker DNS and the host assertions use `localhost` — but the presenter's BROWSER cannot resolve `app.demo.local:9092` until it is added. This plan did not add it: modifying a host system file is outside its remit.

## Next Phase Readiness

Ready for plan 01-03. Specifically in place for it:

- The `proxy` service exists with the directory mount and the alias, so 01-03 adds a `listen 9093` server block plus one published port rather than restructuring anything.
- `scripts/smoke.sh` `section_redirect()` is still the RED stub with the same `assert` idiom available.
- `make contrast` remains `.PHONY`-only, awaiting 01-03's recipe.
- The `Location` target for the 301 (`http://app.demo.local:9090$request_uri`) is reachable from the host browser via D-03 + the published 9090, but NOT from the client container, where `app.demo.local` resolves to the proxy, which does not listen on 9090. RESEARCH flagged this; the 01-03 walkthrough must not tell the presenter to `curl -L` 9093 from inside the client.
- Phase 2 inherits a settled `log_format` (`backend=$upstream_http_x_backend`), a one-word flip file, and `make reload`'s test-then-reload-then-verify discipline for `make flip` to extend.

**Current state:** the stack is left running and healthy — `server-old` and `server-new` healthy, `proxy` and `client` up, `proxy/active-backend.conf` in its correct canonical five-line state selecting `old`. `curl http://localhost:9092/whoami` returns `OLD server-old` right now.

No blockers.

## Self-Check: PASSED

Both created files verified present on disk (`proxy/nginx.conf`, `proxy/active-backend.conf`). Both task commits verified in `git log`: `894ae92`, `b790881`.

---
*Phase: 01-demo-up-http-lands-on-old*
*Completed: 2026-07-21*

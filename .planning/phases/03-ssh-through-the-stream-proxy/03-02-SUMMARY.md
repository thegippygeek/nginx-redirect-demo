---
phase: 03-ssh-through-the-stream-proxy
plan: 02
subsystem: proxy-stream
tags: [nginx, stream, ssh, tcp-proxy, cutover, smoke-tests, d-39, d-40, d-46]

requires:
  - "03-01: SSH key auth from the client container and the pre-auth identity banner"
  - "Phase 1 proxy/active-backend.conf — the shared five-line selector (D-13)"
  - "Phase 1 nginx built --with-stream (ENV-04)"
provides:
  - "SSH-01: the proxy itself listens on :22 inside the demo network; `ssh demo@app.demo.test` needs no port flag"
  - "SSH-02: a top-level `stream` block that proxy_passes raw TCP to the shared selector variable"
  - "SSH-03: the backend's identity banner arriving intact through the TCP hop"
  - "CUT-04: one stored command string returning OLD then NEW across a flip, corroborated by an auth-free host-key reading"
  - "D-40 resolved in proxy/nginx.conf with a measurement: an in-flight session survives the reload on its original backend"
  - "scripts/smoke.sh section_ssh — 23 further assertions (48 in the section, 168 in the suite)"
affects:
  - "Plan 03-03 (scripts/verify.sh) can read identity through the proxied hostname, not just a backend name"
  - "Phase 4 KEY-01/KEY-02: the host key presented at app.demo.test:22 now changes with the selector — the phase's entire premise, live"

tech-stack:
  added: []
  patterns:
    - "one `map` in a shared include, valid in both `http` and `stream`; `upstream` groups declared per-context (D-13/D-39)"
    - "region-scoped config assertions: extract with an awk range anchored at column zero, assert the range is non-empty, then pair every negative check with a positive one"
    - "the IPv4 loopback literal for anything probing the proxy — a stream `listen 22;` binds 0.0.0.0 only"
    - "trap-based selector restore in any smoke section that flips the rig"

key-files:
  created: []
  modified:
    - proxy/nginx.conf
    - scripts/smoke.sh

key-decisions:
  - "The stream log reuses the HTTP log's `backend=` field NAME so `make logs-demo`'s awk colours SSH lines with no Makefile change, and pays the honesty cost explicitly: `selector=` sits on the same line and a config comment states that the HTTP field is the backend asserting its own identity while this one is the proxy reporting its own selector."
  - "`access_log /dev/stdout` and nothing else. Lines sent to the JSON evidence sink would be silently discarded by the status parser's `except ValueError: continue` while still growing a file it rescans every poll — worse than crashing (D-46)."
  - "No stream analogue of the http `$backend_is_valid` guard, recorded in a comment as a decision: a stream block cannot serve a diagnostic an SSH client could render, and the http guard catches the same typo seconds earlier."
  - "`worker_shutdown_timeout` stays unset (D-40). The in-flight session surviving the reload is the phase's best narrative moment, and the plan asserts it by measurement rather than prose."
  - "The auth-free host-key oracle (`ssh-keyscan` fingerprint == the backend's own) corroborates CUT-04 independently of the banner, so a banner bug and a routing bug cannot mask each other."

requirements-completed: [SSH-01, SSH-02, SSH-03, CUT-04]

coverage:
  - deliverable: "SSH-01 — the proxy listens on :22 and a client ssh with no port flag lands on the active backend"
    verification:
      - kind: test
        ref: "scripts/smoke.sh#section_ssh SSH-01 the proxy itself listens on :22 (IPv4 loopback literal)"
        status: pass
      - kind: test
        ref: "scripts/smoke.sh#section_ssh SSH-01 client -> app.demo.test lands on the selected backend, no port flag"
        status: pass
      - kind: command
        ref: "docker compose exec -T client ssh demo@app.demo.test hostname -> rc=0, 'server-old'"
        status: pass
    human_judgment: false
  - deliverable: "SSH-02 — a top-level stream block proxying raw TCP, sharing one include file with the http block"
    verification:
      - kind: test
        ref: "scripts/smoke.sh#section_ssh SSH-02 stream block / non-empty region / proxy_pass selector / listen 22 (4 assertions)"
        status: pass
      - kind: test
        ref: "scripts/smoke.sh#section_ssh SSH-02/D-39 the shared include path appears exactly twice, once per context"
        status: pass
      - kind: test
        ref: "scripts/smoke.sh#section_ssh D-39 the shared file is still 5 lines with both presenter comments"
        status: pass
      - kind: command
        ref: "awk context walk over proxy/nginx.conf -> include at line 66 (http), line 256 (stream), same path"
        status: pass
    human_judgment: false
  - deliverable: "SSH-03 — the identity banner survives the TCP hop unchanged, before and after the flip"
    verification:
      - kind: test
        ref: "scripts/smoke.sh#section_ssh SSH-03 the identity banner survives the TCP hop unchanged"
        status: pass
      - kind: test
        ref: "scripts/smoke.sh#section_ssh SSH-03 the banner through the hop now names NEW server-new"
        status: pass
    human_judgment: false
  - deliverable: "CUT-04 — the identical stored command returns OLD then NEW, corroborated auth-free"
    verification:
      - kind: test
        ref: "scripts/smoke.sh#section_ssh CUT-04 the identical stored command returns OLD, then NEW"
        status: pass
      - kind: test
        ref: "scripts/smoke.sh#section_ssh CUT-04 host key at the proxied port is server-old's / server-new's own + the reading CHANGED (3 assertions)"
        status: pass
      - kind: command
        ref: "make flip-new then the identical ssh string -> 'NEW server-new' / 'server-new'; make flip-old restores"
        status: pass
    human_judgment: false
  - deliverable: "D-40 — an in-flight session survives the reload on its original backend while a new one lands on NEW"
    verification:
      - kind: test
        ref: "scripts/smoke.sh#section_ssh D-40 the in-flight session still reports OLD after the reload"
        status: pass
      - kind: test
        ref: "scripts/smoke.sh#section_ssh D-40 a session opened after the reload reports NEW"
        status: pass
    human_judgment: false
  - deliverable: "D-46 / T-03-06 — the stream log reaches make logs and never the JSON evidence sink"
    verification:
      - kind: test
        ref: "scripts/smoke.sh#section_ssh D-46 exactly one access_log / targets stdout / names no log directory (3 assertions)"
        status: pass
      - kind: test
        ref: "scripts/smoke.sh#section_ssh EVID-01 the stream log carries the uppercase label AND the raw selector"
        status: pass
      - kind: test
        ref: "scripts/smoke.sh#section_ssh EVID-01 the stream label token is the one logs-demo's awk colours"
        status: pass
    human_judgment: false
  - deliverable: "Phase 1/2 regression surface intact with the stream block live"
    verification:
      - kind: command
        ref: "sh scripts/smoke.sh proxy -> 17 passed, 0 failed (including guard_check's invalid selector)"
        status: pass
      - kind: command
        ref: "make test -> 168 passed, 0 failed (145 inherited + 23 new)"
        status: pass
      - kind: command
        ref: "docker compose exec proxy ps -> one master, one worker, zero shutting-down workers after the suite"
        status: pass
    human_judgment: false
  - deliverable: "The presenter's on-stage moment: one word moving both protocols at once"
    human_judgment: true
    rationale: "Whether the audience reads the single-word diff and the coloured SSH log line as the payoff the narration claims — and whether the D-40 in-flight session is worth narrating live or is a distraction — is a judgment no assertion makes."

metrics:
  duration: "25 min"
  tasks: 2
  files: 2
  completed: 2026-07-21

status: complete
---

# Phase 3 Plan 02: SSH Through the Stream Proxy Summary

A top-level nginx `stream` block relaying raw TCP on port 22 to whichever backend the SAME five-line
`active-backend.conf` selects for HTTP — one file, one word, both protocols, with the D-40 in-flight
reload behaviour resolved in the config by measurement rather than hedge.

## Accomplishments

- **`stream { … }` in `proxy/nginx.conf`** — `log_format demo_stream`, `access_log /dev/stdout` and
  nothing else, both upstreams on `:22`, **the same `include /etc/nginx/demo/active-backend.conf`
  the `http` block uses**, a stream-local uppercase-label `map`, and one `listen 22;` server. D-13's
  speculative bet from Phase 1 — a `map` is valid in both contexts, an `upstream` is not shareable
  between them — cashes here with no restructuring of any kind.
- **The Phase 2 deferred question, resolved in the file.** The `worker_shutdown_timeout` prose block
  is replaced by the measured behaviour, the presenter line it affords, and an explicit instruction
  not to "tidy away" the lingering old worker with a shutdown timeout. The commented preview at the
  foot of the file is deleted — it is realised now, and a second copy of the include path would break
  the D-39 count.
- **23 further assertions in `section_ssh`** (48 in the section, 168 in the suite). The proxied hop,
  the D-39 headline in mechanical form, the cutover through one stored command string, the auth-free
  host-key oracle, the D-40 measurement, and the D-46 sink checks asserted positively as well as
  negatively.
- **A trap-based selector restore** for the section, modelled on `guard_check` and
  `restore_flip_state`: the group flips the rig on purpose, and an interrupted run still leaves
  `proxy/active-backend.conf` byte-identical to what `make reset` writes.

## Task Commits

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | RED proxied-hop assertions | `3f4be79` | `scripts/smoke.sh` |
| 2 | The stream block + D-40 resolution | `3b7dc6c` | `proxy/nginx.conf` |

TDD gates: `test(03-02)` at `3f4be79` (19 FAIL, 29 PASS — RED), `feat(03-02)` at `3b7dc6c`
(48 PASS, 0 FAIL — GREEN). No refactor commit was needed.

## Verification Results

| Check | Result |
|-------|--------|
| `docker compose exec -T proxy nginx -t` with the selector included in BOTH contexts | `test is successful` |
| `nc -z 127.0.0.1 22` inside the proxy | open (`0.0.0.0:22` — IPv4 only, as researched) |
| `ssh demo@app.demo.test hostname` from `client`, no port flag | `rc=0`; banner `OLD server-old`, stdout `server-old` |
| `make flip-new` then the **identical stored command** | `NEW server-new` / `server-new` — nothing client-side changed |
| Same flip over HTTP, same instant | `curl :9092/whoami` → `NEW server-new` — one word, both protocols |
| `make flip-old` | rig restored; banner reads `OLD server-old` again |
| Include path, comment-stripped | exactly 2 — line 66 (`http`), line 256 (`stream`), same path |
| `proxy/active-backend.conf` | 5 lines, byte-identical to `make reset`'s canonical content |
| Stream region: `access_log` count / target / log-directory references | 1 / `/dev/stdout` / 0 |
| `docker compose logs proxy` | `172.19.0.6 -> :22 ssh backend=OLD selector=old upstream=172.19.0.2:22 status=200 bytes=3754/4450 sess=0.094` |
| `sh scripts/smoke.sh proxy` | **17 passed, 0 failed** — the canonical regression tripwire, unmoved, `guard_check` included |
| `sh scripts/smoke.sh ssh` | **48 passed, 0 failed** |
| `make test` | **168 passed, 0 failed** (145 inherited + 23 new) |
| `docker compose exec proxy ps` after the suite | one master, one worker, **zero** shutting-down workers |
| Stack at hand-off | five services healthy, selector `old` |

The D-40 measurement, taken live by the suite: a backgrounded `sleep 6; hostname` session opened
before `flip.sh new` returned `server-old`, while a session opened immediately after the reload
returned `server-new`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocker] The `nginx.conf` bind mount held a stale inode after the edit**

- **Found during:** Task 2
- **Issue:** `compose.yaml` mounts `./proxy/nginx.conf:/etc/nginx/nginx.conf:ro` as a **single file**
  (unlike `active-backend.conf`, which is reached through the `./proxy` **directory** mount precisely
  to avoid this). Any edit that replaces the file's inode — which is what a write-temp-then-rename
  editor does — leaves the container bound to the deleted inode. The symptom was maximally
  misleading: `nginx -t` reported `test is successful` and `nginx -s reload` returned 0, because both
  were validating the **old** config the container could still see. `netstat` showed no `:22`
  listener, and `grep -c "^stream" /etc/nginx/nginx.conf` inside the container returned `0` while the
  host file plainly had the block.
- **Fix:** `docker compose up -d --force-recreate --wait proxy` to re-resolve the mount. This is
  RESEARCH Pitfall 10's exact failure mode, second occurrence, on the one file the directory mount
  does not cover. No config change was made to work around it — `compose.yaml` is untouched, per the
  plan's do-not-modify list.
- **Files modified:** none (operational only)
- **Verification:** container `grep -c "^stream"` → 1; `nc -z 127.0.0.1 22` → open; full suite green.
- **Commit:** covered by `3b7dc6c` (no file change of its own)

**Total deviations:** 1 auto-fixed (1 × Rule 3). **Impact:** none on plan intent. It cost one
container recreate, which is not a cutover mechanism and does not touch D-14 — that rule governs how
a **flip** is applied, and every flip in this plan was a graceful reload.

## Implementation Notes for Later Plans

- **Editing `proxy/nginx.conf` requires recreating the proxy container, not reloading it.** See the
  deviation above. `nginx -t` passing is *not* evidence the container sees your edit — confirm with
  `docker compose exec -T proxy grep -c "^stream" /etc/nginx/nginx.conf`, or any equivalent read of
  the file from **inside** the container. `active-backend.conf` is immune (directory mount), which is
  why `flip.sh` needs no recreate and must never acquire one.
- **`ACTIVE_SEL` / `ACTIVE_LABEL` are exported, like `SSH_OPTS`,** for the same measured reason:
  `assert` runs its condition through a fresh `sh -c` that inherits variables but not functions.
  `selector_now()`, `set_active()`, `keyscan_fp()` and `hostkey_fp()` are top-level helpers the
  section calls *outside* assertions; Plan 03 can reuse all four.
- **`keyscan_fp` is the cheapest routing oracle in the repo** — no credential, ~0.1 s, and orthogonal
  to the banner. `verify.sh` should consider it as a corroborating reading rather than a substitute:
  the contractual identity claim over SSH remains the backend's own banner.
- **Region-scoped config checks must assert the range binds first.** An awk range that fails to bind
  yields zero lines, and every negative check over zero lines passes vacuously. This was observed for
  real during RED: `D-46 the stream region names no log directory path` **passed** while the block did
  not exist. It is only meaningful because the three positive checks beside it were failing.
- **`nc -z localhost 22` is correct for sshd and wrong for the proxy.** A stream `listen 22;` binds
  `0.0.0.0` only; busybox resolvers try `::1` first and do not retry. Use `127.0.0.1`.
- **The `stream` block must stay at column zero,** opening line and closing brace both, or three
  smoke assertions stop binding.

## Flagged Assumption Status

All four of this plan's flagged assumptions were `[probe: unclassified]` and are surfaced rather than
closed:

- **SSH-01** — the address-family edge the planner identified as the load-bearing one is now
  asserted, and it bit for real: `nc -z localhost 22` would have reported the listener closed. The
  residual unclassified risk (any *other* boundary shape for "the client can ssh to the nginx host on
  22") is unchanged.
- **SSH-02** — asserted structurally, as planned: a top-level `stream` block that `proxy_pass`es, and
  the shared include appearing exactly twice with comments stripped. No runtime input edge exists.
- **SSH-03** — the banner's own edges remain asserted in Plan 01; this plan adds only that they
  survive the hop, before and after the flip.
- **CUT-04** — the temporal boundary is now measured by the D-40 assertions rather than reasoned
  about. What is still *not* asserted is a session opened **inside** the sub-second interleave window
  itself; the suite opens sessions either clearly before or clearly after the reload.

## Handover note for Phase 4 (nothing staged, as planned)

- The host key presented at `app.demo.test:22` **now changes with the selector** — asserted twice in
  `section_ssh` as CUT-04's auth-free corroboration. That is Phase 4's entire premise, live in the
  rig, with no staging work done or needed.
- Every SSH assertion in this repo pins `-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null`
  with a comment naming Phase 4 as the reason. Without them, KEY-02 would silently turn every routing
  assertion here into a host-key assertion.
- The client's `known_hosts` remains ephemeral (no volume, no bind mount). Whether Phase 4 wants
  persistence across `docker compose down` is Phase 4's decision — flagged so it is not rediscovered.

## Issues Encountered

None outstanding. The single blocker (stale inode) is documented above and resolved.

## Next Phase Readiness

Ready for **03-03** (`scripts/verify.sh`, D-44/D-45). The proxied SSH path is live and asserted,
`SSH_OPTS` plus the four new helpers are available, and the rig is left running, healthy and
selecting `old`. Untouched by this plan: `compose.yaml`, `scripts/flip.sh`, `Makefile`, `backend/**`,
`client/**`, `status/**`, and `proxy/active-backend.conf`.

## Self-Check: PASSED

- `proxy/nginx.conf` — FOUND, contains a column-zero `stream {`
- `scripts/smoke.sh` — FOUND, `section_ssh` reports 48/48
- Commits `3f4be79`, `3b7dc6c` — both FOUND in `git log --all`
- `sh scripts/smoke.sh proxy` re-run at close — 17 passed, 0 failed

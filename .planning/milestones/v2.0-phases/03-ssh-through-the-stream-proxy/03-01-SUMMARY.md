---
phase: 03-ssh-through-the-stream-proxy
plan: 01
subsystem: backend-ssh-identity
tags: [ssh, sshd, banner, key-auth, docker-volume, smoke-tests]

requires:
  - "Phase 1 backends with openssh + supervisord and runtime ssh-keygen -A"
  - "Phase 1 client container with openssh-client and /usr/bin/timeout"
provides:
  - "BACK-04: an SSH login banner naming each backend, delivered by sshd's Banner so it survives a non-interactive `ssh host <command>`"
  - "BACK-05: non-interactive key auth from the client container into both backends, no -i flag, no password"
  - "demo-keys named volume holding the keypair (rw on client, :ro on both backends)"
  - "scripts/smoke.sh section_ssh — 25 assertions, and the exported SSH_OPTS flag set every later Phase 3/4 assertion reuses"
affects:
  - "Plan 03-02 (stream block) reuses SSH_OPTS and the capture idiom verbatim"
  - "Plan 03-03 (scripts/verify.sh) reads the banner as its contractual identity channel"
  - "Phase 4 KEY-01/KEY-02 inherit differing host keys, untouched"

tech-stack:
  added: []
  patterns:
    - "sshd_config.d drop-in, never an append (Alpine first-directive-wins)"
    - "one envsubst allowlist renders all three identity surfaces (D-16)"
    - "capture-into-a-variable then read $? on the next line; never pipe an ssh invocation"
    - "read-write/read-only volume asymmetry: the consuming tier cannot alter what it consumes"

key-files:
  created:
    - backend/templates/banner.template
    - client/entrypoint.sh
  modified:
    - scripts/smoke.sh
    - backend/entrypoint.sh
    - backend/Dockerfile
    - client/Dockerfile
    - compose.yaml

key-decisions:
  - "The banner is ONE line, byte-identical to that backend's HTTP /whoami body, so the anchored greps that prove BACK-03 over HTTP prove BACK-04 over SSH unchanged."
  - "The banner template's own `#` documentation is stripped at render time — sshd sends /etc/ssh/banner to the client verbatim, so it is the one template that cannot carry comments through."
  - "Key distribution via a demo-keys named volume written by the client entrypoint: no committed private key, no second image, no host state, and raw `docker compose up -d --wait` still yields a working rig."
  - "SSH_OPTS is an exported VARIABLE, not a shell function, because assert runs its condition through a fresh `sh -c`."
  - "The two host-key relaxation options are per-invocation and demo-only, commented as such. The client's own ssh config sets none — that default is Phase 4's raw material."

requirements-completed: [BACK-04, BACK-05]

coverage:
  - deliverable: "BACK-04 — each backend names itself in an SSH banner readable from a non-interactive invocation"
    verification:
      - kind: test
        ref: "scripts/smoke.sh#section_ssh BACK-04 server-old names itself pre-auth (remote command emits no stdout)"
        status: pass
      - kind: test
        ref: "scripts/smoke.sh#section_ssh BACK-04 effective config: server-old banner path took effect"
        status: pass
      - kind: test
        ref: "scripts/smoke.sh#section_ssh D-16 server-old: the ssh banner and the HTTP /whoami body are the identical string"
        status: pass
    human_judgment: false
  - deliverable: "BACK-05 — non-interactive key auth from the client into both backends"
    verification:
      - kind: test
        ref: "scripts/smoke.sh#section_ssh BACK-05 client -> server-old: key auth, non-interactive, no -i flag"
        status: pass
      - kind: test
        ref: "scripts/smoke.sh#section_ssh BACK-05 effective config: server-old authorizedkeysfile is the shared volume"
        status: pass
      - kind: command
        ref: "docker compose exec -T client ssh demo@server-new hostname -> rc=0, 'server-new'"
        status: pass
    human_judgment: false
  - deliverable: "The three BACK-04 probe edges (empty, ordering, adjacency)"
    verification:
      - kind: test
        ref: "scripts/smoke.sh#section_ssh BACK-04 empty edge / ordering edge / adjacency edge (7 assertions)"
        status: pass
    human_judgment: false
  - deliverable: "T-03-01 / T-03-05 — no key material in git, StrictModes-safe permissions"
    verification:
      - kind: test
        ref: "scripts/smoke.sh#section_ssh T-03-01 no key material is tracked by git"
        status: pass
      - kind: test
        ref: "scripts/smoke.sh#section_ssh T-03-05 server-old /keys/authorized_keys is mode 644 owned by root"
        status: pass
    human_judgment: false
  - deliverable: "Phase 1/2 regression surface intact (120 pre-existing assertions)"
    verification:
      - kind: command
        ref: "make test -> 145 passed, 0 failed (120 inherited + 25 new)"
        status: pass
      - kind: command
        ref: "sh scripts/smoke.sh proxy -> 17 passed, 0 failed"
        status: pass
    human_judgment: false
  - deliverable: "The presenter's on-stage experience: a clean command with no prompt and a legible identity line"
    human_judgment: true
    rationale: "Whether the banner reads well on a projector, and whether the presenter finds `docker compose exec client ssh demo@server-old hostname` comfortable to type live, is a judgment no assertion makes."

metrics:
  duration: "38 min"
  tasks: 3
  files: 7
  completed: 2026-07-21

status: complete
---

# Phase 3 Plan 01: SSH Identity and Key Auth Summary

Non-interactive ed25519 key auth from the `client` container into both backends via a `demo-keys`
named volume, with each backend announcing `OLD server-old` / `NEW server-new` through sshd's
pre-auth `Banner` — byte-identical to its HTTP `/whoami` body.

## Accomplishments

- **`section_ssh` in `scripts/smoke.sh`** — 25 assertions covering BACK-04, BACK-05, the three
  BACK-04 probe edges, T-03-01, T-03-05, and three self-guards that forbid the section from ever
  acquiring a quiet/log-level/forced-pty option or putting an `ssh` invocation on the left of a pipe.
  Exports `SSH_OPTS`, the flag set Plans 02 and 03 reuse.
- **`backend/templates/banner.template`** — one line, two fields, rendered by the same three-variable
  `envsubst` allowlist that already renders the nginx config and the HTML page. Three identity
  surfaces, one variable, no drift (D-16).
- **`/etc/ssh/sshd_config.d/10-demo.conf`** written in `backend/Dockerfile`, setting
  `AuthorizedKeysFile /keys/authorized_keys` and `Banner /etc/ssh/banner`. A drop-in, never an
  append — Alpine's stock config has an active `AuthorizedKeysFile` at line 45 below its `Include`
  at line 15, and first-directive-wins.
- **`client/entrypoint.sh` + the `demo-keys` volume** — idempotent keygen, `authorized_keys` at 644,
  private key at 600, and an `IdentityFile` ssh config so the presenter's command carries no `-i`.
  Read-write on `client`, `:ro` on both backends.

## Task Commits

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | RED `section_ssh` | `dfd5fc6` | `scripts/smoke.sh` |
| 2 | Banner template, entrypoint render, sshd drop-in | `6fff576` | `backend/templates/banner.template`, `backend/entrypoint.sh`, `backend/Dockerfile` |
| 3 | `demo-keys` volume and client entrypoint | `4cbb860` | `client/entrypoint.sh`, `client/Dockerfile`, `compose.yaml` |

## Verification Results

| Check | Result |
|-------|--------|
| `docker compose up -d --build --wait` | all five services healthy from a cold build |
| `sh scripts/smoke.sh ssh` | **25 passed, 0 failed** |
| `sh scripts/smoke.sh proxy` | **17 passed, 0 failed** — the canonical regression tripwire, unmoved |
| `make test` | **145 passed, 0 failed** (120 inherited + 25 new) |
| SSH into both backends, executed | `rc=0`; banner then `server-old` / `server-new` on the wire |
| Host keys still differ between backends | confirmed — Phase 4 precondition intact |
| `git ls-files` for key material | 0 matches |
| Host port 22 | no `:22->` mapping anywhere |
| Second `docker compose up -d --wait` | keypair fingerprint unchanged (idempotent) |
| Selector at hand-off | `OLD server-old`, stack running and healthy |

Captured stream, verbatim, proving the adjacency edge and D-43 together:

```
Warning: Permanently added 'server-old' (ED25519) to the list of known hosts.
OLD server-old        <- pre-auth Banner, on stderr
server-old            <- the remote command's own stdout
```

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] The banner template's own documentation would have been served to the SSH client**

- **Found during:** Task 2
- **Issue:** The plan instructs "Head the file with a comment stating it is rendered by the same
  explicit envsubst allowlist…". Unlike `default.conf.template` (nginx ignores `#`) and
  `index.html.template` (HTML comments), `/etc/ssh/banner` is sent to the client **verbatim** — sshd
  has no comment syntax for it. Rendering the template as-is would have put six comment lines into
  every SSH banner, breaking the single-line contract, the `NF==2 && NR==1` ordering-edge assertion,
  and the D-16 byte-identity with `/whoami`.
- **Fix:** The template keeps its documentation; the entrypoint strips leading `#` lines as it
  renders: `envsubst "$VARS" < /templates/banner.template | sed '/^#/d' > /etc/ssh/banner`. This
  preserves both plan requirements (a documented template, and a one-line banner) and does not
  introduce a second rendering mechanism — the allowlist and `envsubst` are unchanged, and the
  three-invocation count the plan asserts still holds.
- **Files modified:** `backend/templates/banner.template`, `backend/entrypoint.sh`
- **Verification:** `docker compose exec -T server-old cat /etc/ssh/banner` outputs exactly
  `OLD server-old`; equal to `curl -fsS http://localhost:9090/whoami`; `grep -c 'envsubst'` on
  non-comment lines of `backend/entrypoint.sh` = 3.
- **Commit:** `6fff576`

**Total deviations:** 1 auto-fixed (1 × Rule 1). **Impact:** none on plan intent — the deviation
protects the plan's own byte-identity contract, which the literal instruction would have violated.

## Implementation Notes for Later Plans

- **`SSH_OPTS` is exported for a measured reason.** `assert` runs its condition through a fresh
  `sh -c`, which inherits exported variables but not shell functions. Plan 02's stream assertions
  should reuse the same variable rather than redeclare the flags.
- **Never add `-q`, `LogLevel=…` or `-tt` to an SSH assertion.** Each of the first two suppresses the
  banner entirely, which silently turns BACK-04 into a vacuous check. `section_ssh` now carries three
  self-guards that fail the suite if any of them appears; the guards are written with bracket
  expressions so the audit cannot trip over its own text.
- **Never put an `ssh` invocation on the left of a pipe.** A pipeline reports the last command's
  status. This is enforced by a guard as well as by convention.
- **Poll for `/keys/authorized_keys` after a bring-up.** `client` has no healthcheck by design
  (D-02), so `--wait` returns before its entrypoint has written the key. `section_ssh` polls for up
  to 10 s. Do **not** solve this by adding a healthcheck to `client`.
- **Research assumption A2 is now confirmed empirically.** The client writes the key strictly after
  both backends have started, no `HUP` is issued anywhere, and key auth succeeds — so sshd does
  re-read `AuthorizedKeysFile` per authentication attempt. No `pkill -HUP sshd` mitigation is needed.

## Flagged Assumption Status

- **BACK-05 [probe: unclassified] — "could a third auth path silently open?"** Still open by design,
  surfaced for the verifier rather than resolved. What is now asserted: `sshd -T` reports
  `passwordauthentication yes` (path 1, the documented `demo:demo` fallback) and
  `authorizedkeysfile /keys/authorized_keys` (path 2, the volume key). No assertion enumerates the
  full effective auth-method set, so a third path introduced later would not be caught here. A
  `sshd -T | grep -i '^\(kbdinteractive\|gssapi\|hostbased\)'` sweep would close it and belongs in
  Plan 03's verify surface if the verifier wants it.

## Issues Encountered

None.

## Next Phase Readiness

Ready for **03-02** (the `stream` block on port 22 through the proxy). Everything it needs is in
place: SSH works backend-direct with key auth, the banner is the identity channel, `SSH_OPTS` and the
capture idiom are established, and the proxy's nginx is confirmed `--with-stream`. Nothing in this
plan touched `proxy/nginx.conf`, `proxy/active-backend.conf`, `scripts/flip.sh`, `status/`, or the
`Makefile`.

## Self-Check: PASSED

- `backend/templates/banner.template` — FOUND
- `client/entrypoint.sh` — FOUND
- Commits `dfd5fc6`, `6fff576`, `4cbb860` — all FOUND in `git log --all`

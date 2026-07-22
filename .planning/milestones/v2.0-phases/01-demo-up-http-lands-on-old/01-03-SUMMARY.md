---
phase: 01-demo-up-http-lands-on-old
plan: 03
subsystem: infra
tags: [nginx, redirect, 301, docker-compose, make, posix-sh, readme, dns, rfc6761]

# Dependency graph
requires:
  - "01-01: `server-old` published directly on 9090 — the 301 needs a real, reachable Location target (D-05)"
  - "01-01: `scripts/smoke.sh` section dispatcher, the `assert` idiom, and the `redirect` RED stub"
  - "01-01: the `.PHONY` target vocabulary, including `contrast` reserved for this plan"
  - "01-02: the `proxy` service, its directory bind mount, and the `demo` log format"
provides:
  - "`proxy/nginx.conf` 9093 server block — `return 301 http://app.demo.test:9090$request_uri`, a literal target with no request-derived component"
  - "Published host port `127.0.0.1:9093` — the redirect listener"
  - "`make contrast` — the D-09 technical backup view; two labelled lines, one command"
  - "`sh scripts/smoke.sh redirect` — 12 green assertions, both halves of the HTTP-04 contrast asserted together"
  - "`README.md` — the presenter-facing entry point: prerequisite, ports, contrast, HTTP-02 verification contract, command reference, layout, SSH framing, ENV-03 inspection notes"
  - "The HTTP-02 verification contract in prose — URL invariance with the SNAT rationale, so a verifier reading only the requirement text cannot fail the phase on source-IP grounds"
affects: [phase-02-cutover, phase-03-ssh-stream, phase-04-walkthrough]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Literal redirect target, never `$host`-derived: readable on a projector AND structurally incapable of being an open redirect (T-01-13)"
    - "The contrast IS the assertion: 9092-unchanged and 9093-changed asserted in the same smoke section, because apart they are two unrelated facts"
    - "Order-independence sandwich: measure 9092, hit 9093, measure 9092 again, assert byte identity — proves the listeners share no state"
    - "`docker compose port <svc> <n>` over grepping `ps --format {{.Ports}}` — Compose collapses adjacent publishes into a range and silently breaks literal greps"
    - "`curl --resolve` in the test/demo path so assertions do not depend on host `/etc/hosts` state (ENV-03)"
    - "RFC 6761 `.test` over RFC 6762 `.local` for any demo hostname on macOS"

key-files:
  created:
    - README.md
  modified:
    - proxy/nginx.conf
    - compose.yaml
    - scripts/smoke.sh
    - Makefile

key-decisions:
  - "The demo hostname changed from `app.demo.local` to `app.demo.test` mid-plan, at the human checkpoint, when the browser could not resolve it. `.local` is RFC 6762 multicast-DNS territory; macOS routes every `.local` lookup to mDNSResponder, which Tailscale's DNS takeover leaves unreachable, so `getaddrinfo` stalls 5s and fails despite a correct `/etc/hosts` entry. Recorded as D-22."
  - "`make contrast` and the 9093 smoke follows pass `--resolve app.demo.test:9090:127.0.0.1`. The redirect target is a literal hostname, so following it needs that name to resolve; without the flag the hop dies at DNS on any machine that has not done the one-time host step, and `make contrast` exits 6. The flag is per-invocation and touches no host state."
  - "Both port assertions moved to `docker compose port proxy <n>`. Publishing 9093 alongside 9092 made Compose collapse them into `127.0.0.1:9092-9093->9092-9093/tcp`, which silently broke plan 01-02's literal `127.0.0.1:9092->9092` grep."
  - "301, not 302, despite the caching cost. A permanent move is what a real hostname migration emits. The cost is handled by README's incognito instruction, not by weakening the status code."
  - "The redirect gets its own listener, not a path or a `Host` rule on 9092, so `port 9092 is the migration endpoint` stays a clean unqualified framing (D-08)."

requirements-completed: [HTTP-03, HTTP-04, ENV-03]

coverage:
  - id: D1
    description: "Port 9093 returns a 301 whose Location points at a real, reachable backend address on 9090 — not back at the proxy — with the requested path intact across the hop."
    requirement: HTTP-03
    verification:
      - kind: integration
        ref: "scripts/smoke.sh redirect#HTTP-03 9093 returns 301"
        status: pass
      - kind: integration
        ref: "scripts/smoke.sh redirect#HTTP-03 301 Location targets the backend on 9090"
        status: pass
      - kind: integration
        ref: "scripts/smoke.sh redirect#HTTP-03 request path survives the redirect (/whoami)"
        status: pass
      - kind: other
        ref: "curl -sS -o /dev/null -w '%{http_code} %{redirect_url}' http://localhost:9093/ -> '301 http://app.demo.test:9090/'"
        status: pass
    human_judgment: false
  - id: D2
    description: "curl -L against 9093 ends on a DIFFERENT URL than requested while the identical invocation against 9092 ends on the SAME URL — the contrast is directly comparable one line at a time, and the redirect genuinely lands on OLD."
    requirement: HTTP-04
    verification:
      - kind: integration
        ref: "scripts/smoke.sh redirect#HTTP-04 redirect side: 9093 ends on a DIFFERENT URL"
        status: pass
      - kind: integration
        ref: "scripts/smoke.sh redirect#HTTP-04 proxy side: 9092 ends on the IDENTICAL URL requested"
        status: pass
      - kind: integration
        ref: "scripts/smoke.sh redirect#HTTP-04 the redirect actually LANDS on OLD (target is reachable)"
        status: pass
      - kind: integration
        ref: "scripts/smoke.sh redirect#HTTP-04 9093 performs exactly 1 redirect / 9092 performs 0 redirects"
        status: pass
    human_judgment: false
  - id: D3
    description: "The browser URL bar stays put on 9092 and visibly changes to the backend's address on 9093, readable from a few metres back — the conceptual crux the demo rests on."
    requirement: HTTP-04
    verification:
      - kind: manual
        ref: "Task 3 human checkpoint steps 4-6: incognito window, app.demo.test:9092 then :9093 side by side"
        status: pass
    human_judgment: true
    rationale: "The mechanism is fully asserted from the CLI, but D-07's claim is about what an audience SEES in a URL bar from across a room. No command can judge whether the contrast reads at projector distance."
  - id: D4
    description: "make contrast prints the proxied and redirected results adjacently and labelled, giving the presenter one memorable command for the technical backup view."
    requirement: HTTP-04
    verification:
      - kind: other
        ref: "make contrast -> 'PROXIED 9092 -> final=http://localhost:9092/whoami redirects=0' and 'REDIRECT 9093 -> final=http://app.demo.test:9090/whoami redirects=1'; exit 0"
        status: pass
      - kind: manual
        ref: "Task 3 human checkpoint step 9: the two labelled lines make the same point as the browser tabs"
        status: pass
    human_judgment: true
    rationale: "Exit code and output content are mechanical; whether the two lines land as a substitute for a URL bar when a projector fails is a presenter judgment."
  - id: D5
    description: "The 301 Location target is a literal address in the config with no request-supplied component, so no request can steer where the client is sent."
    verification:
      - kind: integration
        ref: "scripts/smoke.sh redirect#T-01-13 Location target is literal, not $host-derived"
        status: pass
      - kind: other
        ref: "grep 'return 301' proxy/nginx.conf -> 'return 301 http://app.demo.test:9090$request_uri;' — no $host, no $http_host"
        status: pass
    human_judgment: false
  - id: D6
    description: "The two listeners share no state: the 9092 result is byte-identical measured before and after a 9093 request in the same session."
    verification:
      - kind: integration
        ref: "scripts/smoke.sh redirect#HTTP-04 order-independence: 9092 result identical before and after a 9093 request"
        status: pass
    human_judgment: false
  - id: D7
    description: "The 9093 request is logged with upstream=- and backend=- because nginx answered directly — the honest record of what happened, and a teaching moment on stage."
    verification:
      - kind: integration
        ref: "scripts/smoke.sh redirect#Pattern 6: the 9093 request logs upstream=- and backend=-"
        status: pass
      - kind: other
        ref: "docker compose logs proxy -> '172.19.0.1 -> localhost:9093 \"GET /whoami HTTP/1.1\" 301 upstream=- backend=- rt=0.000 urt=-'"
        status: pass
    human_judgment: false
  - id: D8
    description: "9093 is published on loopback only, matching 9090/9091/9092 — the rig is never offered to conference wifi."
    verification:
      - kind: integration
        ref: "scripts/smoke.sh redirect#T-01-15 9093 published on loopback only"
        status: pass
      - kind: other
        ref: "docker compose port proxy 9093 -> 127.0.0.1:9093"
        status: pass
    human_judgment: false
  - id: D9
    description: "README.md lets a presenter who has never seen the rig perform the one-time host setup, start the demo, narrate the four ports, run the contrast without hitting the 301 cache, and reset to a clean state — with no host state modified by any command in the repository."
    requirement: ENV-03
    verification:
      - kind: other
        ref: "acceptance greps: sudo tee / /etc/hosts / all four ports / incognito / active-backend.conf / 192.168.65.1 / 'docker compose up' at line 46 before 'make up' at line 51 / all 9 .PHONY targets present"
        status: pass
      - kind: manual
        ref: "Task 3 human checkpoint step 2: the /etc/hosts instruction worked verbatim from README with no guesswork"
        status: pass
    human_judgment: true
    rationale: "The greps prove the required content is present; whether the document is actually usable by someone under stage pressure is exactly what the checkpoint asked a human to judge. The hostname failure surfaced BY that judgment is the proof the check was worth having."
  - id: D10
    description: "No repository command executes privilege escalation or modifies host OS state. The escalation token appears only as README prose and as make status's printed remediation line."
    requirement: ENV-03
    verification:
      - kind: other
        ref: "grep -nE '^[[:space:]]*[^@#]*(^|[|;&[:space:]])sudo[[:space:]]' Makefile scripts/*.sh compose.yaml | wc -l -> 0"
        status: pass
      - kind: other
        ref: "make status exits 0 and still prints the full remediation line when the entry is absent; no setup script, make install, or bootstrap entry point exists"
        status: pass
    human_judgment: false
  - id: D11
    description: "No cloud account, credential, registry login or paid service is required — proving a negative, which only inspection can do."
    requirement: ENV-03
    verification:
      - kind: manual
        ref: "Task 3 human checkpoint step 8: repository inspected for registry auth, cloud SDK config, .env secrets, paid-service dependencies; docker compose up succeeded with no docker login performed"
        status: pass
    human_judgment: true
    rationale: "ENV-03 is an absence claim. `01-VALIDATION.md` classifies it manual-only for exactly this reason: no assertion can prove nothing is missing from a repository, only a human reading it can."
  - id: D12
    description: "The OLD/NEW word is legible from across the room independently of colour — the word carries the signal, not the hue."
    requirement: BACK-03
    verification:
      - kind: manual
        ref: "Task 3 human checkpoint step 7: stepped back from the screen, compared 9090 amber OLD against 9091 green NEW, confirmed the word reads with the colour covered"
        status: pass
    human_judgment: true
    rationale: "D-10's substance is cross-room legibility for an audience including colour-blind viewers. Font size and contrast ratio are mechanical; 'readable from the back of the room' is not."

# Metrics
duration: 22 min
completed: 2026-07-21
status: complete
---

# Phase 01 Plan 03: The Redirect Contrast and the Presenter README Summary

**A dedicated nginx listener on 9093 returns a 301 to a literal `http://app.demo.test:9090$request_uri` while 9092 keeps proxying transparently — so the audience sees, in two browser tabs, the difference between someone answering on your behalf and being told to go somewhere else; `README.md` makes the whole rig performable by someone who has never seen it, including the 301-caching trap that would silently break a second run.**

## Performance

- **Duration:** 22 min (including the human checkpoint pause and the hostname remediation)
- **Tasks:** 3 (2 automated, 1 human-verify checkpoint)
- **Files:** 1 created, 4 modified

## Accomplishments

- **The demo now has its point.** Before this plan, Phase 1 proved a request could traverse a proxy. Now it proves *why that matters*: `make contrast` prints `redirects=0` with an unchanged URL on 9092 and `redirects=1` with a changed URL on 9093, one command, two labelled lines. The audience does not need to understand nginx to understand that only one of those is invisible to the client.
- **The redirect cannot be steered by a request.** `return 301 http://app.demo.test:9090$request_uri;` — the target is a literal written into the config, with no `$host` or `$http_host` anywhere near it. This is both the readable-on-a-projector choice and the reason T-01-13 (open redirect) has no attack surface at all rather than a mitigated one. Asserted by grep so it cannot regress silently.
- **The contrast is asserted as a contrast.** Both halves of HTTP-04 live in one smoke section deliberately. "9093 changes the URL" and "9092 does not" are only meaningful side by side; asserted in separate sections they are two unrelated facts and the demo's actual claim goes unverified.
- **The listeners provably share no state.** The order-independence assertion measures 9092, fires a 9093 request, measures 9092 again, and asserts byte identity. That is the mechanically checkable half of the concurrency backstop. The one genuine cross-run interference — a browser caching the 301 indefinitely — is not CLI-checkable and is handled where it actually bites, in README's incognito instruction. `curl` does not cache and is immune.
- **`README.md` states the HTTP-02 verification contract in prose.** This exists so a phase verifier working from the requirement text alone cannot fail Phase 1 on environmental grounds: HTTP-02 is verified as URL invariance (`%{url_effective}` unchanged, `%{num_redirects}` = 0, `$host:$server_port` constant in the log), NOT as source-IP invariance — because macOS Docker Desktop SNATs every host-originated request to `192.168.65.1` before nginx sees it, making the alternative reading unsatisfiable no matter how the proxy is configured.
- **The human checkpoint earned its keep on the first try.** Steps 4-6 failed for the presenter — `app.demo.test` was `app.demo.local` at that point and the browser would not resolve it, despite a correct `/etc/hosts` entry. No automated assertion in the suite could have caught this: all 42 use `localhost` or Docker's embedded DNS, neither of which goes near macOS mDNSResponder. See Deviations.
- **The suite went from 30/1 to 42/0.** Twelve new redirect assertions, and the last stub in Phase 1 is gone.

## Task Commits

1. **Task 1: The redirect listener and the side-by-side contrast** — `a4b39cd` (feat)
2. **Task 2: The presenter README** — `4e302ca` (docs)
3. **Task 3: Browser side-by-side proof and ENV-03 inspection** — human checkpoint; approved. The hostname remediation it surfaced is `533df64` (fix), authored by the orchestrator during the pause.

Task 1 carries `tdd="true"`. Its RED gate is plan 01-01's `section_redirect()` stub — an unconditional `fail "redirect: not implemented yet — plan 01-03"`, verified red on this branch immediately before Task 1 ran (`0 passed, 1 failed`, exit 1). See TDD Gate Compliance.

## Files Created/Modified

- `README.md` (new) — the presenter entry point. Ten sections: the one-time host prerequisite framed as a host-OS step never automated; starting the demo with `docker compose up` shown before `make up`; the four-port table with the 90/91/92/93 mnemonic; the contrast demo, browser-primary with the incognito requirement stated prominently and `make contrast` as the immune backup; the HTTP-02 verification contract; the full command reference; the layout tree calling out `proxy/active-backend.conf`; the SSH framing that keeps Phase 3's "no client change" claim honest; the no-cloud/no-cost inspection notes for ENV-03; and the privilege-escalation contract.
- `proxy/nginx.conf` — a second `server` block on 9093 with one `location /` issuing `return 301` to a literal target. No `add_header`, no `$host`, no stream block. The comment block explains the 301-vs-302 trade and the literal-target rule to whoever reads the config on stage.
- `compose.yaml` — `127.0.0.1:9093:9093` added to the proxy's publishes, same explicit loopback binding as 9090/9091/9092.
- `scripts/smoke.sh` — `section_redirect()` replaces the RED stub with 12 assertions; `section_proxy()`'s T-01-10 port assertion switched to `docker compose port`.
- `Makefile` — the `contrast` recipe, four `@`-prefixed lines, GNU Make 3.81-compatible, no `.ONESHELL:`.

## Decisions Made

See `key-decisions` in the frontmatter. The one Phase 2 must inherit is D-22 — the hostname. See the first deviation below.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug, surfaced by the human checkpoint] The demo hostname changed from `app.demo.local` to `app.demo.test`**

- **Found during:** Task 3, the human checkpoint — the presenter added the `/etc/hosts` entry exactly as README instructed and the browser still could not reach `app.demo.local:9092`.
- **Issue:** `.local` is reserved by **RFC 6762 for multicast DNS**. macOS routes every `.local` lookup to mDNSResponder (`scutil --dns` resolver #4, `options: mdns`, `timeout: 5`) rather than through the normal resolution path — `/etc/hosts` is not consulted the way you would expect. The presenter runs Tailscale, whose DNS takeover leaves that resolver `reach: Not Reachable`, so `getaddrinfo` — which is what `curl` and every browser use — stalled the full five seconds and then failed. `ping` and `dscacheutil` take a different code path and succeeded, which is precisely why the failure looked inconsistent and hard to diagnose.
- **Measured on this machine:** `nope.demo.local` → **5.03s** then failure. `nope.demo.test` → **0.05s**.
- **Fix:** the demo hostname is now `app.demo.test`. **RFC 6761 reserves `.test` for exactly this purpose** — it never reaches real DNS, is never routed to mDNS, and does not collide with the tailnet search domains (`unicorn-bee.ts.net`, `ts.net`, `lan`). Tailscale MagicDNS was considered and rejected on three counts: it issues *machine* names (`tonys-macbook-pro.unicorn-bee.ts.net`) rather than service names, which undercuts the "the hostname never changed" narrative the demo rests on; it does not resolve inside the Docker bridge network, so D-02's `client` container would need a second mechanism anyway; and it would require rebinding the published ports off `127.0.0.1`, exposing the demo — and from Phase 3 an sshd carrying demo credentials — to the entire tailnet (threat T-01-06).
- **Files modified:** `Makefile`, `README.md`, `compose.yaml`, `proxy/nginx.conf`, `scripts/smoke.sh`, plus the forward-looking planning docs (`01-CONTEXT.md` gained **D-22**, all three PLANs, `01-VALIDATION.md`, `SKELETON.md`, `ROADMAP.md`). `01-RESEARCH.md` and the `01-01`/`01-02` SUMMARY files were left as historical records with a superseded-hostname banner prepended.
- **Verification:** re-verified from a cold `down -v` + `up --build --wait` — 42/42 smoke assertions pass; `make contrast` shows `final=http://app.demo.test:9090/whoami redirects=1` on the redirect side and `redirects=0` on the proxy side; `docker compose exec client curl http://app.demo.test:9092/whoami` → `OLD server-old`.
- **Commit:** `533df64` (authored by the orchestrator during the checkpoint pause).

> **For Phase 2, 3 and 4: do not reintroduce `.local`.** The hostname is `app.demo.test` and the reason is environmental, not cosmetic. Every automated assertion in this suite passes under either name — they use `localhost` or Docker's embedded DNS, neither of which touches mDNSResponder — so a regression here would be invisible to the test suite and would surface only in a browser, on stage. D-22 in `01-CONTEXT.md` is the canonical record.

**2. [Rule 3 - Blocking] `make contrast` exited 6 because the redirect target could not be resolved**

- **Found during:** Task 1, first live run of `make contrast`.
- **Issue:** the 301 target is a literal hostname, so following it with `curl -L` requires that name to resolve on the host. The `/etc/hosts` entry is deliberately *not* created by this repository, so on any machine that has not yet done the one-time step the hop dies with `curl: (6) Could not resolve host` and `make contrast` exits non-zero — failing an acceptance criterion and, worse, making the presenter's backup view unavailable exactly when the browser path is also broken.
- **Fix:** `--resolve app.demo.test:9090:127.0.0.1` on the redirect-following invocations in `make contrast` and in the three 9093 `-L` smoke assertions. This is a per-invocation client-side resolution: it touches no host state (ENV-03 intact) and changes nothing the demo claims, since the URL the client ends on is still the backend's. It also means the CLI contrast works *before* the presenter has done the host prerequisite.
- **Files modified:** `Makefile`, `scripts/smoke.sh`
- **Verification:** `make contrast` exits 0 and prints both labelled lines; the new `HTTP-04 the redirect actually LANDS on OLD` assertion now genuinely fetches through the redirect and greps `OLD server-old`, so the hop is proven end to end rather than only at the `Location` header.
- **Commit:** `a4b39cd`

**3. [Rule 1 - Bug] Publishing 9093 silently broke plan 01-02's port assertion**

- **Found during:** Task 1, first full-suite run after adding the port.
- **Issue:** with two adjacent ports published on one service, Compose collapses them in `docker compose ps --format '{{.Ports}}'` into `127.0.0.1:9092-9093->9092-9093/tcp`. Plan 01-02's `T-01-10 9092 published on loopback only` greps for the literal `127.0.0.1:9092->9092` and started failing — a false negative on a security assertion (T-01-10) caused entirely by an unrelated port being added.
- **Fix:** both port assertions now use `docker compose port proxy <n>`, which resolves one container port at a time and is immune to range collapsing. `docker compose port proxy 9092` → `127.0.0.1:9092`; same for 9093.
- **Files modified:** `scripts/smoke.sh`
- **Verification:** both assertions green; `docker compose ps` still shows the collapsed range, which is now cosmetic rather than load-bearing. Noted in the smoke comment so a future reader does not "fix" it back.
- **Commit:** `a4b39cd`

**Total deviations:** 3 auto-fixed (2 bugs, 1 blocking). One — the hostname — is architecturally significant enough that it was escalated to a new locked decision (D-22) rather than left as a plan-local note.

**Impact on plan:** none on scope. Every acceptance criterion in both tasks is met. The hostname change is a substitution applied uniformly; the `--resolve` and `docker compose port` changes make assertions more robust than the plan specified, not less.

## Issues Encountered

- **The suite could not have caught the hostname problem.** Every one of the 42 assertions uses either `localhost` (host path) or Docker's embedded DNS (client-container path). Neither goes near macOS mDNSResponder. The only path that does is a browser on the host — which is precisely the path D-07 makes primary and `01-VALIDATION.md` classifies as manual-only. This is the strongest possible argument for the manual-only rows being real verification rather than ceremony.
- **`curl` and `ping` disagreed**, which made the failure look intermittent rather than systematic. `ping` and `dscacheutil` resolve `.local` through a different code path than `getaddrinfo`, so the entry appeared present and working right up until a browser or `curl` touched it.

## Verification Results

Plan-level `<verification>`, run from cold, in order:

| # | Check | Result |
|---|-------|--------|
| 1 | `make reset` — exits zero, four services up, both backends healthy | PASS |
| 2 | `sh scripts/smoke.sh` (all sections) | PASS — **42 passed, 0 failed**, exit 0 |
| 3 | `curl -sS -i http://localhost:9093/whoami` — 301, `Location` ending `/whoami`, targeting 9090 | PASS — `Location: http://app.demo.test:9090/whoami` |
| 4 | `make contrast` — proxied unchanged/0 redirects, redirect changed/1 redirect | PASS — exit 0, both labelled lines |
| 5 | `docker compose logs proxy \| grep 9093` — `-` for upstream and backend | PASS — `301 upstream=- backend=- rt=0.000 urt=-` |
| 6 | Task 3 human checkpoint — browser side-by-side, cross-room legibility, ENV-03 inspection | PASS — approved, after the hostname remediation |
| 7 | `make reset && make test` — the cold-start path (the phase gate) | PASS |

Task 2 acceptance criteria confirmed individually:

- `sudo tee`, `/etc/hosts`, `app.demo.test`, all four port numbers, `incognito`, `active-backend.conf`, `192.168.65.1` — all present in `README.md`.
- `docker compose up` first appears at line 46; `make up` first appears at line 51. The Makefile is documented as convenience, not a dependency (D-20).
- All nine `.PHONY` targets (`up down status logs test reset contrast reload check`) appear in the command reference.
- Privilege-escalation contract: `grep -nE '^[[:space:]]*[^@#]*(^|[|;&[:space:]])sudo[[:space:]]' Makefile scripts/*.sh compose.yaml | wc -l` → **0**. `make status` still prints the full remediation line when the entry is absent and exits zero. No setup script, `make install`, or bootstrap entry point exists.

## Human Checkpoint Outcome

**Approved.** The presenter worked all nine steps of Task 3. Three items are discharged that no command could have covered:

1. **HTTP-04's browser proof (D-07).** In an incognito window, `http://app.demo.test:9092/` shows the amber OLD banner with the URL bar unchanged; `http://app.demo.test:9093/` shows the same banner with the URL bar visibly changed to `app.demo.test:9090`. Side by side, the contrast reads at distance. This is the conceptual crux of the whole demo and the only verification that touches the actual claim.
2. **Cross-room legibility (D-10 / BACK-03).** OLD and NEW are distinguishable from across the room, and the *word* carries the signal independently of the colour.
3. **ENV-03 inspection.** No registry credentials, no cloud SDK config, no `.env` with secrets, no paid-service dependency. `docker compose up` succeeded with no `docker login` performed.

Step 2 — "confirm README's instruction worked verbatim" — is what surfaced the `.local` failure. The checkpoint diverged, the divergence was diagnosed and fixed as D-22, and the steps were re-run green.

## TDD Gate Compliance

Task 1 carries `tdd="true"`; the plan is `type: execute`, so the plan-level RED/GREEN/REFACTOR commit sequence does not strictly apply. The RED gate was nonetheless real and verified: `section_redirect()` shipped in plan 01-01's `test(01-01)` commit as an unconditional failure and was confirmed red on this branch immediately before Task 1 ran (`sh scripts/smoke.sh redirect` → `0 passed, 1 failed`, exit 1). Task 1 then landed as a `feat(01-03)` GREEN commit taking it to 12/12. No separate `test(01-03)` commit exists because the failing assertion already existed on the branch — which is exactly what the Wave 1 stub was authored for. No REFACTOR commit was needed.

This is the same pattern plan 01-02 documented; all three Phase 1 plans used the Wave 1 stub as their RED gate, which is why `scripts/smoke.sh` has never been green with an unimplemented section.

## Threat Mitigations Applied

| Threat | Disposition | Evidence |
|--------|-------------|----------|
| T-01-13 Tampering (open redirect via `Host`-derived `Location`) | mitigated | `return 301 http://app.demo.test:9090$request_uri;` — a literal target with no request-supplied component. Asserted by `scripts/smoke.sh redirect#T-01-13`, which greps the `return 301` line for the literal host:port, so a future edit to `$host` fails the suite |
| T-01-14 Tampering / Elevation (repository modifying host OS state) | mitigated | Recipe-position grep over `Makefile`, `scripts/*.sh`, `compose.yaml` returns **0**. No setup script, no `make install`, no bootstrap. The escalation token appears only in `README.md` prose and `make status`'s printed remediation line — both deliberately preserved, since suppressing them would leave a presenter who skipped the prerequisite with no remediation path |
| T-01-15 Information Disclosure (9093 bound on all interfaces) | mitigated | Published `127.0.0.1:9093:9093`; asserted via `docker compose port proxy 9093` → `127.0.0.1:9093` |
| T-01-16 Repudiation (no evidence of what nginx did on 9093) | accepted, as planned | The `demo` log format records the 9093 request with `-` for both upstream and backend, which correctly indicates nginx answered directly. Asserted rather than merely accepted — `scripts/smoke.sh redirect#Pattern 6` greps for `upstream=- backend=- ` on a `:9093` line, so the teaching moment cannot silently disappear |
| T-01-SC Tampering (package installs) | accepted | Nothing installed from any registry by this plan |

No security-relevant surface was introduced beyond the plan's `<threat_model>`. **No threat flags raised.**

The hostname change (D-22) has one security-adjacent note worth recording: the rejected Tailscale MagicDNS alternative would have required rebinding the published ports off `127.0.0.1`, which would have exposed the rig — and from Phase 3 an sshd carrying a `demo:demo` credential — to the whole tailnet. That is threat T-01-06, and it was a material input to choosing `.test` over MagicDNS rather than a purely ergonomic preference.

## Known Stubs

**None.** `scripts/smoke.sh` has no remaining stub sections and `make contrast` is no longer `.PHONY`-only. Phase 1's automated surface is complete: 42 assertions across `backends`, `proxy` and `redirect`, all green from a cold reset.

## Flagged Assumptions Carried Forward

**HTTP-03 (`unclassified` at probe time).** The assumption the plan carried held and is now implemented as stated: "the backend directly" means `server-old`'s own published port (9090), not `server-new`, and not a load-balanced or dynamically selected backend. **The redirect target is deliberately static and does NOT follow the `$active_backend` selector** — the point of the contrast is the mechanism, not the destination. If a later phase wants the redirect to follow the Phase 2 flip, that is a new decision to make explicitly, not an implicit one to inherit. Concretely: after Phase 2 flips to NEW, 9092 will land on NEW while 9093 still redirects to 9090/OLD. That is correct and intended, and the presenter should not be surprised by it mid-demo.

## User Setup Required

- **D-03 / D-22 one-time host setup:** `echo '127.0.0.1  app.demo.test' | sudo tee -a /etc/hosts`. **Completed by the presenter during the Task 3 checkpoint** — `make status` now reports `hosts: OK`. Note the hostname: an entry for the old `app.demo.local` is harmless but useless, and if one was added before D-22 it can be removed. This remains the only host state the demo touches, and removing that line is the complete uninstall.

## Next Phase Readiness

Phase 1 is functionally complete. Ready for Phase 2's live cutover. Specifically in place for it:

- **The flip file is untouched by this plan.** `proxy/active-backend.conf` is still the canonical five-line include selecting `old`, and `make reset` still restores it byte-identically.
- **The log format is settled and asserted.** `backend=$upstream_http_x_backend` renders `backend=OLD` today and will render `backend=NEW` after the flip — EVID-01's entire foundation, asserted in the suite so it cannot drift.
- **`make reload`'s test-then-reload-then-verify discipline** is the shape `make flip` should extend.
- **`make contrast` is a second flip-moment view** Phase 2 gets for free: after the flip, the proxied line will show NEW while the redirect line still shows 9090/OLD, which makes the "the redirect is static, the proxy is the migration mechanism" point without any extra tooling.
- **The hostname is `app.demo.test`.** Phase 2 must not reintroduce `.local` — the test suite would not catch it.
- **`README.md` exists** and Phase 4's walkthrough document should extend it rather than duplicate it; the port narration, the incognito caveat and the HTTP-02 verification contract are already written and verified.

**Current state:** the stack is left running and healthy — `server-old` and `server-new` healthy, `proxy` and `client` up, `proxy/active-backend.conf` in its canonical five-line state selecting `old`. `curl http://localhost:9092/whoami` returns `OLD server-old` and `curl -sS -o /dev/null -w '%{http_code}' http://localhost:9093/` returns `301` right now.

No blockers.

## Self-Check: PASSED

- `README.md` — verified present on disk.
- `proxy/nginx.conf` — verified present, `return 301 http://app.demo.test:9090$request_uri;` at line 93.
- Commits verified in `git log`: `a4b39cd` (Task 1), `4e302ca` (Task 2), `533df64` (the D-22 hostname remediation).
- Working tree clean at the time of writing; the stack verified running and healthy.

---
*Phase: 01-demo-up-http-lands-on-old*
*Completed: 2026-07-21*

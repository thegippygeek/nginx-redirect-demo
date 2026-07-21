# Roadmap: Server Migration Redirect Demo

## Overview

The demo is built as four vertical slices, each one a bigger piece of the on-stage narrative. Phase 1 gets the whole rig up with one command and lands HTTP on `server-old` through nginx — including the 301 redirect contrast that sets up the conceptual point. Phase 2 delivers the money shot: the live upstream flip, with logs and a status page proving where traffic went. Phase 3 extends the same cutover to SSH over nginx's `stream` module and adds an automated verify script that asserts which backend answered over both protocols. Phase 4 stages the SSH host-key failure, fixes it, and wraps the whole thing in a written walkthrough the presenter can run cold.

Every phase ends in something demoable in front of an audience.

## Phases

**Phase Numbering:**

- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: Demo Up, HTTP Lands on OLD** - One command brings up nginx + two backends; port 9092 proxies to `server-old` and a second port shows the 301 redirect contrast
- [ ] **Phase 2: The Live HTTP Cutover** - Edit upstream, reload, and HTTP lands on NEW with logs and a status page as proof
- [ ] **Phase 3: SSH Through the Stream Proxy** - `ssh` on port 22 lands on the active backend across the same cutover, with a verify script asserting both protocols
- [ ] **Phase 4: Host-Key Gotcha and the Presenter Walkthrough** - The `REMOTE HOST IDENTIFICATION HAS CHANGED` failure staged, fixed, and documented as a runnable narrative

## Phase Details

### Phase 1: Demo Up, HTTP Lands on OLD

**Goal**: Presenter runs one command and can immediately show a browser/curl hitting nginx on port 9092, landing on `server-old`, with the URL unchanged — and show the redirect approach alongside it changing the URL
**Mode:** mvp
**Depends on**: Nothing (first phase)
**Requirements**: ENV-01, ENV-02, ENV-03, ENV-04, BACK-01, BACK-02, BACK-03, HTTP-01, HTTP-02, HTTP-03, HTTP-04
**Success Criteria** (what must be TRUE):

  1. Presenter runs `docker compose up` and nginx, `server-old`, and `server-new` all come up healthy with no cloud account, credentials, or prior setup
  2. `curl http://localhost:9092` returns a body that names the backend as OLD with its hostname, and the client's address and port are unchanged in the request
  3. Hitting the redirect port returns a 3xx with a `Location` header, and `curl -L` visibly ends up on a different URL than the one requested — the contrast with the proxied port is showable side by side
  4. Presenter runs one teardown command and can bring the demo back to the identical clean starting state
  5. `nginx -V` inside the proxy container shows the `stream` module is compiled in, so port 22 proxying is possible later

**Plans**: 3/3 plans executed

Plans:
**Wave 1**

- [x] 01-01-PLAN.md — Walking skeleton foundation: test harness, presenter Makefile, the one-image/two-identities backend, and `docker compose up` bringing both boxes up healthy (ENV-01/02/03, BACK-01/02/03)

**Wave 2** *(blocked on Wave 1 completion)*

- [x] 01-02-PLAN.md — nginx joins the stack: transparent reverse proxy on 9092 landing on `server-old` via `app.demo.test`, plus the flip include, log format, and invalid-selector guard (ENV-04, HTTP-01/02)

**Wave 3** *(blocked on Wave 2 completion)*

- [x] 01-03-PLAN.md — The 301 redirect contrast on 9093, the presenter README, and the human browser side-by-side verification (HTTP-03/04, ENV-03 inspection)

### Phase 2: The Live HTTP Cutover

**Goal**: Presenter flips the nginx upstream from old to new on stage, reloads, and the audience sees the same URL now answered by `server-new` — with independent evidence confirming it
**Mode:** mvp
**Depends on**: Phase 1
**Requirements**: CUT-01, CUT-02, CUT-03, CUT-05, EVID-01, EVID-02, EVID-03
**Success Criteria** (what must be TRUE):

  1. Presenter edits the nginx upstream and reloads, and the identical `curl http://localhost:9092` command — no client-side change of any kind — now returns a body naming the backend as NEW
  2. A live tail of nginx access logs shows each request and which upstream served it, visibly switching from old to new at the moment of the flip
  3. A status page shows which backend is currently active and lists recent requests with the backend that answered each
  4. Presenter can flip back to `server-old` and re-run the whole cutover without tearing anything down

**Plans**: 4 plans
**UI hint**: yes

Plans:
**Wave 1**

- [ ] 02-01-PLAN.md — The flip pipeline: gate both backends, rewrite the one word, print the diff, reload, prove via the `:8081` oracle, settle; plus the dual evidence log and the two log views (CUT-01/02/03/05, EVID-01)

**Wave 2** *(blocked on Wave 1 completion)*

- [ ] 02-02-PLAN.md — The stateless evidence service: a fourth container deriving config, traffic, counters and boundary from two read-only files plus a live proxy probe, exposed as `/api/status` (EVID-01/02/03, CUT-05)

**Wave 3** *(blocked on Wave 2 completion)*

- [ ] 02-03-PLAN.md — The projected status page to `02-UI-SPEC.md`: the D-27 dual reading, the recent-requests table with its flip boundary, the stats rail, and the four states with the convergence sequence (EVID-02/03)

**Wave 4** *(blocked on Wave 3 completion)*

- [ ] 02-04-PLAN.md — UI token audit as a permanent regression guard, the presenter's Phase 2 README, and the human visual sign-off (EVID-02/03, CUT-05)

### Phase 3: SSH Through the Stream Proxy

**Goal**: Presenter SSHes to port 22 on the same host and lands on whichever backend is active, proving the cutover is not just an HTTP trick — with a script that asserts it automatically
**Mode:** mvp
**Depends on**: Phase 2
**Requirements**: BACK-04, BACK-05, SSH-01, SSH-02, SSH-03, CUT-04, EVID-04, EVID-05
**Success Criteria** (what must be TRUE):

  1. Presenter runs `ssh` against the nginx host on port 22 with a known credential or key and gets a shell on the active backend, whose login banner names it as OLD or NEW with its hostname
  2. The nginx config visibly uses a `stream` block proxying raw TCP — presenter can show it is a TCP proxy, not an HTTP redirect
  3. After the upstream flip, a new SSH session lands on `server-new` and its banner says NEW, using the identical `ssh` command as before
  4. A verify script issues an HTTP request and an SSH connection, reports which backend answered each, and exits non-zero when the observed backend does not match the expected one

**Plans**: TBD

### Phase 4: Host-Key Gotcha and the Presenter Walkthrough

**Goal**: Presenter can deliberately trigger the SSH host-key mismatch after cutover, fix it live without touching the client, and run the entire demo from a written script
**Mode:** mvp
**Depends on**: Phase 3
**Requirements**: KEY-01, KEY-02, KEY-03, KEY-04, WALK-01, WALK-02, WALK-03
**Success Criteria** (what must be TRUE):

  1. Presenter can start the demo in a state where `server-new` has different SSH host keys from `server-old`
  2. After the cutover in that state, the client's `ssh` attempt fails visibly with `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED`
  3. Presenter applies the documented host-key transfer fix, and the same `ssh` command then succeeds against `server-new` with no edit to the client's `known_hosts`
  4. A written walkthrough covers the full narrative in order — show old → flip → show new → SSH gotcha → fix — with the exact command, the expected output, and the audience takeaway for each step
  5. Someone who has never seen the demo can follow the walkthrough top to bottom and reproduce every beat

**Plans**: TBD

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Demo Up, HTTP Lands on OLD | 3/3 | Complete | 2026-07-21 |
| 2. The Live HTTP Cutover | 0/4 | Planned | - |
| 3. SSH Through the Stream Proxy | 0/TBD | Not started | - |
| 4. Host-Key Gotcha and the Presenter Walkthrough | 0/TBD | Not started | - |

## Requirement Coverage

| Phase | Requirements | Count |
|-------|--------------|-------|
| 1 | ENV-01, ENV-02, ENV-03, ENV-04, BACK-01, BACK-02, BACK-03, HTTP-01, HTTP-02, HTTP-03, HTTP-04 | 11 |
| 2 | CUT-01, CUT-02, CUT-03, CUT-05, EVID-01, EVID-02, EVID-03 | 7 |
| 3 | BACK-04, BACK-05, SSH-01, SSH-02, SSH-03, CUT-04, EVID-04, EVID-05 | 8 |
| 4 | KEY-01, KEY-02, KEY-03, KEY-04, WALK-01, WALK-02, WALK-03 | 7 |

**Total: 33/33 v1 requirements mapped. No orphans, no duplicates.**

---
*Roadmap created: 2026-07-21*

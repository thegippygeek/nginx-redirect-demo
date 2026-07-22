# Requirements: Server Migration Redirect Demo

**Defined:** 2026-07-21
**Core Value:** A live, on-stage flip of the nginx upstream from old to new where the client keeps hitting the same hostname and port, and unmistakably lands on the new server.

## v1 Requirements

Requirements for initial release. Each maps to roadmap phases.

### Environment

- [x] **ENV-01**: Presenter can bring the entire demo up with a single `docker compose up` command
- [x] **ENV-02**: Presenter can tear the demo down and bring it back to a clean starting state with a single command
- [x] **ENV-03**: Demo runs entirely locally with no cloud account, credentials, or cost
- [x] **ENV-04**: nginx container includes the `stream` module so TCP proxying on port 22 works

### Backends

- [x] **BACK-01**: A `server-old` container serves HTTP and accepts SSH connections
- [x] **BACK-02**: A `server-new` container serves HTTP and accepts SSH connections
- [x] **BACK-03**: Each backend's HTTP response body states its own identity (OLD or NEW) and hostname
- [x] **BACK-04**: Each backend's SSH login banner states its own identity (OLD or NEW) and hostname
- [x] **BACK-05**: Presenter can log into either backend over SSH with a known credential or key

### HTTP Routing

- [x] **HTTP-01**: Client can reach the active backend by connecting to nginx on port 9092 over plain HTTP
- [x] **HTTP-02**: nginx forwards port 9092 traffic transparently — the client's address and port never change
- [x] **HTTP-03**: A separate nginx port demonstrates the 301/302 redirect approach, returning a `Location` header that sends the client to the backend directly
- [x] **HTTP-04**: Presenter can show, side by side, that the proxied request keeps the original URL while the redirected request changes it

### SSH Routing

- [x] **SSH-01**: Client can `ssh` to the nginx host on port 22 and land on the active backend
- [x] **SSH-02**: nginx uses the `stream` module to proxy raw TCP on port 22, not an HTTP redirect
- [x] **SSH-03**: The SSH session shows the active backend's identity banner on login

### Cutover

- [x] **CUT-01**: Presenter can switch the active backend from `server-old` to `server-new` by editing the nginx upstream and reloading
- [x] **CUT-02**: Cutover requires no change on the client side — same hostname, same ports, same commands
- [x] **CUT-03**: HTTP requests after the flip land on `server-new`, provable from the response body
- [x] **CUT-04**: SSH sessions opened after the flip land on `server-new`, provable from the login banner
- [x] **CUT-05**: Presenter can flip back to `server-old` to re-run the demo without a full teardown

### Evidence

- [x] **EVID-01**: Presenter can tail nginx access logs live and see which upstream served each request
- [x] **EVID-02**: A status page shows which backend is currently active
- [x] **EVID-03**: The status page shows recent requests and which backend answered them
- [x] **EVID-04**: A verify script issues an HTTP request and an SSH connection and reports which backend answered each
- [x] **EVID-05**: The verify script exits non-zero if the observed backend does not match the expected one

### SSH Host Key Gotcha

- [x] **KEY-01**: Demo can be run in a state where `server-new` has different SSH host keys from `server-old`
- [x] **KEY-02**: After cutover in that state, the client's SSH attempt fails with `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED`
- [x] **KEY-03**: Presenter can apply a documented fix that transfers `server-old`'s host keys to `server-new`
- [x] **KEY-04**: After the fix, SSH through the proxy to `server-new` succeeds with no client-side `known_hosts` edit

### Walkthrough

- [x] **WALK-01**: A written walkthrough documents the full demo narrative in order: show old → flip → show new → SSH gotcha → fix
- [x] **WALK-02**: Each walkthrough step lists the exact command to run and the output the presenter should expect
- [x] **WALK-03**: The walkthrough explains what the audience should conclude at each step

## v2.0 Requirements — Two-Proxy Switch Topology

Current milestone. A front `switch` nginx flips traffic between two static proxies (`proxy-old`, `proxy-new`), enabling pre-flip validation and instant rollback. Same map-flip + reload mechanism as v1, one layer up.

### Switch (the flip surface)

- [x] **SW-01**: A `switch` nginx service is the client's only endpoint, reachable at `app.demo.test` on HTTP 9092 and SSH 22 — unchanged from the client's point of view versus v1 *(HTTP 9092 delivered in Phase 5; the switch's SSH:22 stream listener delivered in Phase 6 / SW-03 — the switch now answers both protocols)*
- [x] **SW-02**: The switch selects between the two proxies via a single one-line map (`default old` → `new`) in `switch/active-proxy.conf` — the only file the presenter edits to cut over
- [x] **SW-03**: The same selector governs both the HTTP 9092 path and the SSH 22 stream path, so one edit flips both protocols
- [x] **SW-04**: Cutover is performed by editing that one line and reloading the switch (`nginx -s reload`) — no client-side change, same mechanism as v1's CUT-01/CUT-02

### Static Proxies

- [x] **PROX-01**: A `proxy-old` service statically forwards HTTP and SSH to `server-old` and is never reconfigured during the demo
- [x] **PROX-02**: A `proxy-new` service statically forwards HTTP and SSH to `server-new` and is never reconfigured during the demo
- [x] **PROX-03**: Each static proxy carries a distinct network alias — `app-old.demo.test` and `app-new.demo.test` — reachable directly on the demo network

### Pre-flip Validation & Rollback

- [x] **VAL-01**: Presenter can reach `app-new.demo.test` over HTTP and land on `server-new` *before* any cutover, while live traffic on `app.demo.test` still lands on `server-old`
- [x] **VAL-02**: Presenter can `ssh app-new.demo.test` and see `server-new`'s banner before cutover, proving the new stack's SSH path is live
- [x] **VAL-03**: After cutover, the presenter can roll back to old by flipping the switch selector back and reloading — no teardown
- [x] **VAL-04**: The two static proxies' configs are provably unchanged across the whole cutover — "the old proxy is never touched" is literally true

### Evidence (switch-sourced)

- [x] **EV2-01**: The access/evidence log the status page reads is the **switch's** log, capturing the client's real `remote_addr` (not a downstream proxy's address)
- [x] **EV2-02**: The answering backend's own `X-Backend` identity header propagates back through the proxy chain to the switch log, so `backend=OLD/NEW` reflects the true backend and is asserted by no proxy tier
- [x] **EV2-03**: The status page shows the current switch selector (which proxy is active) and recent requests with the backend that answered — the v1 EVID-02/03 guarantees, re-sourced from the switch
- [x] **EV2-04**: The verify script asserts over both HTTP and SSH which backend answered through the switch, and can target `app-new.demo.test` directly for pre-flip validation

### Migration Story & Continuity

- [x] **MIG-01**: The whole v2 topology (switch + two proxies + two backends + status) comes up with one `docker compose up`, preserving ENV-01 across the added services
- [x] **MIG-02**: The presenter walkthrough narrates the v2 story: validate the new stack via `app-new.demo.test` → flip the switch → land on new → (host-key gotcha, inherited from v1) → roll back → the old proxy was never touched
- [x] **MIG-03**: The v1 single-proxy demo remains available and unbroken (e.g. via git tag or a preserved compose file), not deleted by v2 work

## Future / Deferred Requirements

Deferred to a later release. Tracked but not in the current roadmap.

### Infrastructure

- **INFRA-01**: Deploy the same topology onto real hosts in any target environment (cloud, on-prem, or hypervisor)
- **INFRA-02**: Provision the migration target on whatever platform the real cutover is moving to, to complete the end-to-end story

### Presentation

- **PRES-01**: Fully automated demo playback script with narration pauses
- **PRES-02**: TLS/HTTPS variant showing certificate handling across the cutover

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Real infrastructure of any environment | Local simulation proves the same routing mechanics without cost or setup friction |
| TLS / HTTPS on port 9092 | Plain HTTP keeps the proxy-vs-redirect distinction visible in curl output and logs |
| SSH ProxyJump / bastion pattern | The demo is specifically about nginx as the TCP intermediary |
| Weighted or gradual traffic shifting | The demo is a single decisive cutover, not a phased migration |
| Production hardening (auth, rate limiting, real certs) | This is a demonstration artifact, not a deployable proxy |
| Fully automated hands-off playback | Presenter controls pacing during the live narrative |
| Vendor-specific naming in the demo itself | Generic `server-old` / `server-new` keeps it reusable for any migration |
| New SSH host-key scope in v2 | The host-key gotcha is inherited backend behaviour (v1 KEY-*); v2 surfaces it in the walkthrough but adds no new key requirement |

## Traceability

Which phases cover which requirements. Updated during roadmap creation.

| Requirement | Phase | Status |
|-------------|-------|--------|
| ENV-01 | Phase 1 | Complete |
| ENV-02 | Phase 1 | Complete |
| ENV-03 | Phase 1 | Complete |
| ENV-04 | Phase 1 | Complete |
| BACK-01 | Phase 1 | Complete |
| BACK-02 | Phase 1 | Complete |
| BACK-03 | Phase 1 | Complete |
| BACK-04 | Phase 3 | Complete |
| BACK-05 | Phase 3 | Complete |
| HTTP-01 | Phase 1 | Complete |
| HTTP-02 | Phase 1 | Complete |
| HTTP-03 | Phase 1 | Complete |
| HTTP-04 | Phase 1 | Complete |
| SSH-01 | Phase 3 | Complete |
| SSH-02 | Phase 3 | Complete |
| SSH-03 | Phase 3 | Complete |
| CUT-01 | Phase 2 | Complete |
| CUT-02 | Phase 2 | Complete |
| CUT-03 | Phase 2 | Complete |
| CUT-04 | Phase 3 | Complete |
| CUT-05 | Phase 2 | Complete |
| EVID-01 | Phase 2 | Complete |
| EVID-02 | Phase 2 | Complete |
| EVID-03 | Phase 2 | Complete |
| EVID-04 | Phase 3 | Complete |
| EVID-05 | Phase 3 | Complete |
| KEY-01 | Phase 4 | Complete |
| KEY-02 | Phase 4 | Complete |
| KEY-03 | Phase 4 | Complete |
| KEY-04 | Phase 4 | Complete |
| WALK-01 | Phase 4 | Complete |
| WALK-02 | Phase 4 | Complete |
| WALK-03 | Phase 4 | Complete |
| SW-01 | Phase 5 (HTTP) / Phase 6 (SSH) | Complete — HTTP re-homed (Phase 5); SSH:22 stream at the switch delivered (Phase 6 / SW-03) |
| SW-02 | Phase 5 | Complete |
| SW-03 | Phase 6 | Complete |
| SW-04 | Phase 5 | Complete |
| PROX-01 | Phase 5 | Complete |
| PROX-02 | Phase 5 | Complete |
| PROX-03 | Phase 5 | Complete |
| VAL-01 | Phase 6 | Complete |
| VAL-02 | Phase 6 | Complete |
| VAL-03 | Phase 7 | Complete |
| VAL-04 | Phase 7 | Complete |
| EV2-01 | Phase 5 | Complete |
| EV2-02 | Phase 5 | Complete |
| EV2-03 | Phase 5 | Complete |
| EV2-04 | Phase 6 | Complete |
| MIG-01 | Phase 5 | Complete |
| MIG-02 | Phase 7 | Complete |
| MIG-03 | Phase 7 | Complete |

**Coverage:**

- v1 requirements: 33 total — mapped to Phases 1–4: 33 ✓ (all Complete)
- v2.0 requirements: 18 total — mapped to Phases 5–7: 18 ✓ (all Pending)
- Combined: 51 total, 51 mapped, 0 unmapped

**By phase:**

| Phase | Milestone | Name | Requirements |
|-------|-----------|------|--------------|
| 1 | v1 | Demo Up, HTTP Lands on OLD | 11 |
| 2 | v1 | The Live HTTP Cutover | 7 |
| 3 | v1 | SSH Through the Stream Proxy | 8 |
| 4 | v1 | Host-Key Gotcha and the Presenter Walkthrough | 7 |
| 5 | v2.0 | The Switch and Two Static Proxies — HTTP Cutover Re-Homed | 10 |
| 6 | v2.0 | The SSH Stream Flip and Pre-Flip Validation | 4 |
| 7 | v2.0 | Instant Rollback, v1 Preservation, and the v2 Walkthrough | 4 |

---
*Requirements defined: 2026-07-21*
*Last updated: 2026-07-22 — mapped v2.0 requirements (SW, PROX, VAL, EV2, MIG) to Phases 5–7 in the roadmap traceability table*

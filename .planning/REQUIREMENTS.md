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
- [ ] **BACK-04**: Each backend's SSH login banner states its own identity (OLD or NEW) and hostname
- [ ] **BACK-05**: Presenter can log into either backend over SSH with a known credential or key

### HTTP Routing

- [x] **HTTP-01**: Client can reach the active backend by connecting to nginx on port 9092 over plain HTTP
- [x] **HTTP-02**: nginx forwards port 9092 traffic transparently — the client's address and port never change
- [ ] **HTTP-03**: A separate nginx port demonstrates the 301/302 redirect approach, returning a `Location` header that sends the client to the backend directly
- [ ] **HTTP-04**: Presenter can show, side by side, that the proxied request keeps the original URL while the redirected request changes it

### SSH Routing

- [ ] **SSH-01**: Client can `ssh` to the nginx host on port 22 and land on the active backend
- [ ] **SSH-02**: nginx uses the `stream` module to proxy raw TCP on port 22, not an HTTP redirect
- [ ] **SSH-03**: The SSH session shows the active backend's identity banner on login

### Cutover

- [ ] **CUT-01**: Presenter can switch the active backend from `server-old` to `server-new` by editing the nginx upstream and reloading
- [ ] **CUT-02**: Cutover requires no change on the client side — same hostname, same ports, same commands
- [ ] **CUT-03**: HTTP requests after the flip land on `server-new`, provable from the response body
- [ ] **CUT-04**: SSH sessions opened after the flip land on `server-new`, provable from the login banner
- [ ] **CUT-05**: Presenter can flip back to `server-old` to re-run the demo without a full teardown

### Evidence

- [ ] **EVID-01**: Presenter can tail nginx access logs live and see which upstream served each request
- [ ] **EVID-02**: A status page shows which backend is currently active
- [ ] **EVID-03**: The status page shows recent requests and which backend answered them
- [ ] **EVID-04**: A verify script issues an HTTP request and an SSH connection and reports which backend answered each
- [ ] **EVID-05**: The verify script exits non-zero if the observed backend does not match the expected one

### SSH Host Key Gotcha

- [ ] **KEY-01**: Demo can be run in a state where `server-new` has different SSH host keys from `server-old`
- [ ] **KEY-02**: After cutover in that state, the client's SSH attempt fails with `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED`
- [ ] **KEY-03**: Presenter can apply a documented fix that transfers `server-old`'s host keys to `server-new`
- [ ] **KEY-04**: After the fix, SSH through the proxy to `server-new` succeeds with no client-side `known_hosts` edit

### Walkthrough

- [ ] **WALK-01**: A written walkthrough documents the full demo narrative in order: show old → flip → show new → SSH gotcha → fix
- [ ] **WALK-02**: Each walkthrough step lists the exact command to run and the output the presenter should expect
- [ ] **WALK-03**: The walkthrough explains what the audience should conclude at each step

## v2 Requirements

Deferred to future release. Tracked but not in current roadmap.

### Infrastructure

- **INFRA-01**: Terraform deployment of the same topology onto real AWS EC2 instances
- **INFRA-02**: Nutanix-side target deployment to complete the real migration story

### Presentation

- **PRES-01**: Fully automated demo playback script with narration pauses
- **PRES-02**: TLS/HTTPS variant showing certificate handling across the cutover

## Out of Scope

Explicitly excluded. Documented to prevent scope creep.

| Feature | Reason |
|---------|--------|
| Real AWS/Nutanix infrastructure | Local simulation proves the same routing mechanics without cost or setup friction |
| TLS / HTTPS on port 9092 | Plain HTTP keeps the proxy-vs-redirect distinction visible in curl output and logs |
| SSH ProxyJump / bastion pattern | The demo is specifically about nginx as the TCP intermediary |
| Weighted or gradual traffic shifting | The demo is a single decisive cutover, not a phased migration |
| Production hardening (auth, rate limiting, real certs) | This is a demonstration artifact, not a deployable proxy |
| Fully automated hands-off playback | Presenter controls pacing during the live narrative |
| Vendor-specific naming in the demo itself | Generic `server-old` / `server-new` keeps it reusable for any migration |

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
| BACK-04 | Phase 3 | Pending |
| BACK-05 | Phase 3 | Pending |
| HTTP-01 | Phase 1 | Complete |
| HTTP-02 | Phase 1 | Complete |
| HTTP-03 | Phase 1 | Pending |
| HTTP-04 | Phase 1 | Pending |
| SSH-01 | Phase 3 | Pending |
| SSH-02 | Phase 3 | Pending |
| SSH-03 | Phase 3 | Pending |
| CUT-01 | Phase 2 | Pending |
| CUT-02 | Phase 2 | Pending |
| CUT-03 | Phase 2 | Pending |
| CUT-04 | Phase 3 | Pending |
| CUT-05 | Phase 2 | Pending |
| EVID-01 | Phase 2 | Pending |
| EVID-02 | Phase 2 | Pending |
| EVID-03 | Phase 2 | Pending |
| EVID-04 | Phase 3 | Pending |
| EVID-05 | Phase 3 | Pending |
| KEY-01 | Phase 4 | Pending |
| KEY-02 | Phase 4 | Pending |
| KEY-03 | Phase 4 | Pending |
| KEY-04 | Phase 4 | Pending |
| WALK-01 | Phase 4 | Pending |
| WALK-02 | Phase 4 | Pending |
| WALK-03 | Phase 4 | Pending |

**Coverage:**

- v1 requirements: 33 total
- Mapped to phases: 33 ✓
- Unmapped: 0

**By phase:**

| Phase | Name | Requirements |
|-------|------|--------------|
| 1 | Demo Up, HTTP Lands on OLD | 11 |
| 2 | The Live HTTP Cutover | 7 |
| 3 | SSH Through the Stream Proxy | 8 |
| 4 | Host-Key Gotcha and the Presenter Walkthrough | 7 |

---
*Requirements defined: 2026-07-21*
*Last updated: 2026-07-21 after roadmap creation*

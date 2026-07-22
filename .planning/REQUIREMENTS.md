# Requirements: Server Migration Redirect Demo

**Core Value:** A live, on-stage flip of the nginx upstream from old to new where the client keeps hitting the same hostname and port, and unmistakably lands on the new server.

## Shipped Milestones

- **v1.0 — Core migration demo** (33 requirements) — full validated set preserved in `.planning/milestones/v2.0-REQUIREMENTS.md`.
- **v2.0 — Two-Proxy Switch Topology** (18 requirements: SW, PROX, VAL, EV2, MIG) — SHIPPED 2026-07-22, tag `v2.0`. Full archive: `.planning/milestones/v2.0-ROADMAP.md` and `.planning/milestones/v2.0-REQUIREMENTS.md`.

The next milestone's requirements will be defined by `/gsd-new-milestone`.

## Deferred / Future Requirements

Tracked but not yet scheduled into a milestone.

### Infrastructure

- **INFRA-01**: Deploy the same topology onto real hosts in any target environment (cloud, on-prem, or hypervisor)
- **INFRA-02**: Provision the migration target on whatever platform the real cutover is moving to, to complete the end-to-end story

### Presentation

- **PRES-01**: Fully automated demo playback script with narration pauses
- **PRES-02**: TLS/HTTPS variant showing certificate handling across the cutover

## Out of Scope

Explicitly excluded (carried across milestones):

| Feature | Reason |
|---------|--------|
| Real infrastructure of any environment | Local simulation proves the same routing mechanics without cost or setup friction |
| TLS / HTTPS on port 9092 | Plain HTTP keeps the proxy-vs-redirect distinction visible in curl output and logs |
| SSH ProxyJump / bastion pattern | The demo is specifically about nginx as the TCP intermediary |
| Weighted or gradual traffic shifting | The demo is a single decisive cutover, not a phased migration |
| Production hardening (auth, rate limiting, real certs) | This is a demonstration artifact, not a deployable proxy |
| Fully automated hands-off playback | Presenter controls pacing during the live narrative |
| Vendor-specific naming in the demo itself | Generic `server-old` / `server-new` keeps it reusable for any migration |
| A second concurrent `compose.v1.yaml` for v1 | v1 is preserved at git tag `v1.0` (self-contained); a live v1 compose would collide with v2 on ports 9092/9093 |

---
*Requirements defined: 2026-07-21 · v2.0 archived: 2026-07-22*

# Server Migration Redirect Demo

## What This Is

A self-contained Docker Compose demo that simulates migrating a hostname from one server to another using nginx. It reverse-proxies HTTP on port 9092 and stream-proxies SSH on port 22, then performs a live cutover from `server-old` to `server-new` — with the client never changing what it connects to. Built as a migration proof-of-concept to run on a laptop.

## Core Value

A live, on-stage flip of the nginx upstream from old to new where the client keeps hitting the same hostname and port, and unmistakably lands on the new server.

## Current Milestone: v2.0 Two-Proxy Switch Topology

**Goal:** Replace v1's single flip-in-place proxy with a blue-green proxy tier — a front "switch" nginx that flips traffic between two static proxies, enabling pre-flip validation of the new stack and instant rollback.

**Target features:**
- A `switch` nginx: the client's only endpoint (`app.demo.test`), flipping a one-line map (`default old`→`new`) across HTTP :9092 and SSH :22 stream — the sole flip surface (`switch/active-proxy.conf`), replacing v1's `proxy/active-backend.conf`.
- Two **static** proxies — `proxy-old`→server-old (`app-old.demo.test`) and `proxy-new`→server-new (`app-new.demo.test`) — each single-upstream and never reconfigured during the demo.
- Evidence log sourced from the **switch** (it sees the client's real `remote_addr`; the backend's own `X-Backend` header still flows back through the chain so `backend=NEW` stays honest); status service re-pointed to the switch's log.
- Pre-flip validation of the new stack: `curl`/`ssh app-new.demo.test` proves it live *before* the cutover, and rollback is instant by flipping the switch back — making "the old proxy is never touched" literally true.

**Key context:** The map-flip + `nginx -s reload` *mechanism* is unchanged from v1, so the on-stage flip action is identical — what changes is the architecture around it. Tradeoff: one extra proxy hop each way. The v1 single-proxy demo is preserved intact.

**Status: v2.0 COMPLETE (2026-07-22)** — all 3 phases shipped, all 18 v2.0 requirements verified (`make test` 257/0 + a human walkthrough cold-read). Phase 5: the switch + two static proxies, HTTP:9092 re-homed, evidence re-sourced from the switch. Phase 6: the switch's SSH:22 stream block so **one `switch/active-proxy.conf` edit flips both protocols** (D-39 shared include), plus pre-flip validation (`curl`/`ssh app-new.demo.test` → NEW while `app.demo.test` stays OLD). Phase 7: instant rollback (flip back, no teardown), "the old proxy is never touched" as a `shasum -a 256` proof, v1 preserved at tag `v1.0`, and the presenter walkthrough rewritten to the 11-beat v2 narrative. The blue-green proxy tier is done: a live front-door flip between two static proxies with pre-flip validation and instant rollback.

## Requirements

### Validated

- ✓ nginx reverse-proxies HTTP on port 9092 to a backend server, transparently (client sees no address change) — Phase 1
- ✓ nginx also demonstrates the HTTP 301/302 redirect approach side by side, so the difference from proxying is visible — Phase 1
- ✓ Two backend containers exist: `server-old` and `server-new`, each running HTTP and SSH — Phase 1 (SSH present and reachable in-container; routed in Phase 3)
- ✓ Each backend self-identifies as OLD or NEW in its HTTP response body — Phase 1 (SSH login banner lands in Phase 3)
- ✓ Whole demo comes up with one command (`docker compose up`) — Phase 1
- ✓ Cutover is performed live by editing the nginx upstream and reloading — no client-side change required — Phase 2
- ✓ nginx access logs are viewable live, showing which upstream served each request — Phase 2
- ✓ A status page shows current routing state and recent requests — Phase 2
- ✓ nginx `stream` module proxies raw TCP on port 22 to a backend SSH server — Phase 3
- ✓ Each backend self-identifies as OLD or NEW in its SSH login banner — Phase 3
- ✓ An automated verify script curls HTTP and connects over SSH, asserting which backend answered — Phase 3
- ✓ The SSH host-key mismatch failure (`REMOTE HOST IDENTIFICATION HAS CHANGED`) is staged deliberately, then fixed by transferring host keys to the new server — Phase 4
- ✓ A written step-by-step walkthrough documents the live narrative: show old → flip → show new → SSH gotcha → fix — Phase 4

### Active

(None — all v1 requirements validated)

### Out of Scope

- Real infrastructure of any kind (cloud, on-prem, hypervisor, bare metal) — this is a local simulation; provisioning real hosts would add cost and setup friction without changing what the demo proves
- TLS / HTTPS on port 9092 — plain HTTP keeps the proxy-vs-redirect distinction visible in logs and curl output
- SSH ProxyJump / bastion patterns — the demo is specifically about nginx as the TCP intermediary
- Weighted or gradual traffic shifting — the demo is a single decisive cutover, not a phased migration
- Production hardening (auth, rate limiting, real certs) — this is a demonstration artifact, not a deployable proxy
- Fully automated hands-off demo playback — the walkthrough is run manually so the presenter controls pacing

## Context

- The demo is a generic, environment-agnostic host migration: it proves that a hostname can be cut over from one server to another without clients noticing, independent of where the servers live — cloud-to-cloud, on-prem-to-cloud, a data-centre move, a VM rehost, or one container to another. It uses generic `server-old` / `server-new` naming so it is reusable for any such migration and tied to no vendor or platform.
- The SSH side is genuinely a TCP stream proxy, not an HTTP redirect — nginx's `stream` module handles this and needs to be present in the nginx image used.
- The SSH host-key mismatch is the migration surprise most likely to bite in real life, so it is deliberately part of the narrative rather than engineered away.
- Greenfield: no existing code in this directory.

## Constraints

- **Tech stack**: nginx (with `stream` module) + Docker Compose — the demo is specifically about nginx behaviour, and Compose keeps it laptop-local and disposable
- **Ports**: HTTP on 9092, SSH on 22 — 9092 chosen explicitly by the user; SSH must be 22 to make the "no client change" point honestly
- **Environment**: must run entirely locally with no cloud account or cost
- **Startup**: one command to bring the whole demo up — a demo that needs setup steps isn't a demo

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Docker Compose locally instead of provisioning real infrastructure | Fast, disposable, zero cost; proves the routing mechanics identically | — Pending |
| nginx `stream` TCP proxy for SSH (not DNS cutover or ProxyJump) | SSH can't be HTTP-redirected; stream proxy is the mechanism that actually keeps the client pointed at one hostname | — Pending |
| Show reverse proxy and 301 redirect side by side | The difference between the two is the conceptual crux for the audience | — Pending |
| Live upstream flip + reload as the cutover mechanism | It's the money shot — visible, decisive, and client-transparent | — Pending |
| Generic `server-old` / `server-new` naming | Keeps the demo reusable for any migration and tied to no vendor or environment | — Pending |
| Stage the SSH host-key mismatch rather than pre-solve it | It's the #1 real-world migration surprise; showing the failure then the fix is more valuable than a clean run | — Pending |
| Four independent forms of evidence (banner, logs, status page, verify script) | Migration claims need proof the audience can see from more than one angle | — Pending |
| Demo hostname is `app.demo.test`, not `app.demo.local` (D-22, Phase 1) | `.local` is RFC 6762-reserved for mDNS; macOS routes it to mDNSResponder, which under Tailscale's DNS takeover is unreachable — every browser/curl lookup stalled 5s despite a correct `/etc/hosts`. `.test` is RFC 6761-reserved, never hits real DNS. Measured 5.03s → 0.05s | ✓ Good |
| Tailscale MagicDNS rejected as the demo's name source | Issues machine names not service names (undercuts the "hostname never changed" claim), does not resolve inside the Docker bridge network, and would require unbinding from loopback — exposing the demo and a demo-credentialled sshd to the whole tailnet | ✓ Good |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-07-22 — milestone v2.0 COMPLETE (two-proxy switch topology: Phases 5–7 shipped and verified)*

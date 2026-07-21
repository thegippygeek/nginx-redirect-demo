# Server Migration Redirect Demo

## What This Is

A self-contained Docker Compose demo that simulates migrating a hostname from one server to another using nginx. It reverse-proxies HTTP on port 9092 and stream-proxies SSH on port 22, then performs a live cutover from `server-old` to `server-new` — with the client never changing what it connects to. Built as a migration proof-of-concept to run on a laptop.

## Core Value

A live, on-stage flip of the nginx upstream from old to new where the client keeps hitting the same hostname and port, and unmistakably lands on the new server.

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

### Active

- [ ] nginx `stream` module proxies raw TCP on port 22 to a backend SSH server
- [ ] Each backend self-identifies as OLD or NEW in its SSH login banner
- [ ] An automated verify script curls HTTP and connects over SSH, asserting which backend answered
- [ ] The SSH host-key mismatch failure (`REMOTE HOST IDENTIFICATION HAS CHANGED`) is staged deliberately, then fixed by transferring host keys to the new server
- [ ] A written step-by-step walkthrough script documents the live narrative: show old → flip → show new → SSH gotcha → fix

### Out of Scope

- Real AWS or Nutanix infrastructure — this is a local simulation; Terraform/EC2 would add cost and setup friction without changing what the demo proves
- TLS / HTTPS on port 9092 — plain HTTP keeps the proxy-vs-redirect distinction visible in logs and curl output
- SSH ProxyJump / bastion patterns — the demo is specifically about nginx as the TCP intermediary
- Weighted or gradual traffic shifting — the demo is a single decisive cutover, not a phased migration
- Production hardening (auth, rate limiting, real certs) — this is a demonstration artifact, not a deployable proxy
- Fully automated hands-off demo playback — the walkthrough is run manually so the presenter controls pacing

## Context

- Repo is named `aws-nutainx-redirect`, reflecting the real-world scenario that motivated it: proving an AWS → Nutanix migration can cut over without clients noticing. The demo itself uses generic `server-old` / `server-new` naming so it is reusable for any migration.
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
| Docker Compose locally instead of AWS/Terraform | Fast, disposable, zero cost; proves the routing mechanics identically | — Pending |
| nginx `stream` TCP proxy for SSH (not DNS cutover or ProxyJump) | SSH can't be HTTP-redirected; stream proxy is the mechanism that actually keeps the client pointed at one hostname | — Pending |
| Show reverse proxy and 301 redirect side by side | The difference between the two is the conceptual crux for the audience | — Pending |
| Live upstream flip + reload as the cutover mechanism | It's the money shot — visible, decisive, and client-transparent | — Pending |
| Generic `server-old` / `server-new` naming | Keeps the demo reusable beyond the AWS→Nutanix case | — Pending |
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
*Last updated: 2026-07-21 after Phase 2*

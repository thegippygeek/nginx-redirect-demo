# Milestones

Historical record of shipped versions. Full per-milestone detail lives in `.planning/milestones/`.

| Version | Name | Shipped | Phases | Plans | Tag | Archive |
|---------|------|---------|--------|-------|-----|---------|
| v1.0 | Core Migration Demo | 2026-07-22 | 1–4 | 14 | `v1.0` | (in-tree; requirements in v2.0-REQUIREMENTS.md snapshot) |
| v2.0 | Two-Proxy Switch Topology | 2026-07-22 | 5–7 | 7 | `v2.0` | [v2.0-ROADMAP.md](milestones/v2.0-ROADMAP.md) · [v2.0-REQUIREMENTS.md](milestones/v2.0-REQUIREMENTS.md) |

## v2.0 — Two-Proxy Switch Topology

Replaced v1's single flip-in-place proxy with a blue-green proxy tier: a front `switch` nginx flips one shared map (`old`→`new`) + reload to route between two static proxies across **both** HTTP:9092 and SSH:22 — client-transparent. Added pre-flip validation via `app-new.demo.test` (prove the new stack live before cutover), instant rollback (flip back, no teardown), "the old proxy is never touched" as a `shasum -a 256` proof, v1 preserved at tag `v1.0`, and an 11-beat v2 presenter walkthrough. 18/18 requirements verified; `make test` 257/0 + human cold-read.

## v1.0 — Core Migration Demo

The original single-proxy demo: nginx reverse-proxies HTTP:9092 and stream-proxies SSH:22 to a backend, with a live cutover from `server-old` to `server-new` by editing the upstream and reloading — the client never changes what it connects to. Included the 301-redirect contrast, live logs + a status page, an automated verify script, the SSH host-key gotcha staged-and-fixed, and a presenter walkthrough. Preserved at git tag `v1.0`.

---
quick_id: 260723-aq1
slug: architecture-doc
type: quick
created: 2026-07-23
---

# Quick Task: docs/architecture.md

**Task:** Create `docs/architecture.md` — an architecture document for the v2.0 two-proxy switch topology.

**Contents:**
- Overview of the blue-green proxy tier
- The Mermaid flowchart diagram (from `scratchpad/architecture-v2.mmd`)
- Component descriptions: switch (client's only endpoint + flip surface + evidence writer), the two static proxies (never reconfigured, `app-old`/`app-new.demo.test` aliases), the OLD/NEW backends, the status page (`:9094`, reads switch log `:ro`)
- The flip mechanism: one edit in `switch/active-proxy.conf` + `nginx -s reload`; shared map across http + stream so one edit flips both HTTP:9092 and SSH:22 (D-39)
- Request flows: normal HTTP/SSH through switch→proxy→server; pre-flip validation direct to `app-new.demo.test`; instant rollback; evidence integrity (backend's own `X-Backend` rides back untouched — no proxy can forge identity)
- Key properties: client-transparent, static proxies never touched (shasum-verified), loopback-bound ports, no host :22, no Docker socket, v1 preserved at tag `v1.0`

**Acceptance:** `docs/architecture.md` exists, renders the Mermaid diagram, matches the project's doc voice, and is factually consistent with the shipped v2.0 code.

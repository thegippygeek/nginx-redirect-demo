---
quick_id: 260723-aq1
slug: architecture-doc
status: complete
completed: 2026-07-23
---

# Summary: docs/architecture.md

Created `docs/architecture.md` — the architecture reference for the v2.0 two-proxy switch topology.

**Delivered:**
- Overview of the blue-green proxy tier (what the extra layer buys over v1)
- The Mermaid flowchart diagram (client → switch → static proxies → backends, plus evidence + pre-flip edges), with class-based colouring
- Component sections: switch (endpoint + flip surface + evidence writer), the two static proxies (alias table, never reconfigured, no identity header), the OLD/NEW backends, the status page
- The flip mechanism (one-line `switch/active-proxy.conf` map + `nginx -s reload`; shared map across http + stream = one edit flips both protocols, D-39)
- Request flows: normal (client-transparent), pre-flip validation (direct to `app-new.demo.test`), rollback, and evidence integrity (backend's own `X-Backend` rides back untouched)
- Key properties (client-transparent, static proxies untouched/shasum-verified, loopback-bound, no host :22, no Docker socket, v1 at tag `v1.0`) and a "where things live" file map

**Voice:** matched README.md — descriptive prose, bold emphasis, points readers at WALKTHROUGH.md for the runnable script.

**Verification:** factually cross-checked against the shipped v2.0 code (switch/static-proxy configs, flip.sh, verify.sh, status.py, compose.yaml). Mermaid source is the same rendered cleanly earlier in the session.

**Not committed to `main` remote** — left on the local branch; the user gates every `main` push.

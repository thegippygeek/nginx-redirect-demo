---
quick_id: 260723-b48
slug: readme-diagram
status: complete
completed: 2026-07-23
---

# Summary: README.md architecture diagram

Added a new "## Architecture" section to README.md between the intro and "## One-time setup":
- A one-line description of the blue-green two-proxy switch topology
- The v2.0 Mermaid flowchart (identical block to docs/architecture.md — client → switch → two static proxies → OLD/NEW backends, plus flip surface, evidence→status, and pre-flip validation edges, with classDef colouring)
- A legend line + a pointer to docs/architecture.md for the full reference

Diagram not duplicated in prose — just the block + link. Renders natively on GitHub.

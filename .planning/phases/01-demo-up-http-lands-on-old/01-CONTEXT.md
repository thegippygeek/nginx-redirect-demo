# Phase 1: Demo Up, HTTP Lands on OLD - Context

**Gathered:** 2026-07-21
**Status:** Ready for planning

<domain>
## Phase Boundary

Bring the whole demo rig up with one command and prove HTTP through nginx on port 9092 lands on `server-old` with the client's URL unchanged — plus show the 301 redirect approach alongside it so the audience sees the difference.

Requirements: ENV-01, ENV-02, ENV-03, ENV-04, BACK-01, BACK-02, BACK-03, HTTP-01, HTTP-02, HTTP-03, HTTP-04.

**Not this phase:** the live cutover (Phase 2), SSH routing through the `stream` module (Phase 3), the host-key gotcha and walkthrough doc (Phase 4).

</domain>

<decisions>
## Implementation Decisions

### Client-facing story

- **D-01:** The demo uses a real-looking hostname, `app.demo.local`, not `localhost`. The "hostname stayed the same" claim is the point of the demo and `localhost` undermines it.
- **D-02:** A `client` container is part of the compose stack. It resolves `app.demo.local` via Docker's own DNS / `extra_hosts` and is the source of `curl` (and, in Phase 3, `ssh`) commands. Presenter runs e.g. `docker compose exec client curl http://app.demo.local:9092`.
- **D-03:** The presenter's host machine also gets an `/etc/hosts` entry mapping `app.demo.local` → `127.0.0.1`. This is a documented one-time setup step. Rationale: the browser runs on the host and cannot see Docker's internal DNS — without this the browser and the client container would be using two different names on stage, which muddies the story.
- **D-04:** Both clients therefore use the identical hostname. This is deliberate and load-bearing for the narrative.

### Network exposure

- **D-05:** `server-old` and `server-new` are each exposed directly on their own host ports, in addition to being reachable through the proxy. Two reasons: the presenter can establish "here are the two boxes" before introducing the proxy, and the 301 redirect needs a real, reachable `Location` target.
- **D-06:** Exact port numbers for direct access and for the redirect listener are planner's discretion, with two constraints: 9092 is the proxied HTTP port (locked by the user), and the numbers should be adjacent/memorable enough to narrate.

### Redirect contrast (HTTP-03/04)

- **D-07:** The proxy-vs-redirect contrast is demonstrated **in a browser**, not with `curl -v`. Seeing the URL bar stay put on the proxied port and visibly change on the redirect port is the most visceral proof for the audience.
- **D-08:** The redirect is served from a separate nginx port (not a path on 9092), so "port 9092 is the migration endpoint" stays a clean framing.
- **D-09:** `curl -v` remains available as the technical backup view, but the browser is the primary demo path.

### Backend identity signal (BACK-03)

- **D-10:** Each backend serves an HTML page with a large, colour-coded **OLD** or **NEW** banner showing its hostname — readable across a room.
- **D-11:** Each backend also sets an `X-Backend: server-old` / `server-new` response header, so scripts and log inspection have something machine-greppable. Both signals, not one or the other.

### nginx config shape

- **D-12:** The upstream target lives in a small dedicated include file (e.g. `active-backend.conf`), `include`d by the main nginx config. The Phase 2 flip must be a one-line edit in one small file that the audience can see in full on screen.
- **D-13:** The config is structured so the same include can later be referenced from the `stream` block in Phase 3, without restructuring.
- **D-14:** Changes are picked up with `docker compose exec proxy nginx -s reload` — a graceful reload, not a container restart. This is what you'd do in production and it implicitly makes the zero-downtime point.
- **D-15:** Phase 1 ships **no `stream` block at all**. ENV-04 is satisfied by proving the module is compiled in (`nginx -V`), which drives the base image choice. Phase 3 adds the stream config from scratch.

### Backend container makeup

- **D-16:** One Dockerfile, built once, instantiated twice as two compose services. Identity comes from a `BACKEND_ID=OLD|NEW` (or equivalent) env var that drives the page banner, its colour, the `X-Backend` header, and later the SSH banner. Rationale: provably identical boxes differing only in identity strengthens "the only thing that changed is which server answered."
- **D-17:** Web server and sshd run **in the same container** per backend — one container = one "server". This matches the mental model the demo depends on and puts the Phase 4 host-key story naturally on the same box. Needs a small init/supervisor to run two processes; that trade-off is accepted.
- **D-18:** sshd is built into the image **now**, in Phase 1, even though SSH isn't routed or demoed until Phase 3. BACK-01/02 as written say the backends accept SSH, and building once avoids an image rebuild mid-project. Phase 1 simply doesn't route or demo it.

### Presenter command surface

- **D-19:** A **Makefile** is the presenter's interface: `make up`, `make status`, `make reset`, and (from Phase 2) `make flip`. Short commands read well on stage and are hard to fumble live.
- **D-20:** The Makefile is convenience, not a dependency. Raw `docker compose up` must work standalone — ENV-01 is satisfied literally, and nothing essential is hidden behind `make`.
- **D-21:** `make reset` (ENV-02) does a **full teardown and rebuild** — `docker compose down -v` plus restoring the active-backend include to point at OLD. Guarantees an identical clean starting state on every run. The faster config-only flip-back is Phase 2's concern (CUT-05), not this.

### Claude's Discretion

- Base image choice for the proxy container, subject to the hard constraint that `nginx -V` shows the `stream` module compiled in.
- Base image and process supervisor for the backend containers (D-17 requires two processes in one container; the mechanism is open).
- Exact port numbers for direct backend access and the redirect listener (D-06).
- nginx log format — must make the serving upstream visible, since Phase 2's EVID-01 depends on it. Getting this right in Phase 1 avoids rework.
- Health check definitions and how "all came up healthy" is verified.
- File and directory layout of the repo.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Project scope and requirements

- `.planning/PROJECT.md` — core value, constraints, out-of-scope boundaries, key decisions from init
- `.planning/REQUIREMENTS.md` — full v1 requirement text for ENV-01..04, BACK-01..03, HTTP-01..04
- `.planning/ROADMAP.md` §"Phase 1: Demo Up, HTTP Lands on OLD" — goal and the five success criteria this phase is verified against

### Downstream phases this phase must not block

- `.planning/ROADMAP.md` §"Phase 2: The Live HTTP Cutover" — D-12 and the log-format discretion item exist to serve this phase
- `.planning/ROADMAP.md` §"Phase 3: SSH Through the Stream Proxy" — D-13, D-15, D-17, D-18 exist to serve this phase

No external specs or ADRs — this is a greenfield repo and the requirements are fully captured above.

</canonical_refs>

<code_context>
## Existing Code Insights

Greenfield. The repository contains only `.planning/` and `.claude/CLAUDE.md` — no source files, no Dockerfiles, no configs.

### Reusable Assets

None — everything in this phase is built from scratch.

### Established Patterns

None yet. Phase 1 establishes the conventions (repo layout, Makefile target naming, env-var-driven backend identity) that Phases 2–4 will follow.

### Integration Points

None — this phase creates the whole rig.

</code_context>

<specifics>
## Specific Ideas

- Hostname is `app.demo.local`. Chosen so it reads like a real service name rather than a test artifact.
- The OLD/NEW page banner should be big and colour-coded — the presenter should be able to stand back from the screen and have the audience call out which server answered.
- `make flip` (Phase 2) is intended to be the memorable money-shot command; Phase 1 should name its targets consistently so that lands well.
- Direct backend access exists so the presenter can say "here are two separate boxes" *before* nginx enters the story.

</specifics>

<deferred>
## Deferred Ideas

- **Config-only fast flip-back** (containers keep running, just repoint the include and reload) — genuinely useful for back-to-back demo takes, but it is CUT-05 and belongs in Phase 2. Phase 1 only provides the full teardown reset.
- **`make flip` target** — Phase 2. Phase 1 should not implement the cutover, only structure the config so the flip is trivial.
- **`stream` block for SSH** — Phase 3, per D-15.
- **Shared SSH host keys / host-key mismatch staging** — Phase 4. Phase 1 installs sshd but takes no position on host-key generation strategy beyond not actively preventing Phase 4's approach.

</deferred>

<open_concerns>
## Open Concerns Carried From STATE.md

- **Host port 22 collision.** The presenter's laptop may already have sshd bound to port 22, which would break the proxy's port mapping. This is primarily a Phase 3 problem, but Phase 1's compose file establishes the port-mapping conventions. Phase 1 should not bind port 22 (no stream block per D-15) but should leave the mapping strategy unresolved rather than baking in an assumption Phase 3 has to undo. Phase 3 must settle it in a way that keeps the "no client change" claim honest — note that D-02's client container sidesteps the host-port problem entirely for SSH, since it connects over the Docker network.

</open_concerns>

---

*Phase: 1-Demo Up, HTTP Lands on OLD*
*Context gathered: 2026-07-21*

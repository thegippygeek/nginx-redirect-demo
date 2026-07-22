# Phase 7: Instant Rollback, v1 Preservation, and the v2 Walkthrough - Research

**Researched:** 2026-07-22
**Domain:** Docker Compose / nginx demo close-out — behavioural assertion, checksum integrity proof, git-tag preservation, presenter-doc rewrite. Low new-code, high correctness-of-narrative-and-assertions.
**Confidence:** HIGH — every claim below is grounded in files read this session (codebase-verified), not external docs. No new packages, no network research required.

## Summary

Phase 7 is a **brownfield close-out**. The full v2 topology already runs and works: the `switch` flips both HTTP:9092 and SSH:22 through a single one-line selector (`switch/active-proxy.conf`), routing through two static single-upstream proxies (`proxy-old`, `proxy-new`) to the two backends. Phases 5–6 delivered the cutover *and* pre-flip validation; `flip.sh` already flips **both directions** (old↔new) over both protocols via one `nginx -s reload` on the switch. **Nothing in this phase needs a new routing mechanism.** All four requirements are either *demonstrate-and-assert an already-working behaviour* (VAL-03, VAL-04) or *documentation* (MIG-02, MIG-03).

The work is: (1) **VAL-03** — assert rollback (`flip.sh old` after a cutover) returns *both* protocols to OLD with **no container teardown** (StartedAt unchanged); (2) **VAL-04** — a `shasum -a 256` triple-equality proof that `proxy-old/nginx.conf` + `proxy-new/nginx.conf` are byte-identical before flip == after flip-to-new == after rollback-to-old, strengthened by proving those two containers were never restarted *or reloaded*; (3) **MIG-03** — v1 preservation via the already-existing, self-contained `git tag v1.0` (`git checkout v1.0 && make up`), asserted non-destructively; (4) **MIG-02** — rewrite `WALKTHROUGH.md` for the v2 narrative, updating `section_walkthrough` **in lockstep** because it hard-codes the v1 8-beat narrative as an executable contract.

**Primary recommendation:** Add one combined destructive smoke section (`section_rollback` covering VAL-03 + VAL-04 in a single flip cycle), add a small non-destructive `section_preserve` (MIG-03, git-tag assertions only), rewrite `WALKTHROUGH.md` and update `section_walkthrough`'s hard-coded narrative/step/target contract to match — and add any new presenter make target (e.g. a checksum "proxies-untouched" target and the rollback command) to `.PHONY` so the walkthrough lint stays green. Use `shasum -a 256` (portable on macOS + Linux; `sha256sum` is absent on stock macOS). Rely on `git tag v1.0` as the canonical v1 preserved form — do **not** add a `compose.v1.yaml`/`make up-v1` (port collision with v2, extra maintenance surface).

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Rollback (flip back to OLD) | `switch` (the flip surface) | `flip.sh` | The switch owns the single selector governing both protocols; `flip.sh old` reloads it. No proxy/backend involvement. [VERIFIED: flip.sh, compose.yaml] |
| "Old proxy never touched" checksum | Test harness (`smoke.sh`) | host filesystem | The static proxy configs are host bind-mounts (`:ro`) never written by any script; the assertion is a host-side `shasum` over `proxy-old/nginx.conf` + `proxy-new/nginx.conf`. [VERIFIED: compose.yaml, grep of scripts/] |
| "No teardown" proof | Test harness | Docker engine (`docker inspect .State.StartedAt`) | Container restart is observable via StartedAt; reload is observable via nginx worker PIDs. Existing CUT-05 idiom. [VERIFIED: smoke.sh:454-463] |
| v1 preservation | git (tag `v1.0`) | — | The tag points at a fully self-contained tree (single `proxy` service + own Makefile). No runtime tier owns this. [VERIFIED: git ls-tree v1.0, git show v1.0:Makefile] |
| v2 narrative | `WALKTHROUGH.md` (doc) | `section_walkthrough` (executable contract) | The doc is the deliverable; the smoke section is the anti-rot guard that must move with it. [VERIFIED: smoke.sh:1792-2036] |

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| VAL-03 | After cutover, roll back to old by flipping the switch selector back and reloading — no teardown | `flip.sh old` already exists and flips both protocols via one switch reload (SW-03). Needs a smoke assertion that BOTH protocols return to OLD and container StartedAt is unchanged. No new mechanism. [VERIFIED: flip.sh, smoke.sh:451-463] |
| VAL-04 | The two static proxies' configs provably unchanged across the whole cutover | Static proxy configs are `:ro` bind-mounts never written by any script (grep confirms). Add `shasum -a 256` triple-equality (before/after-flip/after-rollback) + StartedAt + worker-PID unchanged. [VERIFIED: compose.yaml:119-161, grep scripts/] |
| MIG-02 | Rewrite the presenter walkthrough for the v2 narrative | `WALKTHROUGH.md` read in full; `section_walkthrough` hard-codes the v1 8-beat contract and MUST be updated in lockstep. New v2 beats map to existing commands. [VERIFIED: WALKTHROUGH.md, smoke.sh:1821-2036] |
| MIG-03 | v1 single-proxy demo remains available and unbroken | `git tag v1.0` is self-contained (single `proxy` service, own compose + Makefile + `proxy/` dir). `git checkout v1.0 && make up` works. [VERIFIED: git ls-tree v1.0, git show v1.0:compose.yaml/:Makefile] |

## Project Constraints (from CLAUDE.md)

Directives extracted from `./.claude/CLAUDE.md` — the planner must not contradict these:

- **Tech stack is fixed:** nginx (with `stream` module) + Docker Compose only. No new runtimes or services beyond what ships. [CITED: .claude/CLAUDE.md]
- **Ports:** HTTP 9092, SSH 22. 9092 is a hard user choice; SSH must be 22 to keep "no client change" honest. [CITED: .claude/CLAUDE.md]
- **Local-only, zero cost:** no cloud account/credential. [CITED: .claude/CLAUDE.md]
- **One-command startup:** `docker compose up` / `make up` brings the whole rig up; a demo that needs setup steps isn't a demo. **A `compose.v1.yaml` that needed its own bring-up ceremony would erode this — another reason to prefer the git tag for MIG-03.** [CITED: .claude/CLAUDE.md]
- **GSD workflow enforcement:** file edits go through a GSD command (this is a planned phase → `/gsd-execute-phase`). [CITED: .claude/CLAUDE.md]
- **Global:** use "participant" not "patient" (N/A to this phase — no such text). [CITED: ~/.claude/CLAUDE.md]

## Locked Decisions To Respect (from PROJECT.md / STATE.md decision log)

These are settled and must not be re-litigated or contradicted by Phase 7 work:

| Decision | Impact on Phase 7 |
|----------|-------------------|
| **D-14** graceful reload, never container restart | Rollback = reload only. The "no teardown" proof is StartedAt-unchanged. |
| **D-15** no host port 22 binding | Any new walkthrough SSH beat runs from the `client` container, never `-p 22`. |
| **D-36** `flip.sh old` truncates the evidence log and issues NO confirming request | The rollback direction is *also the between-takes reset*: it clears counters. This affects the walkthrough rollback beat narration (see Pitfall 3). |
| **D-52** two named SSH connection modes (test vs presenter) | New SSH assertions use TEST mode (`StrictHostKeyChecking=no`, `UserKnownHostsFile=/dev/null`); the walkthrough gotcha beat uses PRESENTER mode (`make ssh`). Never mix. |
| **D-55 / D-54** fixed walkthrough narrative order and Run/Expect/Say block order | `section_walkthrough` enforces these literally. A v2 rewrite must update the contract, not just the doc. |
| static proxies **never reconfigured** (PROX-01/02) | VAL-04 depends on this being literally true — confirmed no script writes those files. |
| **D-29** no Docker socket mounted anywhere | Do not introduce one for any StartedAt/PID inspection — use host-side `docker inspect`. |

## Standard Stack

No new packages. Everything this phase touches already ships and is verified in-tree.

### Core
| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Docker Compose v2 | (host) | The rig; `docker inspect`/`docker compose exec` for StartedAt & PID probes | Already the whole project's substrate. `docker inspect -f '{{.State.StartedAt}}'` is the existing CUT-05 no-restart idiom [VERIFIED: smoke.sh:454] |
| nginx | 1.30-alpine | switch + two static proxies | Pinned across all three tiers [VERIFIED: compose.yaml:67,120,145] |
| POSIX `sh` | — | `smoke.sh` assertions, `flip.sh` | Suite is deliberately POSIX, not bash [VERIFIED: smoke.sh:1] |
| `shasum -a 256` | /usr/bin/shasum (Perl) | VAL-04 sha256 config checksum | **Portable on macOS AND Linux.** House idiom already uses bare `shasum` (SHA-1) at smoke.sh:478 — upgrade to `-a 256` per criterion wording [VERIFIED: `command -v shasum`; criterion 2 says "sha256"] |
| git | (host) | MIG-03 v1 preservation via `tag v1.0` | Tag already exists and is self-contained [VERIFIED: git tag; git ls-tree v1.0] |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `shasum -a 256` | `sha256sum` | `sha256sum` is **absent on stock macOS** (present here only via coreutils). Presenter laptops are darwin — `shasum -a 256` is the safe choice. [VERIFIED: this session is darwin; project runs on a laptop] |
| git tag v1.0 for MIG-03 | `compose.v1.yaml` + `make up-v1` on main | The kept-compose route **collides on 9092/9093** with v2 (both publish those ports — can't co-run) and adds a second maintained topology that can rot. The tag is zero-maintenance and already self-contained. **Recommend the tag.** |
| Combined `section_rollback` (VAL-03+04) | Extend the already-1000-line `section_cutover` | `section_cutover` is huge and HTTP-only; VAL-03 needs SSH (test-mode helpers). A dedicated section keeps concerns legible and mirrors the suite's one-section-per-concern convention. |

## Package Legitimacy Audit

**Not applicable — this phase installs no external packages.** No `npm`/`pip`/`cargo` dependencies are added; all tooling (docker, nginx, git, shasum, POSIX sh) is pre-existing host/base-image software already vetted in Phases 1–6. No legitimacy gate required.

## Architecture Patterns

### System Data Flow (already built — Phase 7 asserts it, adds nothing)

```
                       ┌──────────────────────────────────────────────┐
   client container    │                  the SWITCH                   │
   (app.demo.test)     │  switch/active-proxy.conf  ← the ONE selector │
        │  HTTP :9092   │  (default old|new)  governs BOTH protocols   │
        │  SSH  :22     │                                              │
        ▼               │   map → upstream proxy-old | proxy-new        │
  ┌───────────┐  reload └───────┬───────────────────────┬──────────────┘
  │ flip.sh   │─ nginx -s reload│                       │
  │ old|new   │  (switch only)  ▼                       ▼
  └───────────┘          ┌────────────┐          ┌────────────┐
                         │  proxy-old │          │  proxy-new │   ← STATIC :ro
   VAL-04 checksums ────▶│ nginx.conf │          │ nginx.conf │      never written
   these two files       │ (untouched)│          │ (untouched)│      by any script
                         └─────┬──────┘          └─────┬──────┘
                               ▼                       ▼
                         ┌────────────┐          ┌────────────┐
                         │ server-old │          │ server-new │
                         └────────────┘          └────────────┘

   VAL-03 rollback:  flip.sh new  →  (both protocols NEW)  →  flip.sh old  →  (both protocols OLD)
                     proved by: curl :9092 + ssh app.demo.test land OLD; StartedAt of all
                     containers UNCHANGED across the whole cycle (no teardown).
```

### Pattern 1: The cutover-cycle assertion (VAL-03 + VAL-04 in one flip cycle)
**What:** Perform exactly one real cutover-and-rollback (`flip.sh new` then `flip.sh old`), capturing checksums and container state at three points, asserting many facts over one cycle.
**When to use:** VAL-03 and VAL-04 both require a real cutover to have happened; share it.
**Example (assertion sketch, house style — verify against `section_cutover`):**
```sh
# Source: derived from smoke.sh section_cutover (CUT-05 StartedAt idiom) + D-35 shasum idiom
restore_flip_state                      # existing trap-based restore (smoke.sh:316)
sh scripts/flip.sh old >/dev/null 2>&1; settle_flip old

# capture BEFORE
_sha_before=$(shasum -a 256 proxy-old/nginx.conf proxy-new/nginx.conf | awk '{print $1}')
_ids=$(docker compose ps -q proxy-old proxy-new switch server-old server-new)
_started_before=$(echo "$_ids" | xargs docker inspect -f '{{.State.StartedAt}}')
_pworkers_before=$(docker compose exec -T proxy-old pgrep -f 'nginx: worker'; \
                   docker compose exec -T proxy-new pgrep -f 'nginx: worker')

sh scripts/flip.sh new; settle_flip new         # THE CUTOVER
_sha_mid=$(shasum -a 256 proxy-old/nginx.conf proxy-new/nginx.conf | awk '{print $1}')

sh scripts/flip.sh old >/dev/null 2>&1; settle_flip old   # THE ROLLBACK (VAL-03)
_sha_after=$(shasum -a 256 proxy-old/nginx.conf proxy-new/nginx.conf | awk '{print $1}')
_started_after=$(echo "$_ids" | xargs docker inspect -f '{{.State.StartedAt}}')

# VAL-04: byte-identical across the whole cycle
assert "VAL-04 static proxy configs byte-identical before==after-flip==after-rollback" \
  "test '$_sha_before' = '$_sha_mid' && test '$_sha_mid' = '$_sha_after'"
# VAL-03/04: no teardown — nothing restarted
assert "VAL-03/04 no container restarted across cutover+rollback (StartedAt unchanged)" \
  "test -n '$_started_before' && test '$_started_before' = '$_started_after'"
```
*Plus:* both-protocol OLD after rollback (HTTP via `curl localhost:9092/whoami` == `OLD server-old`; SSH via test-mode `ssh app.demo.test` banner == `OLD server-old`), and the static-proxy **worker PIDs unchanged** (proves not even a *reload* reached them).

### Pattern 2: Non-destructive v1-preservation assertion (MIG-03)
**What:** Prove the preserved v1 form exists and is coherent **without checking it out** (a checkout would dirty the working tree mid-suite).
**Example:**
```sh
# Source: git ls-tree v1.0 / git show v1.0:<path> — all read-only
assert "MIG-03 the v1.0 tag exists" 'git rev-parse -q --verify refs/tags/v1.0'
assert "MIG-03 v1.0 preserves the single-proxy topology (one 'proxy' service, no switch)" \
  'git show v1.0:compose.yaml | grep -qE "^  proxy:" && ! git show v1.0:compose.yaml | grep -qE "^  switch:"'
assert "MIG-03 v1.0 ships the preserved proxy config and flip include" \
  'git cat-file -e v1.0:proxy/nginx.conf && git cat-file -e v1.0:proxy/active-backend.conf'
assert "MIG-03 v1.0 Makefile brings it up standalone (has an 'up' target on 'proxy')" \
  'git show v1.0:Makefile | grep -qE "^up:"'
```

### Anti-Patterns to Avoid
- **`git checkout v1.0` inside the smoke suite** — destructive to the working tree; assert the tag's *content* via `git show`/`git cat-file` instead.
- **`sha256sum`** — absent on stock macOS; use `shasum -a 256`.
- **Rewriting `WALKTHROUGH.md` without updating `section_walkthrough`** — the lint hard-codes 8 steps and the exact v1 narrative keyword order; a v2 rewrite turns it red instantly (see Pitfall 1).
- **Adding a new make target the walkthrough uses but not adding it to `.PHONY`** — `section_walkthrough` asserts every `make <target>` in the doc is declared in `.PHONY` (smoke.sh:1977).
- **Re-scoping the host-key gotcha** — it is inherited v1 backend behaviour (KEY-*); surface it in the v2 narrative only. Out of scope per REQUIREMENTS.md "New SSH host-key scope in v2".
- **Executing extracted walkthrough commands** — `section_walkthrough` must stay a pure reader (T-04-19 guard at smoke.sh:2032).

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Rollback mechanism | A new "rollback" script | `flip.sh old` (exists) | Already flips both protocols via one switch reload; adding a second path would drift from the flip the demo teaches |
| No-teardown proof | Parsing `docker compose ps` uptime strings | `docker inspect -f '{{.State.StartedAt}}'` | Existing CUT-05 idiom; immune to ps output-format drift (smoke.sh:454) |
| Settle-after-reload timing | New sleep constants | `settle_flip <target>` (exists) | Polls the `:8081` oracle + 200ms margin; already tuned against measured 26–90ms interleave (smoke.sh:296) |
| Restore-on-interrupt | Ad-hoc cleanup | `restore_flip_state`/trap idiom (exists) | The suite's standard destructive-section discipline (smoke.sh:316) |
| v1 preservation | A duplicated `compose.v1.yaml` | `git tag v1.0` | Self-contained, zero-maintenance, no port collision |

**Key insight:** This phase's correct output is *mostly new assertions and prose over an unchanged runtime*. Every mechanism it needs already exists and is battle-tested by 231 assertions. The risk is narrative/contract drift (the walkthrough lint), not new-code bugs.

## Runtime State Inventory

> Rename/refactor-adjacent close-out. After the doc rewrite and new assertions land, what runtime/stored state carries an old shape?

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| Stored data | **None.** The only mutable runtime datum is the evidence log (`/var/log/demo/access.log`), truncated by `make up`/`flip.sh old` by design (D-36). No DB, no keys renamed by this phase. | None — verified: no datastore holds a Phase-7-renamed string. |
| Live service config | **None to migrate.** The switch + two proxies keep their exact configs; VAL-04's whole point is that `proxy-old/nginx.conf` + `proxy-new/nginx.conf` are *unchanged*. No workflow/dashboard state outside git. | None — the phase asserts config immutability, it does not change config. |
| OS-registered state | The one-time `/etc/hosts` line `127.0.0.1 app.demo.test` (client-side, already present; `make status` checks it). No new host registration. | None new. Walkthrough pre-flight already documents it. |
| Secrets/env vars | `demo-keys` named volume + `demo:demo` credential — unchanged. No secret renamed. | None. |
| Build artifacts / preserved dirs | **`proxy/` on main is a preserved-but-UNWIRED v1 artifact** (`proxy/nginx.conf`, `proxy/active-backend.conf`). v2 compose references `proxy-old`/`proxy-new`/`switch`, **not** `proxy/`. It duplicates the v1.0 tag's `proxy/` and can silently drift from it. | **Decision needed (see Open Questions Q1):** keep `proxy/` as-is (harmless, but a second copy of the v1 config) OR treat the git tag as the sole canonical v1 form. MIG-03 is satisfied by the tag either way. Recommend: tag is canonical; leave `proxy/` untouched (deleting is out of scope) but do NOT wire it into a compose file. |

**Canonical question — after the doc rewrite and new assertions land, what still carries the old shape?** Only the orphaned `proxy/` directory (a duplicate, not a live dependency) and any hard-coded v1 narrative inside `section_walkthrough` (which this phase updates). Everything else is unchanged by design.

## Common Pitfalls

### Pitfall 1: The walkthrough lint hard-codes the v1 narrative — rewriting the doc turns it red
**What goes wrong:** `section_walkthrough` (smoke.sh:1821-2036) asserts **exactly 8 numbered steps** (`WT_STEPS = 8`), numbered `1..8`, in the **literal keyword order** `show-old redirect-contrast prime flip gotcha wrong-fix right-fix reset` (smoke.sh:1997-1998), plus five named traps and full prerequisite closure. A v2 rewrite that changes the beats/order fails these instantly.
**Why it happens:** The lint is a deliberate anti-rot contract (Phase 4, D-54/D-55). It is *supposed* to bind tightly to the shipped narrative.
**How to avoid:** Treat `WALKTHROUGH.md` and `section_walkthrough` as **one change**. The plan must, in lockstep: (a) define the exact v2 beat list + step count, (b) update `WT_NARRATIVE`'s awk keyword matcher and the `WT_STEPS`/`WT_NUMSEQ` assertions, (c) update the trap assertions if trap set changes, (d) ensure every `make` target used in the new doc is in `.PHONY` and satisfies prerequisite closure (introduced in pre-flight or an earlier beat).
**Warning signs:** `make test` red in `--- walkthrough ---` with `WALK-01 ... eight numbered step headings` or `... fixed D-55 narrative order`.

### Pitfall 2: `sha256sum` not on macOS
**What goes wrong:** `sha256sum: command not found` on a presenter's stock macOS laptop; the VAL-04 assertion errors instead of comparing.
**How to avoid:** Use `shasum -a 256` (Perl-based, ships with macOS and Linux). Extract field 1 with `awk '{print $1}'`, matching the existing `shasum` idiom at smoke.sh:478.
**Warning signs:** Green on the dev machine (which has coreutils), red on a fresh Mac.

### Pitfall 3: `flip.sh old` truncates the evidence log — the rollback *demo* beat looks like a reset
**What goes wrong:** In the walkthrough rollback beat, `make flip-old` (D-36) clears the evidence log and issues **no** confirming request — it is *also the between-takes reset direction*. On the projected status page the counters drop to zero, which can read as "the demo ended" rather than "traffic rolled back to OLD."
**Why it happens:** D-36/D1 deliberately made the `old` direction a reset (removes the convergence-flash race). Rollback and reset are the same command.
**How to avoid:** In the walkthrough, narrate the rollback with a follow-up `make verify` (which re-confirms OLD on both protocols and re-seeds one evidence line) rather than relying on the status page counters. For the **VAL-03 smoke assertion**, truncation is irrelevant — assert routing (`curl`/`ssh` land OLD) and StartedAt-unchanged, not evidence counts.
**Warning signs:** Presenter confusion on stage; a rollback beat whose "Expect" block claims counters that flip.sh just zeroed.

### Pitfall 4: New SSH assertion using the wrong connection mode
**What goes wrong:** A VAL-03 SSH rollback check that omits the test-mode host-key options trips over the Phase-4 host-key mismatch and fails for the wrong reason (or, worse, silently reads a host-key failure as success if the ssh call is on the left of a pipe).
**How to avoid:** Reuse the exact idiom from `section_validate`/`section_ssh`: export `SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"`, capture via command substitution with `2>&1`, read `$?` on the very next line, grep the captured variable — **never** put ssh on the left of a pipe (smoke.sh:1180-1189).
**Warning signs:** Intermittent SSH reds; an assertion that passes even when the banner is wrong.

### Pitfall 5: Asserting "never reloaded" with StartedAt alone
**What goes wrong:** StartedAt catches a container *restart* but not a *reload* — an `nginx -s reload` keeps the master PID and StartedAt but respawns workers. If VAL-04's claim is the stronger "never touched *at all*," StartedAt is necessary but not sufficient.
**How to avoid:** Add a **worker-PID-unchanged** check on `proxy-old`/`proxy-new` (`pgrep -f 'nginx: worker'` before == after). Since `flip.sh` only reloads the *switch*, the static proxies' workers must be identical across the cycle. This is the assertion that makes "never touched" literally true beyond the file checksum.
**Warning signs:** A future refactor that accidentally reloads all tiers would pass a StartedAt-only check.

## Code Examples

### Portable sha256 of the two static proxy configs (VAL-04)
```sh
# Source: house idiom smoke.sh:478 (shasum) upgraded to -a 256 for the criterion
shasum -a 256 proxy-old/nginx.conf proxy-new/nginx.conf | awk '{print $1}'
# → two hex lines; capture at 3 points (before / after flip-new / after flip-old) and assert equal
```

### No-teardown proof across the cutover+rollback cycle (VAL-03)
```sh
# Source: smoke.sh:453-463 (CUT-05), extended to the two static proxies
_ids=$(docker compose ps -q proxy-old proxy-new switch server-old server-new)
_before=$(echo "$_ids" | xargs docker inspect -f '{{.State.StartedAt}}')
# ... flip new, settle, flip old, settle ...
_after=$(echo "$_ids" | xargs docker inspect -f '{{.State.StartedAt}}')
test -n "$_before" && test "$_before" = "$_after"   # unchanged ⇒ nothing restarted
```

### v1 preservation without a checkout (MIG-03)
```sh
# Source: git plumbing, read-only
git rev-parse -q --verify refs/tags/v1.0                     # tag exists
git show v1.0:compose.yaml | grep -qE '^  proxy:'            # single-proxy topology
git cat-file -e v1.0:proxy/active-backend.conf              # flip include preserved
git show v1.0:Makefile | grep -qE '^up:'                    # brings up standalone
```

### Presenter re-run of v1 (documented, not tested destructively)
```bash
# In WALKTHROUGH.md / README, for the MIG-03 beat:
git stash        # if the working tree is dirty
git checkout v1.0
make up          # v1's own Makefile + compose, single proxy on 9092/9093
# ... show v1 ...
make down
git checkout main   # (or the branch you were on)
```

## Proposed v2 Walkthrough Beat List (MIG-02)

The ROADMAP criterion-4 narrative is: **validate the new stack → flip the switch → land on new → host-key gotcha (inherited) → roll back → the old proxy was never touched.** A candidate beat map (planner finalizes the exact `WT_NARRATIVE` keyword set and step count, then updates `section_walkthrough` to match):

| # | Beat | Run (existing command) | Takeaway |
|---|------|------------------------|----------|
| 1 | Validate the new stack pre-flip | `make verify-new-stack` | The new stack answers NEW on both protocols *before* any cutover, while live traffic still lands OLD |
| 2 | Show OLD through the switch | `make verify` | Same hostname/port; everything lands OLD via `switch → proxy-old → server-old` |
| 3 | (optional) redirect contrast | `make contrast` | Proxy vs 301 — the client-notices-nothing point (carries from v1; may keep or trim) |
| 4 | Prime SSH trust on OLD | `make ssh` | Records the trust entry keyed on `app.demo.test` (arms the gotcha) |
| 5 | The flip | `make flip-new` | One word, one reload on the switch — both protocols move to NEW; static proxies untouched |
| 6 | The host-key gotcha (inherited) | `make ssh` | `REMOTE HOST IDENTIFICATION HAS CHANGED` — surfaced, not re-scoped |
| 7 | The fix | `make fix-hostkeys` + `make ssh` | Move the identity, not the objection (inherited v1 fix) |
| 8 | Instant rollback | `make flip-old` (+ `make verify` to re-confirm) | Flip back, no teardown — both protocols return to OLD in one reload |
| 9 | The old proxy was never touched | a checksum command (see below) | `shasum -a 256` of the two static configs is identical before and after — a proof, not a claim |
| 10 | Reset for next take | `make reset` | Full re-arm (carries from v1) |

**Note:** This is ~9–10 beats vs v1's 8. The planner must set `WT_STEPS`, `WT_NUMSEQ`, and the `WT_NARRATIVE` keyword list in `section_walkthrough` to the final chosen sequence. The wrong-fix contrast beat and some traps from v1 may be kept, trimmed, or re-ordered — whatever ships must be reflected in the lint.

**New presenter make target likely needed:** a "proxies untouched" checksum target (e.g. `make proxies-untouched`) so beat 9 has a real Run command with real Expect output. It **must** be added to `.PHONY` (smoke.sh:1977 asserts this) and introduced in the pre-flight checklist or beat 9's own Run block (prerequisite closure, smoke.sh:1989).

## State of the Art

| Old (v1) Approach | Current (v2) Approach | When Changed | Impact on Phase 7 |
|--------------------|-----------------------|--------------|-------------------|
| Single flip-in-place `proxy` (edits `proxy/active-backend.conf`) | Front `switch` flips between two static proxies | Phase 5 | Rollback is now "instant + old proxy never touched" — the whole point of VAL-03/04 |
| Walkthrough selector file `proxy/active-backend.conf` | `switch/active-proxy.conf` | Phase 5 | v2 walkthrough must reference the switch's file, not the old proxy include |
| `make flip-*` reloads the `proxy` | reloads the `switch` (governs both protocols) | Phase 5–6 | One reload rolls back both protocols |

**Deprecated/outdated on main:**
- `proxy/` directory — the v1 single-proxy config, now **unwired** (no compose service references it). Superseded by the v1.0 tag as the canonical preserved form. See Open Questions Q1.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | The exact v2 beat count/order is a planning decision; ~9–10 beats proposed | Proposed Beat List | Low — planner sets the final contract; the table is a starting point, not a locked sequence |
| A2 | `pgrep -f 'nginx: worker'` is available inside `nginx:1.30-alpine` for the worker-PID check | Pitfall 5 / Pattern 1 | Low-Med — if `pgrep` is absent, use `ps` or `nginx -s reload`-count via error log; verify in a task before relying on it. Tag: [ASSUMED] |
| A3 | A follow-up `make verify` after `make flip-old` cleanly re-seeds one evidence line for the rollback beat | Pitfall 3 | Low — `verify.sh` issues one HTTP+SSH probe; behaviour is established, but confirm the beat reads well in the cold-read check |

**Everything else in this document is [VERIFIED] against files read this session.**

## Open Questions

1. **The orphaned `proxy/` directory on main.**
   - What we know: `proxy/nginx.conf` + `proxy/active-backend.conf` are the preserved v1 single-proxy config, present on main but referenced by **no** v2 compose service. The v1.0 tag holds an identical copy and is the self-contained runnable form.
   - What's unclear: keep it (belt-and-suspenders, but a second copy that can drift from the tag) or accept the tag as sole canonical form.
   - Recommendation: **Rely on the git tag for MIG-03.** Leave `proxy/` untouched (deleting is out of scope for a close-out), and do NOT wire it into a `compose.v1.yaml`. If the team wants a single source of truth, a follow-up cleanup can remove `proxy/` from main — but that is not required to satisfy MIG-03.

2. **Do VAL-03 and VAL-04 share one smoke section or split?**
   - Recommendation: **one combined `section_rollback`** (one flip cycle, all assertions) placed after `section_validate`/`section_ssh` and before `section_hostkey` in the `all` chain (it is destructive — flips the selector — so it needs the trap-restore discipline and must not precede the pure-reader sections). It leaves the rig on OLD, the precondition the next section expects.

3. **Which trap set does the v2 walkthrough carry?**
   - The v1 traps (301 cache/incognito, client+22, 9093-doesn't-follow-flip, `make reset` re-arm, `make verify` host-key-blind) mostly still hold. New candidate trap: "`flip-old` is the reset direction — it truncates the evidence log" (Pitfall 3). The planner sets the final trap list and updates the five `section_walkthrough` trap assertions accordingly.

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Docker Compose v2 | whole rig | ✓ (pre-existing) | host | — |
| `shasum` (Perl) | VAL-04 sha256 | ✓ | /usr/bin/shasum | — |
| `sha256sum` | (avoided) | ✓ here / ✗ stock macOS | /sbin (coreutils) | Use `shasum -a 256` |
| git | MIG-03 tag assertions | ✓ | host | — |
| `pgrep` in nginx:alpine | worker-PID check (A2) | ? | verify in-task | `ps` / error-log reload count |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** `sha256sum` → `shasum -a 256` (already the recommendation).

## Validation Architecture

> `nyquist_validation` is enabled (config.json). Observable, laptop-runnable checks per success criterion.

### Test Framework
| Property | Value |
|----------|-------|
| Framework | POSIX `sh` assertion harness — `scripts/smoke.sh` (`assert <label> <shell-condition>`) [VERIFIED: smoke.sh:14] |
| Config file | none — a self-contained shell script |
| Quick run command | `sh scripts/smoke.sh <section>` (e.g. a new `rollback` / `preserve` section, plus `walkthrough`) |
| Full suite command | `make test` (`sh scripts/smoke.sh all`) |

### Phase Requirements → Test Map
| Req | Behavior | Test Type | Automated Command | Exists? |
|-----|----------|-----------|-------------------|---------|
| VAL-03 | Rollback returns BOTH protocols to OLD, no teardown | integration | `sh scripts/smoke.sh rollback` (new) — flip new→old; assert `curl :9092`==OLD, test-mode `ssh app.demo.test` banner==OLD, StartedAt unchanged | ❌ Wave 0 |
| VAL-04 | Static proxy configs byte-identical across cutover+rollback | integration | same section — `shasum -a 256` triple-equality + proxy-old/new StartedAt + worker-PID unchanged | ❌ Wave 0 |
| MIG-03 | v1 preserved form comes up unbroken | static (non-destructive) | `sh scripts/smoke.sh preserve` (new) — `git rev-parse v1.0`, `git show v1.0:compose.yaml`\|grep `proxy:`, `git cat-file -e v1.0:proxy/...`, Makefile `up:` | ❌ Wave 0 |
| MIG-02 | Walkthrough is self-contained & executable for the v2 narrative | doc-lint | `sh scripts/smoke.sh walkthrough` — **updated** `section_walkthrough` (new beat count/order/targets/traps) | ⚠️ exists, must be rewritten in lockstep |
| MIG-02 (criterion) | Walkthrough is *comprehensible* (a room can follow it) | manual (blocking) | Human cold read — a judgement no assertion can make (T-04-16 precedent) | Human checkpoint |

### Sampling Rate
- **Per task commit:** the specific new section (`sh scripts/smoke.sh rollback` / `preserve` / `walkthrough`).
- **Per wave merge:** `make test` (full suite green).
- **Phase gate:** full suite green + the blocking human cold-read of the rewritten `WALKTHROUGH.md` (criterion 4 comprehensibility) before `/gsd-verify-work`.

### Executable-contract check (does v1's `section_walkthrough` carry forward?)
**Yes, and it MUST be updated, not just re-run.** The section (smoke.sh:1821-2036) lints `WALKTHROUGH.md` by extraction: fenced ```bash commands must be real `.PHONY` targets or real binaries; every referenced repo path must resolve; no placeholders/ellipses; N numbered steps in a fixed keyword order; Run/Expect/Say per step in that order; prerequisite closure; named traps present; and it must never execute what it extracts. For the v2 rewrite the planner updates the hard-coded expectations (`WT_STEPS`, `WT_NUMSEQ`, `WT_NARRATIVE` keywords, trap assertions) to the new beat list. The comprehensibility claim (criterion 4's "a room can follow it") is **not** covered by any assertion and rests on a blocking human cold read — cite this in VALIDATION.md exactly as Phase 4 did (04-VALIDATION "On ROADMAP criterion 5").

### Wave 0 Gaps
- [ ] New `section_rollback` in `scripts/smoke.sh` — VAL-03 + VAL-04 (one flip cycle).
- [ ] New `section_preserve` in `scripts/smoke.sh` — MIG-03 (git-tag assertions, non-destructive).
- [ ] Wire both new sections into the dispatch `case` and the `all` chain (rollback before `section_hostkey`; preserve is a pure reader, place early).
- [ ] Update `section_walkthrough` expectations to the v2 beat list (in lockstep with the doc rewrite).
- [ ] Any new presenter make target (checksum / rollback framing) added to `.PHONY`.

*(Framework already exists — these are additions, not a new harness.)*

## Security Domain

> `security_enforcement: true`, ASVS level 1. This phase adds shell assertions + docs; no new network surface, no new auth, no new secrets.

### Applicable ASVS Categories
| ASVS Category | Applies | Standard Control |
|---------------|---------|-----------------|
| V1 Architecture | yes (light) | Preserve existing invariants: no Docker socket mount (D-29), loopback-only port binding, no host :22 (D-15). Phase 7 adds none of these. |
| V5 Input Validation | no | No user input; assertions read fixed files/commands |
| V6 Cryptography | no (integrity only) | `shasum -a 256` is an integrity check, not a security control — do not overstate it as tamper-proofing |
| V12 Files/Resources | yes | `section_walkthrough` must stay a **reader** — never `eval`/execute extracted document text (T-04-19 guard, smoke.sh:2032). Any new section handling doc/file text inherits this rule. |
| V14 Configuration | yes | Static-proxy configs `:ro`; status service mounts `:ro`; no new writable mount or exposed port introduced |

### Known Threat Patterns for this stack
| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Executing text extracted from `WALKTHROUGH.md` | Elevation of Privilege | Keep `section_walkthrough` a pure reader; assert no `eval`/`sh $WT_TMP`/`xargs` in-section (existing guard) |
| A new `compose.v1.yaml` re-exposing ports on 0.0.0.0 | Information Disclosure | **Avoid it — use the git tag.** If ever added, bind loopback only (T-01-15 precedent) |
| Docker socket mounted to inspect container state | Elevation of Privilege | Never mount it (D-29); use host-side `docker inspect` for StartedAt/PID |

**No `security_block_on: high` items identified for this phase.** It introduces no new attack surface; the controls above are *preserve-don't-regress* checks.

## Sources

### Primary (HIGH confidence — codebase-verified this session)
- `scripts/flip.sh` — rollback mechanism (flips both directions; switch reload; D-36 truncation on `old`)
- `scripts/smoke.sh` — assertion harness; `section_cutover` (CUT-05 StartedAt/`shasum` idioms), `section_validate`/`section_ssh` (SSH capture idiom), `section_walkthrough` (the executable contract), dispatch/`all` chain
- `compose.yaml` — v2 topology; static proxies `:ro`, publish nothing, never reconfigured
- `Makefile` — presenter targets + `.PHONY`; `flip-old`/`flip-new`/`verify`/`verify-new-stack`/`reset`/`rearm`/`fix-hostkeys`
- `proxy-old/nginx.conf` — confirms static single-upstream, never-reconfigured proxy
- `WALKTHROUGH.md` — the v1 presenter script to rewrite (8-beat structure, Run/Expect/Say, traps)
- `.planning/REQUIREMENTS.md`, `.planning/ROADMAP.md`, `.planning/STATE.md`, `.planning/config.json`
- `git tag` / `git ls-tree v1.0` / `git show v1.0:compose.yaml` / `git show v1.0:Makefile` — v1.0 is self-contained
- `grep` of `scripts/` + `Makefile` — no script writes `proxy-old/nginx.conf` or `proxy-new/nginx.conf`

### Secondary / Tertiary
- None — no external/web sources needed; this is a self-contained brownfield close-out.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new packages; all tooling verified present in-tree
- Rollback/checksum mechanism (VAL-03/04): HIGH — flip.sh + existing CUT-05/D-35 idioms cover it; only new assertions needed
- v1 preservation (MIG-03): HIGH — v1.0 tag confirmed self-contained via git plumbing
- Walkthrough contract (MIG-02): HIGH on *what the lint enforces*; the final beat list is a planning decision (A1)
- Worker-PID check availability (A2): MEDIUM — verify `pgrep` in nginx:alpine in-task

**Research date:** 2026-07-22
**Valid until:** 2026-08-21 (stable; the only volatility is the final v2 beat list, decided at plan time)

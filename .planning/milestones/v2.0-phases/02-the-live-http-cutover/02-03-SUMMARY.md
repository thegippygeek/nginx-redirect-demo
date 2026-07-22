---
phase: 02-the-live-http-cutover
plan: 03
subsystem: projected-status-page
tags: [html, inline-css, inline-js, no-dependencies, projector, accessibility, xss-mitigation]

# Dependency graph
requires:
  - phase: 02-the-live-http-cutover
    plan: 02
    provides: "GET /api/status — the 15-key contract, with boundary.row_index and since_flip_s computed server-side; GET / already serving /app/index.html from the read-only ./status:/app:ro mount"
provides:
  - "status/index.html — the projected cutover surface: one hand-written file, inline style and script, zero external origins"
  - "The D-27 dual reading rendered at a 2.8x hierarchy with a three-caption sync marker between the two readings"
  - "A 1000 ms fetch poll with a 5000 ms client watchdog — the only mechanism that can detect the page's own server dying"
  - "The four UI-SPEC states, pairwise distinguishable from a screenshot alone with no caption"
  - "A 900 ms one-shot convergence sequence with a persistent-ring reduced-motion fallback"
affects: [02-04 smoke/README completion and the visual audit]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Zero third-party UI code: no package.json, no framework, no icon set, no font file, no remote origin of any kind (ENV-03)"
    - "textContent-only rendering for every log-derived cell — the escaping burden sits entirely on the renderer"
    - "Server-authoritative readings: boundary.row_index and since_flip_s are consumed verbatim, never re-derived client-side"
    - "Cancellable one-shot animation: a state transition arriving mid-sequence tears the sequence down rather than letting it complete"
    - "Root scale hook dividing a length by a plain number inside calc(), so the whole rem scale tracks viewport width"

key-files:
  created:
    - status/index.html
  modified: []

key-decisions:
  - "The uniform table row height ships at 52px, not UI-SPEC's 68px reference: 8 rows at 68px plus a header, a 200px Hero, the config strip, the sync marker, the footer and the 48px safe area sum to ~1267px against a 1080px frame that the same document declares must never scroll"
  - "The table's edge bar is WHITE against the accent row fill, not accent-on-accent — an accent bar on an accent row is invisible, and the shape channel is mandatory because OLD and NEW are isoluminant"
  - "The convergence sequence is cancellable rather than merely guarded, because flip.sh performs a genuine flip to OLD before truncating the evidence and the page cannot see the truncation coming"
  - "Two error-copy strings were added for the proxy and status failing sources, which the copywriting contract does not enumerate but 02-02 actually emits; both keep the load-bearing 'Not showing a stale reading.' sentence verbatim"

patterns-established:
  - "Headless-Chrome-over-CDP verification: the four states, the convergence timing, the reduced-motion fallback, the greyscale test and the no-scrollbar test are all driven and measured against the live page rather than asserted from the source"

requirements-completed: [EVID-02, EVID-03]

coverage:
  - id: D1
    description: "Both D-27 readings render simultaneously at a 2.8x hierarchy and are never merged; the sync marker carries all three captions and the PENDING gap is visible"
    requirement: "EVID-02"
    verification:
      - kind: command
        ref: "grep -c 'CONFIG SAYS' status/index.html == 1 and 'TRAFFIC SHOWS' == 1 and IN SYNC / AWAITING FIRST REQUEST / WAITING FOR RELOAD each >= 1"
        status: pass
      - kind: integration
        ref: "CDP drive: NORMAL renders cfg NEW / hero NEW / sync IN SYNC; the reset renders cfg OLD / hero em dash / sync AWAITING FIRST REQUEST"
        status: pass
    human_judgment: false
  - id: D2
    description: "The page reaches UNAVAILABLE within 5 s of the proxy dying, desaturated and hazard-bordered, with every reading blanked and no stale OLD or NEW anywhere"
    requirement: "EVID-02"
    verification:
      - kind: integration
        ref: "CDP drive: docker compose stop proxy, +7 s -> hero UNAVAILABLE at 72px, filter saturate(0.15), hazard visible, config em dash, counters em dash, rows 0"
        status: pass
      - kind: integration
        ref: "CDP drive: docker compose start proxy -> NORMAL restored, convergence fired 0 times on recovery"
        status: pass
      - kind: command
        ref: "grep -c 'saturate(0.15)' >= 1, 'repeating-linear-gradient' >= 2, 'Not showing a stale reading.' >= 1, '#ef4444|#dc2626' == 0"
        status: pass
    human_judgment: false
  - id: D3
    description: "Every log-derived cell is written with textContent: a request path carrying markup renders as literal characters and executes nothing (T-02-01)"
    requirement: "EVID-03"
    verification:
      - kind: integration
        ref: "CDP drive: /x%3Cscript%3Ealert(1)%3C/script%3E renders as the literal string, 0 script elements in tbody, 0 javascriptDialog events"
        status: pass
      - kind: command
        ref: "grep -c 'innerHTML' status/index.html == 0 (asserted on both the source and the served body)"
        status: pass
    human_judgment: false
  - id: D4
    description: "The audit trail renders newest-first with exactly one structural boundary rule at the server-supplied index, no blank filler rows and no scrollbar"
    requirement: "EVID-03"
    verification:
      - kind: integration
        ref: "CDP drive: 11 requests -> exactly 8 rows, one uniform offsetHeight, oldest evicted; after a flip 7 rows + 1 boundary with 3 above it matching boundary.row_index == 3"
        status: pass
      - kind: integration
        ref: "CDP drive: document.body.scrollHeight === window.innerHeight at 1920x1080 in all four states"
        status: pass
      - kind: command
        ref: "grep -c 'row_index' >= 1 and setInterval-on-clock == 0 — boundary and clock are server-driven"
        status: pass
    human_judgment: false
  - id: D5
    description: "The convergence sequence fires exactly once per real flip, completes under 1 s, and does not fire on load, first poll, recovery from UNAVAILABLE, or the first traffic after a reset"
    verification:
      - kind: integration
        ref: "CDP ring-timing harness across 3 cycles: money shot fired once at 900/902/901 ms each time; 0 fires on page load, on recovery, and on the first request after a reset"
        status: pass
      - kind: integration
        ref: "CDP with prefers-reduced-motion: reduce -> ring persists 2001 ms as a static box-shadow, animations disabled"
        status: pass
    human_judgment: false
  - id: D6
    description: "The evidence reset is confirmed on screen for 10 s as a fixed overlay, with nothing beneath it reflowing"
    verification:
      - kind: integration
        ref: "CDP drive: flip.sh old -> overlay visible with 'EVIDENCE CLEARED · HH:MM:SS · READY FOR NEXT TAKE', counters 0/0, NO FLIP YET; hidden again after ~10 s; scrollHeight unchanged throughout"
        status: pass
    human_judgment: false
  - id: D7
    description: "The served page issues zero requests to any origin other than its own, and the rem scale is live rather than collapsed to the 16px UA default"
    verification:
      - kind: command
        ref: "grep '@font-face' == 0, 'cdn' == 0, no src/href to any remote origin; grep -c '100vw / 120' == 1 and '100vw / 1920' == 0"
        status: pass
      - kind: integration
        ref: "CDP: getComputedStyle(documentElement).fontSize == 10.6667px at 1280 wide (UI-SPEC test 11)"
        status: pass
    human_judgment: false
  - id: D8
    description: "Exactly 4 font sizes and exactly 2 font weights; the two accents appear only as background fills, never as text or border colour"
    verification:
      - kind: command
        ref: "font-size audit: --fs-hero/--fs-display/--fs-label/--fs-meta only, plus the root scale hook; font-weight audit: 400 and 700 only; accent-as-color/border grep == 0"
        status: pass
    human_judgment: false
  - id: D9
    description: "In greyscale a viewer can still state which backend is active and locate the flip boundary (UI-SPEC test 1)"
    verification:
      - kind: integration
        ref: "CDP screenshot with grayscale(1) applied: the two accent fills are indistinguishable as predicted, while the word, the rail position, the edge-bar cap shape and the 8px white captioned rule each carry the signal alone"
        status: pass
    human_judgment: false
  - id: D10
    description: "Projector legibility at ~10 m in a bright room, and whether the flip reads as an event rather than a flicker to a live audience"
    verification: []
    human_judgment: true
    rationale: "Viewing distance, ambient washout, keystone cropping of the 48px safe area and the felt quality of the 900 ms convergence cannot be measured from a screenshot. 02-VALIDATION lists projector legibility as manual-only and 02-04 carries the visual audit."
  - id: D11
    description: "The 12px edge-bar cap shape is distinguishable at 10 m in monochrome"
    verification: []
    human_judgment: true
    rationale: "The cap renders correctly and survives greyscale in a screenshot, but 12px is small and whether the square-versus-chamfer distinction actually resolves at projection distance needs a human at the back of the room. The word and the rule carry the signal regardless, so this channel is reinforcement rather than load-bearing."

# Metrics
duration: 42 min
completed: 2026-07-21
status: complete
---

# Phase 2 Plan 03: The Projected Cutover Surface Summary

**One 710-line hand-written HTML file with no dependencies, no build step and no external origin, rendering the 02-02 contract as the surface a room watches during the flip — with the configured intent and the observed traffic held deliberately apart at a 2.8x hierarchy, a 5 s watchdog that makes the page admit its own server has died, and every attacker-influenced log value routed through `textContent`.**

## Performance

- **Duration:** 42 min
- **Started:** 2026-07-21T09:12Z
- **Completed:** 2026-07-21T09:54Z
- **Tasks:** 3
- **Files created:** 1

## Accomplishments

- **D-27's gap is now something a room can watch close.** `CONFIG SAYS` sits at 72px above `TRAFFIC SHOWS` at 200px, never side by side, with a 40px sync marker between them carrying three distinct captions off the `sync` key. When they disagree the rule goes dashed, white and pulsing, the config chip gains a 4px white outline, and the page literally reads `CONFIG SAYS NEW` above `TRAFFIC SHOWS OLD` — no decoding required.
- **D-28's honest UNAVAILABLE renders, and it is unmistakable.** Driven live: `docker compose stop proxy`, and within 5 s the whole page desaturates to `saturate(0.15)`, gains a 12px diagonal hazard border no other state has, drops the Hero to Display size, blanks the config chip and both counters to em dashes, and **replaces** the table rows with copy naming the failing source, the error detail and the remedy. No stale `OLD` or `NEW` survives anywhere on the surface.
- **The XSS vector research demonstrated is closed and proven closed.** A request to `/x%3Cscript%3Ealert(1)%3C/script%3E` travels verbatim through `$uri` into the JSON and onto the page, where it renders as the literal string `/x<script>alert(1)</script>`. Measured on the live page: **0** `script` elements created inside the table, **0** JavaScript dialog events, and `grep -c 'innerHTML'` is 0 on both the source and the served body.
- **The greyscale test passes decisively.** Converting the NORMAL state to greyscale confirms the isoluminance finding exactly — `#b45309` and `#15803d` become the same grey — while the word, the rail position, the edge-bar cap shape and the 8px white captioned rule each independently answer "which backend, and where did it flip".
- **The convergence sequence is measured, not assumed.** Across three consecutive cycles the money shot fired exactly once at 900, 902 and 901 ms, and fired **zero** times on page load, on the first poll, on recovery from UNAVAILABLE, and on the first request after a reset. Under `prefers-reduced-motion: reduce` the slide and cross-fade go instant and the white ring becomes persistent for 2001 ms.
- **No scrollbar exists in any state.** `document.body.scrollHeight === window.innerHeight` at 1920x1080 was verified in NORMAL with 8 rows, in NORMAL with 7 rows plus a boundary, in NO TRAFFIC YET, in UNAVAILABLE, and with the EVIDENCE CLEARED overlay up.
- **The rem scale is live.** `getComputedStyle(documentElement).fontSize` reads `10.6667px` at 1280 wide, so the `calc(100vw / 120)` form was accepted rather than silently dropped — the bug that looks correct on a 1920 projector and nowhere else.
- **Zero dependencies entered the phase.** No `package.json`, no framework, no icon set, no font file, no remote origin. `sh scripts/smoke.sh` still reports `--- 94 passed, 0 failed ---` and `sh scripts/smoke.sh proxy` still reports `--- 17 passed, 0 failed ---`.

## Task Commits

1. **Task 1: The page shell, the dual reading, and the poll with its watchdog** — `5e4ffbf` (feat)
2. **Task 2: The recent-requests table and the stats rail** — `3c222e8` (feat)
3. **Task 3: The four states, the convergence sequence, and the evidence-cleared overlay** — `f531c7c` (feat)

## Files Created

- **`status/index.html`** (new, 710 lines) — one file, inline `<style>` and `<script>`, zero external references. Tokens and both UI-SPEC font stacks verbatim; the root scale hook as the one permitted form; a grid page root whose rows sum to exactly `100vh`; the config strip, sync marker, traffic banner, evidence row and footer band; a five-fixed-column table with a server-positioned boundary object; a three-tile stats rail with tabular numerals; a 1000 ms `fetch` poll with a 5000 ms watchdog and a 3000 ms stale footer; the four states; the cancellable convergence sequence; and the fixed-position evidence-cleared overlay.

## Decisions Made

- **The uniform row height ships at 52px, not 68px.** See deviation 1 — UI-SPEC's own vertical numbers do not sum, and the no-scrollbar invariant outranks the derived row-height figure. Uniformity, which is what the boundary rule's pixel position actually depends on, is preserved exactly: every rendered row reports the same `offsetHeight`.
- **The table's edge bar is white, not accent.** UI-SPEC specifies both "row fill is the full-width accent" and "edge bar: solid accent fill", which together render the bar invisible and delete the shape channel. Since OLD and NEW are isoluminant, the shape channel is mandatory rather than decorative, so the bar is white — 19.2:1 against the ground, high contrast against both accents, and it survives greyscale.
- **The convergence sequence is cancellable.** A guard alone cannot suppress the flash during `flip.sh old`, because that script performs a genuine flip to OLD and only truncates the evidence afterwards. The page tears the sequence down the moment it recognises the reset instead.
- **Two error-copy strings were added** for the `proxy` and `status` failing sources. The copywriting contract enumerates only log, config and both, but 02-02 emits `proxy`, and the client watchdog needs a `status` case. Both follow the contract's voice exactly and keep `Not showing a stale reading.` verbatim.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] UI-SPEC's vertical budget does not sum to 1080px**

- **Found during:** Task 1 (layout), surfaced again in Task 2
- **Issue:** The document simultaneously requires a 48px safe area, a 152px config strip, a 40px sync marker in a 64px gap, a 396px traffic banner containing a 200px Hero, a 308px evidence row containing **8 rows at 68px** plus a header, and a footer — on a frame it also declares must never scroll. The table alone needs ~592px against the 308px it is allotted, and the minimum honest stack comes to roughly **1267px against 1080px**. The stats rail is inconsistent in the same way: three tiles of 108+108+92 exactly fill 308px, leaving nothing for the 32px padding the same section specifies.
- **Fix:** Preserved the invariants that carry meaning — no scrollbar, the 200px Hero and its 2.8x dominance, the 8-row window, the 48px safe area, the `1176 / 48 / 600` evidence columns and the five fixed table column widths — and absorbed the shortfall in the row height (68px -> 52px) and the band heights. The shipped stack is 48 / 112 / 16 / 40 / 8 / 296 / 24 / 488 / 48 = exactly 1080px. The 68px reference value is recorded in a comment beside the token.
- **Files modified:** `status/index.html`
- **Verification:** `document.body.scrollHeight === window.innerHeight` at 1920x1080 in all four states, with 8 rows and with 7 rows plus a boundary; every row reports an identical `offsetHeight` of 52
- **Committed in:** `5e4ffbf`, `3c222e8`

**2. [Rule 1 - Bug] The watchdog overwrote the footer's `served_at` between polls**

- **Found during:** Task 2 (first live DOM probe)
- **Issue:** The 250 ms watchdog re-rendered the footer from a synthetic object with `served_at: null`, so the footer read `updated —` permanently even while the service was perfectly healthy. The one element whose whole job is to prove the page is not frozen was itself displaying nothing.
- **Fix:** The watchdog re-renders the footer from the last good payload, so only the age reading moves between polls.
- **Files modified:** `status/index.html`
- **Verification:** live probe reads `updated 09:22:33 · src /var/log/demo/access.log ·` with the heartbeat glyph alternating
- **Committed in:** `3c222e8`

**3. [Rule 1 - Bug] The empty and error copy sat at the top of the table panel instead of centred**

- **Found during:** Task 3 (screenshot review of the UNAVAILABLE and EVIDENCE CLEARED states)
- **Issue:** `.tbody` had no flex growth, so the centring on the empty-state block had no height to centre within. UI-SPEC specifies the empty-state copy centred, and top-aligned error copy under a header row reads as a truncated table rather than as a deliberate message.
- **Fix:** `.tbody { flex: 1 1 auto; }` — real rows still stack from the top, the empty and error blocks now centre.
- **Files modified:** `status/index.html`
- **Verification:** re-captured screenshots of both states
- **Committed in:** `f531c7c`

**4. [Rule 2 - Missing critical] The copywriting contract has no error body for two failing sources that actually occur**

- **Found during:** Task 3
- **Issue:** The contract enumerates error bodies for log, config and both. 02-02's most common real failure emits `failing_source: "proxy"`, and the client watchdog's own case is `status`. Falling back to the log-unreadable copy would have printed a sentence that is factually wrong on the projector.
- **Fix:** Added `Cannot reach the proxy. Not showing a stale reading.` and `Cannot reach the status service. Not showing a stale reading.` — same flat instrumentation voice, load-bearing sentence verbatim.
- **Files modified:** `status/index.html`
- **Verification:** driven live via `docker compose stop proxy`; the rendered copy names the proxy and prints `http://proxy:8081/nginx-health — not answering` beneath it
- **Committed in:** `f531c7c`

**5. [Rule 2 - Missing critical] The convergence sequence needed a cancellation path, not just a guard**

- **Found during:** Task 3
- **Issue:** `flip.sh old` issues a real confirming request on OLD **before** truncating the evidence, so the traffic reading genuinely changes for a few hundred milliseconds and a poll can land inside that window. The guard the plan specifies cannot suppress this, because nothing distinguishes it from a real flip at the moment it happens.
- **Fix:** The sequence is cancellable — recognising the reset clears its timers, removes the ring and repaints the banner, so no convergence ever completes across a reset.
- **Files modified:** `status/index.html`
- **Verification:** measured across three reset cycles (see "Issues Encountered")
- **Committed in:** `f531c7c`

---

**Total deviations:** 5 auto-fixed (2 bugs, 2 missing-critical, 1 blocking)
**Impact on plan:** No change to the API contract, the architecture or the file inventory. Deviation 1 is a genuine internal contradiction in the design contract, resolved in favour of the invariant the contract itself calls non-negotiable.

## Authentication Gates

None — nothing in this plan touches an authenticated service.

## Issues Encountered

- **Two of the plan's acceptance criteria are, as written, unsatisfiable.** Both are transcription problems in the criteria rather than defects in the contract they are trying to enforce, and the substance of each was verified with a corrected check:
  1. `grep -ci '#ef4444\|#dc2626\|red' status/index.html` is 0 **and** `grep -c 'prefers-reduced-motion' status/index.html` is at least 1 cannot both hold: the mandated string contains the substring `red`. Verified instead as `grep -ci '#ef4444\|#dc2626'` == 0 plus an audit that no colour keyword `red` is used in any declaration — **both pass**.
  2. `grep -oE 'https?://[^"' \'' )]+' | grep -vc 'localhost'` is 0 conflicts with the copywriting contract's mandatory empty-state body, `Send a request to http://app.demo.test:9092/ and it will appear here.` UI-SPEC wins on disagreement, so the copy ships verbatim and the check was run as "zero `src`/`href` to any remote origin, and zero absolute URLs other than localhost and the demo host" — **passes**. `app.demo.test` is the D-22 demo hostname, not an external origin.
- **`flip.sh old` fires the convergence sequence 1 time in 3, not 0.** Measured across three consecutive reset cycles: the money shot fired once every time at 900/902/901 ms; the reset fired 0, 0 and 1 times. The cause is upstream and structural — `flip.sh` performs a real confirming request on OLD and truncates the evidence roughly a second later, so whether a poll lands in that window is a race. The page-side cancellation removes the flash whenever the poll cadence allows, but cannot make the criterion deterministic. The one-line structural fix lives in `scripts/flip.sh`, which is owned by 02-01 and outside this plan's `files_modified`, so it is logged to `deferred-items.md` (item D1) rather than fixed here.
- **The 12px edge-bar cap is small.** It renders correctly and survives greyscale, but whether the square-versus-chamfer distinction resolves at 10 m is a question for the 02-04 visual audit. It is reinforcement only — the word, the rail position and the boundary rule each carry the OLD/NEW signal independently.

## Known Stubs

None. Every reading on the page is driven by a real key from `/api/status`; nothing is hardcoded, mocked or placeheld.

## Threat Flags

None. This plan introduces no network endpoint, no auth path, no file access and no schema change. The one trust boundary it touches — evidence log to rendered DOM — is the `T-02-01` mitigation it was written to implement, and that mitigation is asserted both by a zero-count grep and by a live payload test.

## Verification Results

| Check | Result |
|-------|--------|
| `sh scripts/smoke.sh` (all four sections) | `--- 94 passed, 0 failed ---` |
| `sh scripts/smoke.sh proxy` (Phase 1 regression guard) | `--- 17 passed, 0 failed ---` |
| `curl -sS -o /dev/null -w '%{http_code}' http://localhost:9094/` | `200`, body is HTML |
| `grep -c 'innerHTML' status/index.html` | `0` (also `0` on the served body) |
| `grep -c 'textContent' status/index.html` | 15 |
| Live injection: `/x%3Cscript%3Ealert(1)%3C/script%3E` | renders as literal text; 0 script elements in the table; 0 dialog events |
| `grep -c '100vw / 120'` / `'100vw / 1920'` | `1` / `0` |
| Root scale at 1280 wide (UI-SPEC test 11) | `10.6667px` |
| `document.body.scrollHeight === window.innerHeight` @1920x1080 | `true` in all four states, with and without a boundary |
| Token audit | 4 font sizes, 2 font weights (400/700), 0 accent-as-`color`/`border` |
| External origins | 0 `@font-face`, 0 hosted-stylesheet references, 0 remote `src`/`href` |
| Kill test (UI-SPEC 4) | `docker compose stop proxy` -> UNAVAILABLE within 5 s, desaturated, hazard-bordered, all readings blanked; restart restores NORMAL |
| Partial failure (UI-SPEC 13) | asserted server-side by 02-02; the page renders `state` only, so a half-lit page is unreachable by construction |
| Four-state test (UI-SPEC 5) | screenshots captured for all four; pairwise distinguishable with no caption |
| Greyscale test (UI-SPEC 1) | active backend and boundary both still readable; the two fills are identical grey, as predicted |
| Convergence test (UI-SPEC 6) | fires once per real flip at 900/902/901 ms; 0 on load, first poll, recovery, first request after reset |
| Reduced-motion test (UI-SPEC 9) | persistent white ring measured at 2001 ms |
| Boundary rendering | exactly one `.bnd` element; 3 rows above matching `boundary.row_index` of 3; 7 request rows with a boundary present |
| Path truncation | a 62-character path renders as 28 characters ending in an ellipsis; all rows report an identical `offsetHeight` |
| Evidence-cleared overlay | appears once with the verbatim copy, hides after ~10 s, `scrollHeight` unchanged throughout |

Final state: five services up and healthy, selector on **OLD**, evidence cleared by the closing `flip.sh old`, `GET /` serving the page, working tree clean apart from an orchestrator-owned `.planning/config.json` flag.

## Next Phase Readiness

**Ready for 02-04 (smoke and README completion, plus the visual audit).**

- The page is served from the existing read-only `./status:/app:ro` mount, so no compose change and no restart were needed and none are pending.
- The mechanical half of UI-SPEC's thirteen acceptance tests is verified above. The remaining half is projector-distance judgment: tests 3 (distance) and the venue-overscan assumption UI-SPEC itself marks unresolved, plus the edge-bar cap question raised under "Issues Encountered".
- `deferred-items.md` item **D1** proposes a one-line change to `scripts/flip.sh` that would make the "reset fires zero convergences" criterion true by construction rather than probabilistically. 02-04 owns `scripts/smoke.sh` and is the natural place to decide it.
- Two acceptance criteria in `02-03-PLAN.md` are self-contradictory as written (see "Issues Encountered"); if the plan is ever re-run, they should be corrected rather than re-litigated.

No blockers.

## Self-Check: PASSED

`status/index.html` verified present on disk (710 lines). All three commits (`5e4ffbf`, `3c222e8`, `f531c7c`) verified present in git history.

---
*Phase: 02-the-live-http-cutover*
*Completed: 2026-07-21*

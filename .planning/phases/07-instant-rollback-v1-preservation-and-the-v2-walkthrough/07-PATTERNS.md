# Phase 7: Instant Rollback, v1 Preservation, and the v2 Walkthrough - Pattern Map

**Mapped:** 2026-07-22
**Files analyzed:** 6 (2 new smoke sections, 1 dispatch/all wiring edit, 1 smoke section rewrite, 1 doc rewrite, 1 possible Makefile edit)
**Analogs found:** 6 / 6 (every artifact has an in-repo analog; one is role-match only)

All work lives in one repo of pre-existing house idioms. There is **no new mechanism** — every excerpt below is copy-from-existing, not invent.

## File Classification

| New / Modified File | Role | Data Flow | Closest Analog | Match Quality |
|---------------------|------|-----------|----------------|---------------|
| `scripts/smoke.sh` → new `section_rollback` (VAL-03 + VAL-04) | test (destructive integration) | request-response + flip-cycle | `section_cutover` (smoke.sh:381-499+), esp. CUT-05 flip-cycle (453-463) + D-35 shasum (477-488); SSH capture from `section_validate` VAL-02 (1178-1205) | exact (idioms exist, recombined) |
| `scripts/smoke.sh` → new `section_preserve` (MIG-03) | test (non-destructive static) | read-only assertion | `section_validate` non-destructive header + precondition style (smoke.sh:1137-1161) | role-match (no git-assertion analog exists) |
| `scripts/smoke.sh` → dispatch `case` + `all` chain | config/wiring | dispatch | existing `case`/`all` block (smoke.sh:2332-2370) | exact |
| `scripts/smoke.sh` → `section_walkthrough` UPDATE (v2 beats) | test (doc lint / executable contract) | transform (extract + assert) | **the section itself** (smoke.sh:1821-2036) — change its own hard-coded constants | self (edit in place) |
| `WALKTHROUGH.md` REWRITE (v2 narrative) | doc | presenter script | **the current `WALKTHROUGH.md`** (per-beat Run/Expect/Say + preflight + traps) | self (rewrite same skeleton) |
| `Makefile` → possible `proxies-untouched` (+ any rollback presenter target) in `.PHONY` | config | — | existing presenter targets `verify-new-stack`/`contrast`/`reload` + `.PHONY` line (Makefile:12, 89-101, 139-140) | role-match |

**CRITICAL LOCKSTEP PAIRING:** `section_walkthrough` (smoke.sh:1821-2036) and `WALKTHROUGH.md` are **one atomic change**. The section hard-codes the v1 8-beat contract as an executable lint. Rewriting the doc without updating the section's constants turns `make test` red instantly (see Shared Pattern: The Walkthrough Lockstep). The planner MUST assign both to the same task.

---

## Pattern Assignments

### `section_rollback` — VAL-03 + VAL-04 (test, destructive, one flip cycle)

**Analog:** `section_cutover` (smoke.sh:381-499), plus SSH capture from `section_validate` (smoke.sh:1178-1205).

Combine VAL-03 (rollback lands both protocols OLD, no teardown) and VAL-04 (proxy configs byte-identical, proxies never touched) into **one flip cycle** (flip new → flip old), capturing state at three points.

**1. Destructive-section discipline — copy the trap/restore idiom verbatim** (smoke.sh:316-321, 374-379):
```sh
restore_flip_state() {
	_flipbak=$(mktemp)
	cp switch/active-proxy.conf "$_flipbak"
	trap 'cp "$_flipbak" switch/active-proxy.conf; docker compose up -d server-old server-new switch proxy-old proxy-new status >/dev/null 2>&1; docker compose exec -T switch nginx -s reload >/dev/null 2>&1; rm -f "$_flipbak"; exit 1' INT TERM
	trap 'cp "$_flipbak" switch/active-proxy.conf; docker compose up -d server-old server-new switch proxy-old proxy-new status >/dev/null 2>&1; docker compose exec -T switch nginx -s reload >/dev/null 2>&1; rm -f "$_flipbak"' EXIT
}
```
Call `restore_flip_state` at section top; call `finish_flip_state` (smoke.sh:374-379) at the end once the rig is back on OLD under its own power.

**2. The flip cycle + settle — copy from CUT-05** (smoke.sh:284-310 for `settle_flip`, 453-460 for the cycle):
```sh
sh scripts/flip.sh old >/dev/null 2>&1; settle_flip old
sh scripts/flip.sh new >/dev/null 2>&1; settle_flip new   # THE CUTOVER
sh scripts/flip.sh old >/dev/null 2>&1; settle_flip old   # THE ROLLBACK (VAL-03)
```
`settle_flip <target>` polls the :8081 oracle + 200 ms margin — never re-derive the wait.

**3. No-teardown proof — copy the CUT-05 StartedAt idiom verbatim** (smoke.sh:453-463), extend the id list to include the two static proxies:
```sh
_ids=$(docker compose ps -q switch server-old server-new proxy-old proxy-new)
_started_before=$(echo "$_ids" | xargs docker inspect -f '{{.State.StartedAt}}' 2>/dev/null)
# ... flip new, settle, flip old, settle ...
_started_after=$(echo "$_ids" | xargs docker inspect -f '{{.State.StartedAt}}' 2>/dev/null)
assert "VAL-03/04 no container restarted across cutover+rollback (StartedAt unchanged)" \
	"test -n '$_started_before' && test '$_started_before' = '$_started_after'"
```

**4. Config-checksum equality — copy the D-35 `shasum` idiom** (smoke.sh:478-488), upgrade `shasum` → `shasum -a 256` (VAL-04 criterion says sha256; `sha256sum` is absent on stock macOS), and target the two static proxy configs:
```sh
_sha_before=$(shasum -a 256 proxy-old/nginx.conf proxy-new/nginx.conf | awk '{print $1}')
# capture again as _sha_mid (after flip-new) and _sha_after (after flip-old)
assert "VAL-04 static proxy configs byte-identical before==after-flip==after-rollback" \
	"test '$_sha_before' = '$_sha_mid' && test '$_sha_mid' = '$_sha_after'"
```
Note the existing D-35 assertion already uses exactly `shasum ... | awk '{print $1}'` and `test -n '$x' && test '$x' = '$y'` — match that shape.

**5. Worker-PID-unchanged (proves not even a reload reached the proxies)** — extend the StartedAt idea one level (RESEARCH Pitfall 5; A2 flags verifying `pgrep` in nginx:alpine in-task):
```sh
_pw_before=$(docker compose exec -T proxy-old pgrep -f 'nginx: worker'; docker compose exec -T proxy-new pgrep -f 'nginx: worker')
# ... after the cycle ...
assert "VAL-04 static proxy workers never respawned (proxies not even reloaded)" \
	"test -n '$_pw_before' && test '$_pw_before' = '$_pw_after'"
```

**6. Both-protocols-OLD after rollback — HTTP copy from CUT-02/03** (smoke.sh:444-445), SSH **copy the non-piped capture idiom verbatim from VAL-02** (smoke.sh:1178-1205; also the export at 1155):
```sh
export SSH_OPTS="-o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
assert "VAL-03 after rollback: ssh app.demo.test banner -> OLD server-old (non-piped capture)" \
	'out=$(docker compose exec -T client timeout 10 ssh $SSH_OPTS demo@app.demo.test true 2>&1)
	 rc=$?
	 test "$rc" -eq 0 && printf "%s\n" "$out" | grep -qx "OLD server-old"'
```
**Delta / hazard (RESEARCH Pitfall 4):** ssh assignment via `$(...)` with `2>&1`, read `$?` on the very next line, grep the captured variable — **never** put ssh on the left of a pipe. This is TEST mode (`UserKnownHostsFile=/dev/null`), matching `section_ssh`/VAL-02, NOT presenter mode.

**Placement:** in the `all` chain, after `section_ssh`, before `section_walkthrough`/`section_hostkey` (it is destructive; leaves rig on OLD, the precondition the next reader expects).

---

### `section_preserve` — MIG-03 (test, non-destructive, git plumbing)

**Analog:** `section_validate`'s non-destructive header + standalone-precondition style (smoke.sh:1137-1161). **No exact git-assertion analog exists in the suite — this is role-match.** Copy the *style* (read-only, `echo "--- preserve ---"`, `assert` one-liners), invent the git-plumbing conditions.

**Non-destructive style to copy** (smoke.sh:1137-1147):
```sh
# NON-DESTRUCTIVE by construction: this section only READS. It never flips the
# selector and installs NO restore trap, because it disturbs nothing to restore.
section_preserve() {
	echo "--- preserve ---"
```

**Assertions (RESEARCH §Pattern 2, all read-only git plumbing — never `git checkout` inside the suite):**
```sh
assert "MIG-03 the v1.0 tag exists" \
	'git rev-parse -q --verify refs/tags/v1.0'
assert "MIG-03 v1.0 preserves the single-proxy topology (one 'proxy' service, no switch)" \
	'git show v1.0:compose.yaml | grep -qE "^  proxy:" && ! git show v1.0:compose.yaml | grep -qE "^  switch:"'
assert "MIG-03 v1.0 ships the preserved proxy config and flip include" \
	'git cat-file -e v1.0:proxy/nginx.conf && git cat-file -e v1.0:proxy/active-backend.conf'
assert "MIG-03 v1.0 Makefile brings it up standalone (has an 'up:' target)" \
	'git show v1.0:Makefile | grep -qE "^up:"'
```
**Anti-pattern to avoid:** `git checkout v1.0` in-suite dirties the working tree mid-run. Assert *content* via `git show`/`git cat-file` only.

**Placement:** pure reader — place early in the `all` chain (before the destructive sections). It touches no rig state.

---

### Dispatch `case` + `all` chain wiring (config)

**Analog:** the existing block at smoke.sh:2332-2370 (exact).

Copy the two existing patterns. Add case arms:
```sh
rollback) section_rollback ;;
preserve) section_preserve ;;
```
And in `all`, mirror the existing ordering comments (smoke.sh:2342-2365): insert `section_preserve` early (pure reader, cheap-fail-first alongside `section_walkthrough`), and `section_rollback` after `section_ssh` / before `section_walkthrough` and `section_hostkey` (destructive, leaves rig on OLD). Update the usage string at smoke.sh:2367 to list `rollback|preserve`.

---

### `section_walkthrough` UPDATE (test / executable contract) — LOCKSTEP with WALKTHROUGH.md

**Analog: the section itself** (smoke.sh:1821-2036). Do not restructure it — change only the hard-coded v1 expectation constants to the final v2 beat list. The extraction machinery (awk over ```bash fences, `.PHONY` target check, path resolution, prereq closure, Run/Expect/Say order) is generic and stays. **Change exactly these:**

**Step count** (smoke.sh:1993-1996) — currently 8:
```sh
assert "WALK-01 the document carries eight numbered step headings" \
	'test "$WT_STEPS" = "8"'
assert "WALK-01 the step headings are numbered 1..8 in ascending order" \
	'test "$WT_NUMSEQ" = "1 2 3 4 5 6 7 8 "'
```
Delta: set to the chosen v2 count (RESEARCH proposes ~9-10; planner locks it). Update both the number word in the label, the `WT_STEPS` value, and the `WT_NUMSEQ` string.

**Narrative keyword matcher + order assertion** (smoke.sh:1908-1918 = the awk keyword map; 1997-1998 = the order assertion):
```sh
WT_NARRATIVE=$(grep -E '^### [0-9]+\.' "$WT" ... | awk '
	/show old/          { printf "show-old ";          next }
	/redirect contrast/ { printf "redirect-contrast "; next }
	/prime/             { printf "prime ";             next }
	/the flip/          { printf "flip ";              next }
	/gotcha/            { printf "gotcha ";            next }
	/wrong fix/         { printf "wrong-fix ";         next }
	/right fix/         { printf "right-fix ";         next }
	/reset/             { printf "reset ";             next }
	                    { printf "UNKNOWN " }')
...
assert "WALK-01 the step headings appear in the fixed D-55 narrative order" \
	'test "$WT_NARRATIVE" = "show-old redirect-contrast prime flip gotcha wrong-fix right-fix reset "'
```
Delta: add keyword arms for the new v2 beats (e.g. `validate.*new.*stack` → `validate-new`, `roll ?back` → `rollback`, `never touched|untouched|checksum` → `proxies-untouched`), and set the expected `WT_NARRATIVE` string to the exact v2 sequence. Every heading must match exactly one arm (else `UNKNOWN`).

**Trap assertions** (smoke.sh:2008-2018) — five named-trap greps. Keep the ones that still hold (incognito/301, client+22, 9093-doesn't-follow-flip, `make reset`, `make verify` host-key-blind); add/adjust for any new v2 trap (RESEARCH Q3 candidate: `flip-old` is the reset direction that truncates the evidence log, Pitfall 3). Whatever traps ship in the doc must have a matching grep here.

**Do NOT touch:** the extraction awk (1833-1845), the `.PHONY` closure loop (1855-1863), prereq closure (1927-1949), the Run/Expect/Say order machinery (1892-1899), or the two reader-guards (2025-2033). Those enforce structure, not narrative — they carry forward unchanged.

**Non-vacuity floors** (smoke.sh:1967-1974): `WT_CMD_COUNT >= 8`, `WT_PATH_COUNT >= 3`, `WT_TRAP_LINES >= 10` — verify the v2 doc still clears them (it will; more beats = more commands).

---

### `WALKTHROUGH.md` REWRITE (doc) — LOCKSTEP with section_walkthrough

**Analog: the current `WALKTHROUGH.md`** — reuse its exact skeleton so the rewrite satisfies the lint and matches the house voice.

**Structural skeleton to preserve (what the lint reads):**
- Intro paragraph, then `## Pre-flight checklist` (WALK-01 requires it; names ≥3 `make` targets → WT_PREFLIGHT_COUNT; every `make` target used in a later step must be introduced here or in an earlier step — prereq closure).
- `## The demo`, then each beat as `### N. <title>` with the keyword the narrative matcher expects in the title.
- Every beat carries **Run → Expect → Say** in that exact order (WT_ORDER_BAD asserts the `RES` sequence per heading). Run commands go in ```bash fences (extracted as commands); transcribed output goes in plain ``` fences (NOT counted as commands).
- `## Known traps` at the end (WALK-03 requires it; ≥10 lines).

**Per-beat block shape to copy** (from WALKTHROUGH.md:58-79, beat 1):
```markdown
### 1. Show OLD — the proxied request

**Run**

```bash
make verify
```

**Expect** — ... transcript in a plain ``` fence ...

**Say** — "..."
```

**v2 narrative to write** (RESEARCH §Proposed Beat List, planner finalizes count/order): validate app-new stack (`make verify-new-stack`) → show OLD (`make verify`) → [optional contrast] → prime SSH (`make ssh`) → the flip (`make flip-new`) → host-key gotcha (`make ssh`) → the fix (`make fix-hostkeys` + `make ssh`) → instant rollback (`make flip-old` + `make verify`) → the old proxy was never touched (checksum command, e.g. `make proxies-untouched`) → reset (`make reset`).

**Deltas from v1 doc:**
- Every ```bash command must be a real `.PHONY` target (Makefile:12) or a real binary — if the rollback beat uses a new `make proxies-untouched`, add it to `.PHONY` first.
- Every referenced repo path (`` `...` `` ending .md/.sh/.conf/.yaml) must resolve. The v1 doc references `proxy/active-backend.conf` (v1 file) — v2 must reference `switch/active-proxy.conf` (RESEARCH State-of-the-Art table).
- No ellipsis / `<placeholder>` / TODO in any command block (WT_PLACEHOLDER assertion).
- Rollback beat narration (Pitfall 3): `make flip-old` truncates the evidence log and issues no confirming request — narrate a follow-up `make verify`, do NOT claim status-page counters the flip just zeroed.

---

### `Makefile` — possible new presenter target(s) (config)

**Analog:** existing presenter targets `verify-new-stack` (Makefile:139-140), `contrast` (89-93), `reload` (98-101), and the `.PHONY` declaration line (Makefile:12).

If beat 9 needs a real Run command, add a checksum presenter target following the `contrast` shape (`@echo` label + a real command with readable single-line output):
```makefile
proxies-untouched:
	@shasum -a 256 proxy-old/nginx.conf proxy-new/nginx.conf
```
**Delta (mandatory):** add any new target name to the `.PHONY` line (Makefile:12) — `section_walkthrough` (smoke.sh:1977) asserts every `make <target>` in the doc is declared in `.PHONY`. Omitting it turns the walkthrough lint red.

---

## Shared Patterns

### The Walkthrough Lockstep (cross-cutting — the critical coupling)
**Sources:** `WALKTHROUGH.md` (doc) ↔ `section_walkthrough` (smoke.sh:1821-2036, contract) ↔ `Makefile:12` (`.PHONY`).
**Apply to:** the doc-rewrite task as ONE atomic unit.
The lint binds the doc's beat count, numbering, keyword order, Run/Expect/Say order, referenced paths, command targets, and named traps. A doc change without the matching constant change in `section_walkthrough` fails `make test` immediately. The planner must define the final v2 beat list once and update **both** in the same task, plus add any new `make` target to `.PHONY`. Never execute extracted doc text (T-04-19 reader guard, smoke.sh:2032 — carries forward untouched).

### Destructive-section trap discipline
**Source:** `restore_flip_state`/`finish_flip_state` (smoke.sh:316-321, 374-379); mirrored by `restore_ssh_state`/`finish_ssh_state` (1121-1126) and section_hostkey (2298).
**Apply to:** `section_rollback` (it flips the selector). Install traps at section top, restore + `trap - EXIT INT TERM` on the way out, leave the rig on OLD.

### The StartedAt / shasum "nothing was touched" idiom
**Source:** CUT-05 (smoke.sh:453-463) + D-35 (477-488).
**Apply to:** `section_rollback` VAL-03/04. `docker inspect -f '{{.State.StartedAt}}'` for no-restart; `shasum -a 256 ... | awk '{print $1}'` for byte-identity; `test -n '$x' && test '$x' = '$y'` guards a non-empty capture. Use host-side `docker inspect` (D-29: no Docker socket mounted anywhere).

### The non-piped SSH capture idiom (TEST mode)
**Source:** VAL-02 (smoke.sh:1155, 1178-1205); `section_ssh`; `verify.sh`.
**Apply to:** any new SSH assertion in `section_rollback`. `out=$(... ssh $SSH_OPTS ... 2>&1)`, `rc=$?` on the next line, `grep -qx` the variable. Never ssh-on-left-of-pipe. TEST mode pins (`StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null`) — never presenter mode here (D-52).

## No Analog Found

| File / concern | Role | Data Flow | Reason |
|----------------|------|-----------|--------|
| `section_preserve` git-plumbing assertions | test | read-only | No existing section asserts over `git rev-parse`/`git show`/`git cat-file`. Style comes from `section_validate`; the git conditions are new (RESEARCH §Pattern 2). Role-match only. |

## Metadata

**Analog search scope:** `scripts/smoke.sh` (2373 lines), `WALKTHROUGH.md` (357), `Makefile` (210), `07-RESEARCH.md`.
**Files scanned:** 4.
**Pattern extraction date:** 2026-07-22.
**Key insight:** This phase is recombination, not invention. `section_rollback` = CUT-05 StartedAt + D-35 shasum + VAL-02 SSH capture, run over one flip cycle. `section_preserve` = section_validate style + read-only git plumbing. The real risk is the walkthrough lockstep, not new-code bugs.

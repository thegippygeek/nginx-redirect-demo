---
milestone: v1
audit_type: milestone-integration
audited: 2026-07-22T10:30:00Z
verdict: MILESTONE VERIFIED
core_value_end_to_end: true
phases_integrate: true
evidence_forms_aligned: 4
requirements_total: 33
requirements_spot_checked: 12
regressions: 0
rig_left_as: "selector on OLD, gotcha armed (fingerprints differ), client trust record clean, all five services healthy, source unmodified"
---

# Milestone v1 Audit — Server Migration Redirect Demo

**Scope:** Integration and intent audit of the assembled v1 (all four phases Complete).
Not a re-run of the per-phase verifications — a test that the *assembled whole* delivers
the Core Value end to end and that the four phases integrate against one live rig.

**Core Value under test:** *"A live, on-stage flip of the nginx upstream from old to new
where the client keeps hitting the same hostname and port, and unmistakably lands on the
new server."*

**Verdict:** the core value is real, driven live in one continuous run — not inferred.

---

## 1. Core value, end to end, in one continuous run

Driven as a presenter would, in order, against the running rig:

| Beat | Command (verbatim) | Result | Status |
|------|--------------------|--------|--------|
| Land on OLD, both protocols | `make verify` | `HTTP → OLD server-old` and `SSH demo@app.demo.test:22 → OLD server-old` | ✓ |
| Redirect contrast | `make contrast` | `9092` redirects=0 (URL kept); `9093` redirects=1 → `app.demo.test:9090` | ✓ |
| Prime SSH trust on OLD | presenter-mode ssh to `app.demo.test` | banner `OLD server-old`, trust recorded (md5 `76eeb648…`) | ✓ |
| **The flip — one word** | `make flip-new` | diff shows single `old`→`new` line change, `nginx -t` ok, graceful reload, `curl … → NEW server-new` | ✓ |
| Same commands land on NEW | `make verify EXPECT=new` | `HTTP → NEW server-new` **and** `SSH → NEW server-new` — **byte-identical commands** | ✓ |

The client changed nothing. One word in `proxy/active-backend.conf`, a graceful reload
(no container restart), and the identical `curl` and `ssh` invocations followed the flip
on **both** protocols. This is the money shot, and it fires.

## 2. The four phases integrate (not merely coexist)

Exercised against the *same* rig at the *same* time:

- **Status page follows the flip the SSH path also follows.** After `make flip-new`, the
  status API read `config: NEW | traffic: NEW | sync: IN_SYNC | counts {OLD:11, NEW:2}` —
  the same flip that `make verify EXPECT=new` observed on SSH.
- **`make verify` asserts both protocols agree** on every run, one labelled line each, and
  carries a distinct exit-3 for the "protocols disagree" case (`scripts/verify.sh` exits
  1/2/3; the smoke suite exercises the branch).
- **The host-key gotcha fires on the Phase-3 SSH path.** Primed on OLD → `make flip-new`
  → identical presenter-mode ssh returned **rc=255** with the exact
  `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!` banner ending on
  `Host key verification failed.`
- **The Phase-4 fix operates on that same path.** `make fix-hostkeys` transferred the keys
  and HUP'd the daemon (both backends then presented `SHA256:Lim1…`); the identical ssh
  command then returned **rc=0**, banner `NEW server-new`, with the client's `known_hosts`
  **byte-identical** (md5 unchanged, no `known_hosts.old`).
- **One selector, both contexts.** `proxy/nginx.conf`'s `stream` block listens on `:22`,
  proxies raw TCP to the active backend's `:22`, and `include`s the *same*
  `active-backend.conf` the `http` block reads. Genuine shared-selector integration, not
  two parallel mechanisms.

## 3. Four independent forms of evidence, all pointing at the same truth after a flip

| Evidence form | After flip to NEW | Status |
|---------------|-------------------|--------|
| Self-identifying backend banner | `/whoami` → `NEW server-new`; ssh banner → `NEW server-new` | ✓ |
| Live logs | proxy/backend access logs record backend=NEW; status counts NEW rising | ✓ |
| Status page | `CONFIG SAYS NEW` / `TRAFFIC SHOWS NEW`, `IN_SYNC` | ✓ |
| Verify script | `make verify EXPECT=new` → OK on both HTTP and SSH | ✓ |

All four agreed after the flip and all four agreed again after the restore to OLD.

## 4. Walkthrough executable against the assembled system

Spot-checked the commands `WALKTHROUGH.md` tells the presenter to run — `make verify`,
`make contrast`, `make ssh` (presenter mode), `make flip-new` / `make flip-old`,
`make fix-hostkeys` — all exist, run, and produce the documented behaviour against the
running rig. (Fresh-reader comprehension of the doc is owner-accepted per the brief and
not independently cold-read here.)

## 5. Constraints from PROJECT.md hold on the assembled system

| Constraint | Evidence | Status |
|------------|----------|--------|
| Runs entirely locally, no cloud account/cost | Only Docker Official Images; no SDK/registry creds; no `.env` | ✓ |
| One command brings it up | `docker compose up -d --wait` / `make up`; five services healthy | ✓ |
| Ports 9092 (HTTP) and 22 (SSH) | 9092 proxies; proxy `stream` listens on `:22` inside the network | ✓ |
| All published ports loopback-only | Every mapping bound `127.0.0.1:…`; **nothing** published on host `:22` | ✓ |
| No host state modified by the repo | No key material tracked in git; `/etc/hosts` line is hand-run text, never executed | ✓ |

## 6. No regression across the integration (sampled from every phase)

- **Phase 1:** `docker compose up` healthy; 9093 returns `301` + `Location: …:9090`;
  both backends self-identify (`OLD server-old` / `NEW server-new`);
  `nginx -V` shows `--with-stream`.
- **Phase 2:** live flip both directions; status page config/traffic/sync correct;
  `flip-old` clears evidence with no teardown.
- **Phase 3:** `stream` block on `:22` reading the shared selector; `make verify`
  reports both protocols with exit-code vocabulary 1/2/3.
- **Phase 4:** gotcha fires (255), fix succeeds (0), `known_hosts` byte-identical,
  gotcha re-armable.
- **Full suite on a settled rig:** `sh scripts/smoke.sh` → **231 passed, 0 failed**.

All 33 requirements remain consistent with live behaviour.

---

## Operational note (not a defect)

Running `sh scripts/smoke.sh` **while the rig was mid-take** from manual gotcha/fix
testing produced a transient `224 passed, 7 failed`. A settled re-run was immediately
`231 passed, 0 failed`. The suite expects an armed/settled starting rig and self-restores;
it is not designed to be run in the middle of a hand-driven take. Worth a one-line caution
for presenters — do not fire `make test` in the middle of a live take — but nothing in the
assembled system is broken.

---

## Verdict

## MILESTONE VERIFIED

The assembled v1 delivers its Core Value end to end in one continuous run: the same
hostname and ports, one word changed, a graceful reload, and the identical `curl` and
`ssh` commands land on the new server — with four independent forms of evidence agreeing,
and the migration-day host-key surprise staged and fixed on the very SSH path the cutover
travels. The four phases integrate against one live rig rather than merely coexisting.

**Rig left as required:** selector on OLD, gotcha armed (fingerprints differ), client
trust record clean, all five services healthy, source unmodified.

---
*Audited: 2026-07-22 · Milestone integration audit · Claude (gsd-milestone-auditor)*

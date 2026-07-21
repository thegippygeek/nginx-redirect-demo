# Phase 4: Host-Key Gotcha and the Presenter Walkthrough - Research

**Researched:** 2026-07-21
**Domain:** OpenSSH host-key trust lifecycle across a TCP proxy; Docker Compose state lifecycles; runnable presenter documentation
**Confidence:** HIGH — every load-bearing claim below was produced by running a command against the live stack in this session, not recalled.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-47 [AUTO]:** The mismatch is **already the default state and needs no staging work** — Phase 1 deliberately generates SSH host keys at container runtime rather than build time, so `server-old` and `server-new` have differed since day one. Phase 3's verifier reproduced `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!` live through the proxy. This phase's job is to make the failure *reachable on demand*, not to create it.
- **D-48 [AUTO]:** The client must **persist `known_hosts` across the flip** for the failure to fire. Phase 3 deliberately pins `-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no` on every assertion precisely so its tests would not trip over this. Phase 4 introduces a **second, deliberate connection mode** that uses a real `known_hosts` — the "presenter mode" — while leaving every Phase 3 assertion untouched.
- **D-49 [AUTO]:** The documented fix is **transferring `server-old`'s host keys to `server-new`**, not editing the client's `known_hosts`. `ssh-keygen -R` on the client is the WRONG fix and must be explicitly named as such in the walkthrough.
- **D-50 [AUTO]:** The fix is applied by a **`make` target** (e.g. `make fix-hostkeys`) that copies the keys and restarts sshd on the target. The underlying commands stay visible in the walkthrough.
- **D-51 [AUTO]:** The fix must be **reversible**, so the gotcha can be re-armed for the next take. `make reset` already rebuilds from scratch, which regenerates distinct keys — that is the re-arm path, and it should be stated explicitly.
- **D-52 [AUTO]:** Two explicit, named connection modes — **presenter mode** (real `known_hosts`, strict checking) and **test mode** (`UserKnownHostsFile=/dev/null`). The distinction must be visible in the README.
- **D-53 [AUTO]:** A **separate `WALKTHROUGH.md`**, not another README section.
- **D-54 [AUTO]:** Every step carries **three things**: the exact command, the output to expect, and the audience takeaway.
- **D-55 [AUTO]:** The narrative order is fixed: **show old → flip → show new → SSH gotcha → fix.** The 301-redirect contrast slots in before the flip.
- **D-56 [AUTO]:** The walkthrough includes a **pre-flight checklist** — `/etc/hosts` entry present, `make status` green, incognito window open, evidence cleared.
- **D-57 [AUTO]:** It also documents the **known traps**: browser 301 caching requiring incognito, the client-container prefix for SSH, that 9093 does not follow the flip, and that `make reset` is the re-arm path.

### Claude's Discretion

- The exact mechanism for persisting the client's `known_hosts` (named volume, bind mount, or a file inside the client image).
- Whether presenter mode is a separate `make` target, an env var, or a documented `ssh` invocation.
- How host keys are copied in `make fix-hostkeys` (docker cp, exec + tar, or a shared volume).
- Whether `WALKTHROUGH.md` also gets a printable/condensed cue-card form.

### Deferred Ideas (OUT OF SCOPE)

- A printable one-page cue card derived from `WALKTHROUGH.md` — nice, not required.
- Automated walkthrough playback with narration pauses — explicitly out of scope for v1 (PROJECT.md).
- Making the 9093 redirect follow the flip — still deliberately static.
- An SSH connection counter on the status page (Phase 3's D-46) — still deferred.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| KEY-01 | Demo can be run in a state where `server-new` has different SSH host keys from `server-old` | §Finding 1 — already the default; §Finding 6 documents the in-place re-arm that restores it in ~1 s |
| KEY-02 | After cutover in that state, the client's SSH attempt fails with `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED` | §Finding 3 — literal 13-line output captured, rc=255; §Finding 7 — the two preconditions that make it fire |
| KEY-03 | Presenter can apply a documented fix that transfers `server-old`'s host keys to `server-new` | §Finding 4 — six files, tar-over-exec, `kill -HUP`, 0.44 s measured end to end |
| KEY-04 | After the fix, SSH through the proxy to `server-new` succeeds with no client-side `known_hosts` edit | §Finding 4 + §Finding 5 — verified byte-identical `known_hosts` across the fix, *provided* `UpdateHostKeys=no` is pinned |
| WALK-01 | Written walkthrough documents the full narrative in order | §Finding 9 — structure; §Architecture Patterns Pattern 3 |
| WALK-02 | Each step lists exact command and expected output | §Finding 3, 4, 5, 8 — literal outputs captured for every failure and fix beat |
| WALK-03 | Walkthrough explains what the audience should conclude at each step | §Finding 9 — the three-block step shape; §Finding 4 note on the inherited `root@server-old` comment |
</phase_requirements>

## Summary

Phase 4 needs almost no new machinery. Every mechanism it requires is already present and was measured working in this session: the two backends already carry distinct host keys, the client container already writes a real `known_hosts` to `/root/.ssh/known_hosts` by default, and the whole failure-and-fix cycle runs in under a second. What the phase actually has to produce is (a) a **named presenter mode** — one `ssh` option set that is the exact complement of Phase 3's test-mode pins — (b) two `make` targets, one to apply the fix and one to re-arm it, (c) a smoke section asserting the deliberate failure, and (d) `WALKTHROUGH.md`.

The single most consequential finding is that **presenter mode needs no persistence mechanism at all**. The client container's own writable layer already holds `/root/.ssh/known_hosts`, and its lifecycle is *automatically* coupled to the backends' host-key lifecycle: any Compose operation that recreates the backends (and therefore regenerates their host keys) also recreates the client (and therefore clears its `known_hosts`). A named volume or a bind mount would **break** that coupling and cause the gotcha to fire at the wrong moment — before the flip, on the first connection after a plain `docker compose down && up`. This inverts the obvious instinct and is the answer to research questions 1 and 2 together.

The second consequential finding is a trap in KEY-04. OpenSSH 10's default `UpdateHostKeys=yes` rewrites `known_hosts` *by itself* on the first successful post-fix connection, appending the RSA and ECDSA host keys it learns from the server. Measured: the file went 95 bytes → 837 bytes and a `known_hosts.old` appeared, all without the presenter touching anything. An assertion of "`known_hosts` is byte-identical across the fix" therefore fails unless presenter mode pins `-o UpdateHostKeys=no`. With that pin, the file is provably unchanged (md5 identical, one readable line) and KEY-04 becomes mechanically assertable rather than a claim about presenter intent.

**Primary recommendation:** Define presenter mode as `-o StrictHostKeyChecking=accept-new -o UpdateHostKeys=no`, using the client container's default `known_hosts` with no new volume; implement `make fix-hostkeys` as tar-over-`compose exec` plus `kill -HUP $(cat /run/sshd.pid)`, and `make rearm` as `rm -f /etc/ssh/ssh_host_* && ssh-keygen -A && kill -HUP` on `server-new` plus clearing the client's `known_hosts`; assert the whole narrative as one destructive, trap-restored smoke section that doubles as the walkthrough's rot guard.

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Holding the client's trust record (`known_hosts`) | Client container writable layer | — | Trust is a *client* property. Its lifetime must equal the client container's, which is the only thing that keeps it in step with the backends' key lifetime (Finding 2) |
| Presenting a host key | Backend container (`sshd`) | — | The identity being asserted belongs to the machine answering, not to the proxy. The proxy is deliberately blind to it (Finding 3) |
| Relaying the key exchange untouched | Proxy (`stream` block) | — | Already true from Phase 3. The gotcha is *evidence* that the proxy is a true TCP relay: a Layer-7 device would terminate and re-present its own key |
| Applying the fix | Host-side orchestration (`make` + `docker compose exec`) | Backend container | Neither backend can reach the other's `/etc/ssh`; the Compose CLI is the only tier with both handles. This mirrors a real migration where an operator, not a server, moves the key material |
| Re-arming the gotcha | Host-side orchestration (`make`) | Backend container | Same reason. `ssh-keygen -A` runs *in* the backend but must be triggered from outside |
| The narrative script | Documentation (`WALKTHROUGH.md`) | Smoke suite | The document is authoritative for humans; the smoke section is authoritative for the machine. Finding 10 keeps them in step |

## Standard Stack

No new packages, images, or dependencies. Every tool the phase needs was verified present in the running stack.

### Core

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| OpenSSH client | `10.0p2` (Alpine 3.22, `client` container) | Presenter-mode `ssh`, `ssh-keygen -R` | Already installed by Phase 1's `client/Dockerfile` [VERIFIED: `docker compose exec client ssh -V`] |
| OpenSSH server | Alpine `openssh`, `sshd -D -e` under supervisord | Presents host keys; reloads them on SIGHUP | Already installed by Phase 1's `backend/Dockerfile` [VERIFIED: `pgrep -a sshd` on both backends] |
| `ssh-keygen -A` | bundled | Regenerates only *missing* host keys — the re-arm primitive | Already invoked in `backend/entrypoint.sh` [VERIFIED: reading the file + measured no-op over a restart] |
| BusyBox `tar` | bundled in both images | Streams the six key files between containers, preserving mode | Present in `nginx:1.30-alpine`; no install needed [VERIFIED: tar-over-exec pipe returned rc=0, modes preserved] |
| `docker compose exec -T` | Compose v2 | The only tier with a handle on both backends | Already the repo's universal idiom |

### Supporting

| Tool | Version | Purpose | When to Use |
|------|---------|---------|-------------|
| `DOCKER_CLI_HINTS=false` | env var, Compose v2 | Suppresses the trailing `What's next: … Gordon → docker ai …` block Docker prints after a **non-zero** `compose exec` in a TTY | On every walkthrough command that is *expected* to fail. See Pitfall 5 |
| `make` | GNU Make 3.81 (macOS) | `fix-hostkeys`, `rearm`, `ssh` targets | Repo already pinned to 3.81 syntax — no 4.x features, tab-indented recipes, doubled `$$` |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `known_hosts` in the client's container layer | A named volume `demo-known-hosts` | Survives `docker compose down`, so a plain `down && up` leaves a stale key against freshly-generated backend keys → **gotcha fires before the flip**. Rejected; see Finding 2 |
| `known_hosts` in the client's container layer | A host bind mount | Survives even `down -v`, so `make reset` would not re-arm; also writes host state, which the project prohibits. Rejected outright |
| tar-over-`compose exec` | `docker cp` via a host temp dir | Two commands plus a temp path, writes key material to the host filesystem (violates T-03-01's spirit), and `docker cp` needs raw container names rather than Compose service names. Rejected |
| tar-over-`compose exec` | A third shared named volume for host keys | Would make the two backends share keys *permanently*, destroying KEY-01. Rejected |
| `kill -HUP` | `supervisorctl restart sshd` | HUP is measured as sufficient (Finding 4), preserves the sshd PID, and does not disturb supervisord's process accounting. `restart` also works but is louder on screen and drops in-flight sessions |
| `-o StrictHostKeyChecking=accept-new` | plain default (`ask`) | Default prompts `Are you sure you want to continue connecting (yes/no/[fingerprint])?` on the first connect — dead air on stage, and it **hangs forever** with no TTY or fails outright with a piped stdin. `accept-new` records silently on first sight and still hard-fails on a *changed* key. See Finding 8 |

**Installation:** none. `git diff` for this phase should touch no Dockerfile package line.

## Package Legitimacy Audit

**Not applicable.** This phase installs no external packages in any ecosystem. Every binary it uses (`ssh`, `ssh-keygen`, `sshd`, `tar`, `kill`) is already present in images pinned by earlier phases (`alpine:3.22`, `nginx:1.30-alpine`). Verified by reading `client/Dockerfile` and `backend/Dockerfile` and by executing each tool in the running containers.

**Packages removed due to [SLOP] verdict:** none
**Packages flagged as suspicious [SUS]:** none

## Architecture Patterns

### System Architecture Diagram

```
                        ┌───────────────────────────────┐
  make ssh / make       │  make fix-hostkeys            │
  fix-hostkeys /        │  make rearm                   │
  make rearm            │  (host-side orchestration —   │
        │               │   the only tier holding a     │
        │               │   handle on BOTH backends)    │
        │               └───────┬───────────────┬───────┘
        │                       │               │
        │             tar -cf - │      tar -xf -│ + kill -HUP
        ▼                       │               │
┌───────────────┐               │               │
│  client       │               ▼               ▼
│  container    │        ┌─────────────┐  ┌─────────────┐
│               │        │ server-old  │  │ server-new  │
│ /root/.ssh/   │        │             │  │             │
│  known_hosts  │        │ /etc/ssh/   │  │ /etc/ssh/   │
│  (writable    │        │ ssh_host_*  │  │ ssh_host_*  │
│   layer —     │        │  ▲          │  │  ▲          │
│   NOT a       │        │  │ generated│  │  │ generated│
│   volume)     │        │  │ at ENTRY-│  │  │ at ENTRY-│
└───────┬───────┘        │  │ POINT    │  │  │ POINT    │
        │                └──┼──────────┘  └──┼──────────┘
        │  ssh demo@app.demo.test:22          │
        │                   │                 │
        ▼                   │                 │
┌───────────────────────────┴─────────────────┴───────────┐
│  proxy — nginx stream { listen 22; proxy_pass $active_  │
│  backend; }                                             │
│                                                         │
│  RAW TCP. The proxy never sees, terminates, caches or   │
│  rewrites the host key. That is exactly WHY the gotcha  │
│  reaches the client — and is the phase's best evidence  │
│  that this is a Layer-4 relay, not a Layer-7 device.    │
└───────────────────────┬─────────────────────────────────┘
                        │
              include ./proxy/active-backend.conf
                        │
                 ┌──────┴──────┐
                 │ default old │  ← the one word `make flip` rewrites
                 └─────────────┘

DECISION POINT — which of the two mutually exclusive modes the ssh
invocation is in decides whether the gotcha is reachable at all:

  presenter mode  -o StrictHostKeyChecking=accept-new
                  -o UpdateHostKeys=no
                  (default UserKnownHostsFile = /root/.ssh/known_hosts)
                  → trust is REMEMBERED  → gotcha FIRES

  test mode       -o StrictHostKeyChecking=no
                  -o UserKnownHostsFile=/dev/null
                  (all 186 existing assertions + verify.sh)
                  → trust is DISCARDED   → gotcha CANNOT fire
```

### Recommended Project Structure

```
WALKTHROUGH.md          # NEW — the runnable script (D-53)
README.md               # gains: pointer to WALKTHROUGH.md + the two-modes section (D-52)
Makefile                # gains: ssh, fix-hostkeys, rearm
scripts/
├── smoke.sh            # gains: section_hostkey (destructive, trap-restored)
├── fix-hostkeys.sh     # NEW — recipe body lives in a script, per the flip/verify precedent
└── rearm.sh            # NEW — same reason
```

Putting the recipe bodies in `scripts/` rather than in the Makefile follows the precedent set for `flip` and `verify`, and for the same stated reason: Make 3.81 without a one-shell directive runs every recipe line in its own shell, and both sequences need early exits.

### Pattern 1: Presenter mode as an *option set*, not a mechanism

**What:** Presenter mode is defined entirely by two `ssh` options. It introduces no volume, no mount, no config-file change, and no new file in the client image.

```sh
# The presenter-mode option set. Note it is the exact COMPLEMENT of Phase 3's
# test-mode pins, and that is the whole point: test mode discards trust so the
#186 routing assertions cannot trip over a host-key change; presenter mode
# REMEMBERS trust so the change is the only thing you see.
#
#   accept-new     records an unseen host silently (no TOFU prompt, no dead air)
#                  but STILL hard-fails on a CHANGED key — measured, rc=255.
#   UpdateHostKeys=no
#                  OpenSSH >= 8.5 defaults this to `yes`, which rewrites
#                  known_hosts by itself on the first successful post-fix
#                  connection. Without this pin KEY-04's "no client-side edit"
#                  claim is unassertable. Measured: 95 -> 837 bytes.
PRESENTER_OPTS="-o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o UpdateHostKeys=no"
```

**When to use:** every walkthrough beat; the new smoke section. Never in `verify.sh` and never in `section_ssh`.

**Why the pins are safe:** command-line `-o` outranks `~/.ssh/config`, and Phase 3's assertions already carry their own explicit `-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no`. Nothing in `section_ssh` or `verify.sh` needs to change. Confirmed empirically: with the gotcha fully armed and presenter mode failing rc=255, `sh scripts/verify.sh new` still printed `OK  both protocols report NEW` and exited 0.

### Pattern 2: The fix as a stream, not a staging directory

```sh
# scripts/fix-hostkeys.sh (core)
#
# Six files, not three: sshd offers ed25519, rsa and ecdsa, and a client that
# has recorded more than one of them will object to whichever it negotiates.
# tar preserves 0600/0644 and root ownership, so no chmod is needed afterwards.
# No pipe hazard here — tar's exit status is what we want, and the ssh
# prohibition from Phase 3 is about `ssh | …`, not about `tar | tar`.
docker compose exec -T server-old tar -C /etc/ssh -cf - \
    ssh_host_ed25519_key ssh_host_ed25519_key.pub \
    ssh_host_rsa_key     ssh_host_rsa_key.pub \
    ssh_host_ecdsa_key   ssh_host_ecdsa_key.pub \
  | docker compose exec -T server-new tar -C /etc/ssh -xf -

# sshd loads host keys ONCE, at startup, and holds them in memory. Copying the
# files changes nothing until it is told. Measured: an ssh attempt made between
# the copy and the signal still produced the mismatch.
docker compose exec -T server-new sh -c 'kill -HUP $(cat /run/sshd.pid)'
```

### Pattern 3: The three-block walkthrough step (D-54)

Every step is three fenced blocks under one heading, always in the same order, so a presenter can find the one they need by position rather than by reading:

```markdown
### 4. The gotcha  ⚠ DESTRUCTIVE — needs `make rearm` before the next take

**Run**
```bash
make ssh
```

**Expect** — 13 lines, exit code 255, ending on `Host key verification failed.`
```
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
…
```

**Say** — "Nothing about the hostname changed. Nothing about the port changed.
What changed is *which machine is behind them* — and my laptop noticed, because
the proxy relayed the server's real key untouched. This is the thing that
actually breaks on migration day."

**If it does not fire** → you skipped step 1, or the fix is still applied.
Run `make rearm`, then step 1, then this step.
```

### Anti-Patterns to Avoid

- **Putting `known_hosts` in a named volume or bind mount.** Decouples the client's trust lifetime from the backends' key lifetime and makes the gotcha fire before the flip. See Finding 2.
- **Removing Phase 3's `/dev/null` pins to "unify" the modes.** Would convert every routing assertion into a host-key assertion the moment the gotcha is armed. The two modes must stay two modes.
- **Asserting the fix by grepping `sshd_config` or by `ls`-ing `/etc/ssh`.** The files being in place proves nothing — sshd holds the keys in memory. Assert the *fingerprint equality* and then assert a real connection.
- **`ssh … | grep` in any new assertion.** Phase 3 measured `ssh … | head` returning 0 while printing `Host key verification failed.` Capture into a variable, read `$?` on the very next line, grep the variable.
- **Regenerating keys with `ssh-keygen -A` alone as a re-arm.** `-A` only creates *missing* keys; with the transferred keys present it is a silent no-op. The `rm -f /etc/ssh/ssh_host_*` is load-bearing.
- **Narrating the fix as "we copied the keys".** Copying is inert until SIGHUP. Say "we gave the new server the old server's identity, and told sshd to pick it up."

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Re-arming the gotcha | A script that edits `known_hosts` to a bogus key | `rm -f /etc/ssh/ssh_host_* && ssh-keygen -A && kill -HUP` on `server-new` | Faking the client's record produces a *different* error path and teaches the wrong lesson. Regenerating the server's key is the real thing, and takes ~1 s |
| Moving key files | A base64 / `docker cp` / temp-file pipeline | `tar -cf - \| tar -xf -` over two `compose exec -T` | tar carries mode and ownership atomically; no host temp file, no key material on the host filesystem |
| Making sshd notice new keys | Container restart, or `docker compose up --force-recreate` | `kill -HUP $(cat /run/sshd.pid)` | Recreate regenerates the very keys you just installed (entrypoint) *and* can change the container IP, which nginx has cached from config-parse time. HUP is 1 s and touches nothing else |
| Detecting "the key changed" in a test | Parsing `ssh -v` output or comparing `ssh-keyscan` results | Capture the invocation, assert `rc != 0` **and** `grep REMOTE HOST IDENTIFICATION HAS CHANGED` | Both halves are needed: rc alone could be a network failure, the string alone could come from a pipeline that masked the exit code |
| Proving `known_hosts` was untouched | A diff of the whole `~/.ssh` tree | `md5sum` the file before and after, with `UpdateHostKeys=no` pinned | Without the pin, ssh legitimately rewrites the file and any whole-tree comparison is a false alarm |

**Key insight:** every piece of this phase's mechanism is a *single, existing* OpenSSH or Docker primitive being used for exactly its documented purpose. The moment a custom script starts synthesising the failure rather than causing it, the demo stops being a demonstration and becomes a puppet show — which is precisely the credibility the phase exists to earn.

## Runtime State Inventory

This is not a rename phase, but it is a **state-lifecycle** phase, and the same discipline applies: what holds the demo's state, and what clears it?

| Category | Items Found | Action Required |
|----------|-------------|------------------|
| **Stored data** | `/root/.ssh/known_hosts` in the `client` container's **writable layer** (absent today — Phase 3 left only `config`). Verified by `ls -la /root/.ssh/`. This is the phase's *only* new piece of state | None — it is created by the presenter's first connection and destroyed with the container. Deliberately **not** promoted to a volume |
| **Live service config** | `/etc/ssh/ssh_host_{ed25519,rsa,ecdsa}_key{,.pub}` on each backend, generated by `backend/entrypoint.sh`'s `ssh-keygen -A`, held in the container writable layer. **sshd additionally caches them in memory at startup** — the files and the running daemon are two separate pieces of state | `make fix-hostkeys` must change **both**: copy the files *and* `kill -HUP`. Changing only the files is a silent no-op (measured) |
| **OS-registered state** | None — verified. The repo publishes nothing on a privileged port, registers no launchd/systemd unit, and touches no host file except the one-time `/etc/hosts` line the presenter adds manually |
| **Secrets / env vars** | `demo-keys` named volume holds the client keypair and `authorized_keys`. **Untouched by this phase.** `demo:demo` password fallback untouched. No new secret is introduced | None |
| **Build artifacts** | `demo-backend:1` image. **Must not gain a `ssh-keygen -A` build layer** — `backend/Dockerfile` carries an explicit `NOTE:` forbidding it, and that note is the reason this phase is possible | None — but any plan that touches `backend/Dockerfile` must preserve that note verbatim |

### Lifecycle matrix (measured)

| Operation | Backend host keys | Client `known_hosts` | Gotcha state afterwards |
|-----------|-------------------|----------------------|--------------------------|
| `docker compose restart server-new` | **kept** (entrypoint's `ssh-keygen -A` is a no-op for existing keys — verified: fingerprint `RkC9…` survived a restart) | kept | unchanged — **the fix survives a restart**, so the presenter cannot be surprised mid-demo |
| `docker compose exec … kill -HUP` | kept | kept | unchanged (only re-reads what is on disk) |
| `make up` (`up -d --build --wait`, images unchanged) | kept — no recreate | kept | unchanged |
| `docker compose down` then `up` | **regenerated** | **cleared** (client container recreated) | armed and consistent — both sides reset together |
| `make reset` (`down -v` + rebuild) | **regenerated** on both backends | **cleared** | armed and consistent. **Measured: 16.5 s wall clock** |
| `docker compose up -d --force-recreate server-new` | regenerated on `server-new` only | kept | armed — but see Pitfall 4: nginx has the backend's IP cached from config-parse time |
| `make rearm` (proposed: `rm -f` + `ssh-keygen -A` + HUP + clear client `known_hosts`) | regenerated on `server-new` | cleared | armed. **~1 s, no rebuild, no IP churn** |

The bottom two rows are the answer to research question 2: `make reset` works and should stay the documented headline path (D-51), but a purpose-built `make rearm` is 16× faster and is what a presenter doing three takes in a row actually wants.

## Common Pitfalls

### Pitfall 1: `UpdateHostKeys` silently rewrites `known_hosts` and breaks the KEY-04 claim

**What goes wrong:** After the fix, the presenter's connection succeeds — and OpenSSH, unprompted, appends `server-old`'s RSA and ECDSA host keys to `known_hosts` and leaves a `known_hosts.old` behind. Measured: `95 → 837 bytes`, md5 `c31eec3a…` → `738879ec…`, three lines where there was one.
**Why it happens:** `UpdateHostKeys` defaults to `yes` in OpenSSH ≥ 8.5. Once a connection authenticates against a key already in `known_hosts`, the client accepts the server's offer of its *other* host keys and records them. It does **not** happen on the initial TOFU acceptance, which is why the prime step looks clean and the trap only springs at the very last step of the demo.
**How to avoid:** pin `-o UpdateHostKeys=no` in presenter mode. Verified: with it, the file is byte-identical across the entire narrative (`BYTE-IDENTICAL: yes`).
**Warning signs:** a `known_hosts.old` file appearing; a `known_hosts` with three lines when the presenter recorded one.

### Pitfall 2: Copying the key files is not the fix

**What goes wrong:** `make fix-hostkeys` copies six files, the presenter reruns `ssh`, and gets the identical 13-line failure. It looks like the fix did nothing.
**Why it happens:** sshd reads host keys once at startup and holds them in memory. Measured directly: after a successful tar transfer with `ls` confirming the new files and `ssh-keygen -lf` confirming the new fingerprints on disk, the connection *still* failed with `The fingerprint … is SHA256:Sya2QG7N…` — the **old in-memory** key.
**How to avoid:** `kill -HUP $(cat /run/sshd.pid)` immediately after the copy, inside the same target. sshd re-execs itself, keeping the same PID (measured: PID 16 before and after), so supervisord never notices.
**Warning signs:** the fingerprint quoted in the failure message is unchanged after the fix ran.

### Pitfall 3: Priming against the wrong name records the wrong entry

**What goes wrong:** the presenter connects to `server-old` directly to "warm things up", then flips, then connects to `app.demo.test` — and gets a clean TOFU acceptance instead of the gotcha.
**Why it happens:** `known_hosts` is keyed on the **name the client typed**. `server-old` and `app.demo.test` are two independent entries. Only a prime against `app.demo.test` arms the gotcha.
**How to avoid:** the walkthrough's prime step must use `app.demo.test` and nothing else; `make ssh` should hard-code the target so it cannot be fumbled.
**Warning signs:** `grep -c app.demo.test /root/.ssh/known_hosts` returns 0 after the prime step.

### Pitfall 4: `--force-recreate` as a re-arm can strand nginx on a dead IP

**What goes wrong:** the presenter re-arms with `docker compose up -d --force-recreate server-new`; the container comes back on a different IP; nginx keeps routing to the old address and every request 502s.
**Why it happens:** `proxy/nginx.conf` declares `upstream new { server server-new:22; }` (and `:80`), and nginx resolves upstream hostnames **at config-parse time**, with no `resolver` directive — a deliberate Phase 1/3 decision documented in the file itself.
**Measured:** in this session the recreated container happened to be reassigned the same IP (`172.19.0.4`) and routing survived. That is luck, not a guarantee, and it is the worst kind of hazard — one that works in rehearsal and fails on stage.
**How to avoid:** make `make rearm` regenerate keys **in place** (`rm -f` + `ssh-keygen -A` + HUP), never recreate the container. If a recreate is ever unavoidable, follow it with `docker compose exec proxy nginx -s reload`.
**Warning signs:** 502s from `:9092` after a re-arm; `make verify` reporting `UNREADABLE`.

### Pitfall 5: Docker's AI hint trails every failing command

**What goes wrong:** the gotcha's final line on the projector is not `Host key verification failed.` but:
```
What's next:
    Debug this Compose error with Gordon → docker ai "help me fix this compose error"
```
**Why it happens:** Compose v2 appends a hint block after any non-zero `compose exec`, but **only when stdout is a TTY** — which is why it never appears in the smoke suite and will always appear on stage.
**How to avoid:** `export DOCKER_CLI_HINTS=false` in the walkthrough's pre-flight checklist (D-56), or set it inside the `make ssh` recipe. Verified: with the variable set, the output ends exactly on `Host key verification failed.`
**Warning signs:** none until you are in front of people. This is a pre-flight item, not a runtime one.

### Pitfall 6: The default `ssh` command hangs or fails on a fresh rig

**What goes wrong:** README currently documents `docker compose exec client ssh demo@app.demo.test` producing `OLD server-old` and a shell prompt. On a **fresh** rig it does not — it first asks:
```
The authenticity of host 'app.demo.test (172.19.0.5)' can't be established.
ED25519 key fingerprint is SHA256:4g8uAcs1On29tSgs2lMfSrCZeniiGrpnzXCSJeDOsI4.
This key is not known by any other names.
Are you sure you want to continue connecting (yes/no/[fingerprint])?
```
and blocks. With no TTY it does not even prompt — it exits 255 with a bare `Host key verification failed.` (measured; one probe in this session hung for the full 120 s timeout).
**Why it happens:** default `StrictHostKeyChecking=ask` plus an empty `known_hosts`.
**How to avoid:** `accept-new` in `make ssh`. The README's Phase 3 SSH example should be corrected to either show the prompt or route through `make ssh`. **This is a pre-existing documentation inaccuracy this phase should fix**, and it is exactly the kind of thing criterion 5 is meant to catch.
**Warning signs:** the very first SSH beat of the demo stalls.

### Pitfall 7: `make verify` passing while the demo is visibly broken

**What goes wrong:** the gotcha is armed and firing, the presenter reaches for `make verify EXPECT=new` to diagnose, and it reports `OK  both protocols report NEW` and exits 0. The presenter concludes the rig is fine and the failure was a fluke.
**Why it happens:** `verify.sh` pins test mode (`UserKnownHostsFile=/dev/null`) by design, so it is structurally incapable of seeing a host-key problem. Measured live: presenter mode rc=255 and `verify.sh new` rc=0, simultaneously.
**How to avoid:** document it as a *feature* in both README and WALKTHROUGH — "`make verify` answers 'did the routing land?', not 'does the client trust what it landed on?'" It is the sharpest available illustration of why D-52's two modes exist.
**Warning signs:** none. This one only bites the presenter's confidence, which is why it belongs in the traps section (D-57).

### Pitfall 8: The transferred public keys still say `root@server-old`

**What goes wrong:** an audience member notices that `ssh-keygen -lf /etc/ssh/ssh_host_ed25519_key.pub` on `server-new` prints `… root@server-old (ED25519)`.
**Why it happens:** the comment field is part of the copied `.pub` file. It is cosmetic and has no protocol effect.
**How to avoid:** do not "fix" it — **narrate** it. It is the single most vivid piece of evidence in the whole demo that the new server is genuinely wearing the old server's cryptographic identity. The walkthrough should point at it deliberately.

## Code Examples

### Presenter mode (`make ssh`)

```make
# make ssh — PRESENTER MODE (D-52). The complement of test mode, and the only
# mode in which the Phase 4 gotcha is reachable.
#
# DOCKER_CLI_HINTS=false: Compose appends an AI upsell after any non-zero exec
# in a TTY, which would otherwise be the last thing on the projector after the
# gotcha. Measured; see RESEARCH Pitfall 5.
#
# accept-new  — records an unseen host silently. No TOFU prompt, no dead air,
#               and it STILL refuses a CHANGED key (measured, rc=255).
# UpdateHostKeys=no
#             — without it OpenSSH rewrites known_hosts by ITSELF on the first
#               successful post-fix connection, and KEY-04's "no client-side
#               edit" claim becomes unassertable. Measured: 95 -> 837 bytes.
ssh:
	@DOCKER_CLI_HINTS=false docker compose exec client ssh \
	  -o StrictHostKeyChecking=accept-new -o UpdateHostKeys=no \
	  demo@app.demo.test
```

### The fix, verified end to end

```
$ make fix-hostkeys
transferring server-old's host keys to server-new …
  SHA256:RkC9Gv2w7yGjb89maRKteWaLfAyiYO5V7MlibL765+g  (ED25519)
telling sshd on server-new to pick them up …
done — 0.44s

$ make ssh
NEW server-new
server-new:~$
```

Measured 0.44 s wall clock for the tar transfer plus HUP.

### The gotcha — literal output (13 lines, rc=255)

```
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
IT IS POSSIBLE THAT SOMEONE IS DOING SOMETHING NASTY!
Someone could be eavesdropping on you right now (man-in-the-middle attack)!
It is also possible that a host key has just been changed.
The fingerprint for the ED25519 key sent by the remote host is
SHA256:8EFs1xelpNSPssNOzaMWcvvSJe7Rh700S1R8Rygcxfo.
Please contact your system administrator.
Add correct host key in /root/.ssh/known_hosts to get rid of this message.
Offending ED25519 key in /root/.ssh/known_hosts:1
Host key for app.demo.test has changed and you have requested strict checking.
Host key verification failed.
```

Notes for WALK-02, all measured:
- Exactly **13 lines**, exit code **255**.
- Line 11 names the file **and the line number**: `/root/.ssh/known_hosts:1`.
- The fingerprint on line 8 is the *new* server's and will differ on every run — the walkthrough must show it as `SHA256:…` rather than a literal, or explicitly say it varies.
- Identical whether run with a TTY or without, and identical with or without `BatchMode=yes` — a **changed** key is refused unconditionally, not merely under strict settings, despite the message's wording.
- Under a TTY, Docker appends the `What's next: … Gordon` block unless `DOCKER_CLI_HINTS=false` is set.

### `ssh-keygen -R` — the wrong fix, and it genuinely works

```
$ docker compose exec client ssh-keygen -R app.demo.test
# Host app.demo.test found: line 1
/root/.ssh/known_hosts updated.
Original contents retained as /root/.ssh/known_hosts.old
```
rc=0, 3 lines. The subsequent connection then succeeds — but only because it re-accepts the new key blind:
```
Warning: Permanently added 'app.demo.test' (ED25519) to the list of known hosts.
NEW server-new
```

Three things make this the teaching moment, all verified:
1. It **works**. Show it working; the argument is not that it fails.
2. It is **two steps, not one** — deleting the record does not connect you; you must then trust whatever answers next, unverified. `-R` does not fix the problem, it deletes the *objection* to the problem.
3. It fixes **one client**. `known_hosts` lives on every laptop, every CI runner, every jump box, every Ansible controller. There is no `-R` you can run once.

### The smoke assertion shape (all 7 executed and passing in this session)

```sh
export PRESENTER_OPTS="-o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new -o UpdateHostKeys=no"

# The deliberate-failure idiom: BOTH halves are required. rc alone could be a
# network fault; the string alone could arrive through a pipeline that masked a
# zero exit — research measured `ssh … | head` returning 0 while printing
# `Host key verification failed.` Capture into a variable, read $? on the VERY
# NEXT line, then grep the VARIABLE.
assert "KEY-02 the gotcha: non-zero exit AND the warning banner" \
	'out=$(docker compose exec -T client timeout 10 ssh $PRESENTER_OPTS demo@app.demo.test hostname 2>&1)
	 rc=$?
	 test "$rc" -ne 0 && printf "%s\n" "$out" | grep -q "WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED"'

# The negative control. Without this, a bug that broke SSH outright would still
# pass the assertion above.
assert "KEY-02 negative control: the same failure does NOT reach test mode" \
	'out=$(docker compose exec -T client timeout 10 ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null demo@app.demo.test hostname 2>&1)
	 rc=$?
	 test "$rc" -eq 0 && printf "%s\n" "$out" | grep -q "^NEW server-new$"'

# KEY-04, mechanically. Requires UpdateHostKeys=no above.
export KH_BEFORE   # captured before the fix
assert "KEY-04 known_hosts byte-identical across the fix" \
	'test "$(docker compose exec -T client md5sum /root/.ssh/known_hosts | cut -d" " -f1)" = "$KH_BEFORE"'
```

`export` is mandatory on `PRESENTER_OPTS` and `KH_BEFORE`: `assert` runs its condition through a fresh `sh -c`, which inherits exported variables but not shell functions or unexported locals. This is the same reason `section_ssh` exports `SSH_OPTS`.

## Findings (the empirical record)

Every result below came from a command run against the live stack on 2026-07-21.

**Finding 1 — the mismatch is real and already present.** `server-old` ed25519 `SHA256:RkC9Gv…`, `server-new` `SHA256:Sya2QG…`. Three key types each (ed25519, rsa, ecdsa), all `0600`/`0644` root-owned, all generated by `backend/entrypoint.sh`'s `ssh-keygen -A`. D-47 holds without qualification. [VERIFIED]

**Finding 2 — `known_hosts` needs no new persistence, and adding one is actively harmful.** The client container's `/root/.ssh` currently holds only `config`. A plain `ssh` writes `known_hosts` into the container's **writable layer**, which lives exactly as long as the container. Because every Compose operation that regenerates backend host keys (`down`+`up`, `reset`) also recreates the client, the two states are automatically in step. A named volume would survive `docker compose down`, leaving a stale key against fresh backend keys — **the gotcha would fire on the first connection, before the flip.** A bind mount would additionally survive `down -v`, defeating `make reset` as a re-arm and writing host state the project forbids. Answers Q1. [VERIFIED — lifecycle matrix above]

**Finding 3 — the failure, verbatim.** 13 lines, rc=255, names `/root/.ssh/known_hosts:1`. Identical with and without a TTY, and with and without `BatchMode`. Reproduced through the nginx `stream` proxy, which is what makes it evidence of a genuine Layer-4 relay. Answers Q4. [VERIFIED]

**Finding 4 — the fix.** Six files via `tar -cf - | tar -xf -` over two `compose exec -T`; modes and ownership preserved by tar, no `chmod` needed. **A running sshd does not pick them up** — a connection attempted after the copy but before any signal still failed with the old in-memory fingerprint. `kill -HUP $(cat /run/sshd.pid)` is sufficient and preserves the PID (16 before, 16 after); supervisord is undisturbed. Total 0.44 s. After the HUP the client connected with an unmodified `known_hosts` and saw the banner `NEW server-new` — cryptographic identity inherited, application identity new, which is exactly KEY-04's claim and the phase's best single sentence. Answers Q3. [VERIFIED]

**Finding 5 — the fix survives a container restart.** `docker compose restart server-new` left the transferred fingerprint `RkC9Gv…` in place, because `ssh-keygen -A` only generates *missing* keys. The presenter cannot be ambushed mid-demo by a restart undoing the fix. This also means `rm -f /etc/ssh/ssh_host_*` is mandatory in any re-arm. Answers the D-49 restart concern. [VERIFIED]

**Finding 6 — the re-arm.** `make reset` works and takes **16.5 s** measured, regenerating both backends' keys and clearing the client's `known_hosts` (the client container is recreated). In-place regeneration — `rm -f /etc/ssh/ssh_host_*; ssh-keygen -A; kill -HUP` on `server-new`, plus `rm -f /root/.ssh/known_hosts*` on the client — achieves the same arm state in ~1 s with no rebuild and no IP churn. `--force-recreate` is the option to avoid (Pitfall 4). Answers Q2. [VERIFIED]

**Finding 7 — the preconditions, exactly.** The gotcha fires on the **first** connection after the flip, deterministically, with no warm-up and no timing dependence, provided all three hold:
1. The client has a `known_hosts` entry **for `app.demo.test`** (not for `server-old`), recorded while the selector was on `old`.
2. `server-new`'s host keys still differ from `server-old`'s — i.e. the fix is not already applied.
3. The selector has been flipped.
The connection must be a **new** one: Phase 3's D-40 leaves in-flight sessions on their original backend for their whole life, so a terminal the presenter left open before the flip will keep talking to OLD and show nothing. Answers Q7. [VERIFIED]

**Finding 8 — `accept-new` is the right presenter pin.** Default (`ask`) prompts and blocks in a TTY; with a piped stdin it does not even prompt, exiting 255 with a bare `Host key verification failed.` `accept-new` records silently on first sight *and* still refuses a changed key with the full 13-line warning. It gives a clean prime step and loses nothing. [VERIFIED]

**Finding 9 — the two modes are genuinely independent.** With the gotcha armed and presenter mode failing rc=255, `sh scripts/verify.sh new` printed `OK  both protocols report NEW` and exited 0. No change to `section_ssh` or `verify.sh` is needed, and none should be made. Full suite re-run at the end of the session: **186 passed, 0 failed**; `sh scripts/smoke.sh proxy`: **17 passed, 0 failed**. [VERIFIED]

**Finding 10 — `ssh-keygen -R` works, in three lines, rc=0**, and leaves a `known_hosts.old`. It then requires a second, blind trust decision to actually connect. Answers Q5. [VERIFIED]

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| `StrictHostKeyChecking` is binary (`yes`/`no`) | `accept-new` — trust on first use, refuse on change | OpenSSH 7.6 (2017) | Exactly the semantics a demo prime step needs; no prompt, no weakening |
| `known_hosts` records one key per host | `UpdateHostKeys=yes` by default — the client learns and records the server's *other* host keys after an authenticated connection | OpenSSH 8.5 (2021) | Silently rewrites `known_hosts` and breaks a naive "unchanged file" assertion. Pin `no` for the demo |
| sshd host keys re-read per connection (never true, but widely assumed) | Loaded once at startup; `SIGHUP` re-execs | long-standing | The reason `make fix-hostkeys` must signal, not just copy |
| `ssh-keygen -R` prints nothing useful | Prints the matched line number and retains `.old` | modern OpenSSH | Gives the walkthrough a concrete artefact to point at when explaining why it does not scale |

**Deprecated / outdated:**
- `ssh-keygen -A` regenerating existing keys — it never did; it only fills gaps. Any re-arm that omits `rm -f` is a silent no-op.
- DSA host keys — not generated by `ssh-keygen -A` on this OpenSSH. Only ed25519, rsa and ecdsa exist; the fix transfers six files, not eight.

## Project Constraints (from `.claude/CLAUDE.md` and inherited phases)

`.claude/CLAUDE.md` carries the GSD workflow enforcement block and the PROJECT constraints. The actionable directives for this phase:

- **Tech stack:** nginx (`stream`) + Docker Compose only. No new runtime, no new service.
- **Ports:** HTTP 9092, SSH 22. Published ports stay exactly `127.0.0.1:9090/9091/9092/9093/9094`. **No host port 22** (D-38, T-01-02).
- **Environment:** entirely local, no cloud account, no cost.
- **Startup:** one command. `make ssh` / `make fix-hostkeys` / `make rearm` are *demo* commands, not setup steps.
- **The repo never modifies host state.** `sudo` appears only inside printed remediation text. No bind mount may be added for `known_hosts`.
- **No key material on the host filesystem and none committed** (T-03-01). This rules out `docker cp` through a host temp directory for the fix.
- **`sh scripts/smoke.sh proxy` must stay at exactly 17/17.** Verified still 17/17 at the end of this session.
- **All 186 existing assertions must keep passing, and Phase 3's `/dev/null` pins must not be removed.** Verified still 186/186.
- **`backend/Dockerfile`'s `NOTE: no ssh-keygen -A here, and there must never be one`** must survive this phase verbatim — it is the load-bearing comment that makes KEY-01 possible.

## Validation Architecture

`workflow.nyquist_validation` is `true` in `.planning/config.json`, so this section applies.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | POSIX-`sh` assertion harness — `scripts/smoke.sh`, section-dispatched, custom `assert` helper. No third-party runner, deliberately |
| Config file | none — the script *is* the config. Sections dispatched by `case "$section"` at the foot |
| Quick run command | `sh scripts/smoke.sh hostkey` (the new section, once added) |
| Full suite command | `sh scripts/smoke.sh` — currently **186 passed, 0 failed** |
| Independent oracle | `sh scripts/verify.sh <old\|new>` — deliberately *cannot* see host-key state (test mode). Useful as a control, never as the KEY-0x assertion |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| KEY-01 | The two backends carry different host keys | unit | `sh scripts/smoke.sh backends` — assertion `KEY-01 precondition: backends have DIFFERENT ssh host keys` | ✅ already present and passing |
| KEY-01 | `make rearm` restores the differing state from a fixed state | integration | `sh scripts/smoke.sh hostkey` | ❌ Wave 0 — `section_hostkey` |
| KEY-02 | Post-flip presenter-mode ssh exits non-zero **and** prints the warning | integration | `sh scripts/smoke.sh hostkey` | ❌ Wave 0 |
| KEY-02 | Negative control — test mode is unaffected in the same state | integration | `sh scripts/smoke.sh hostkey` | ❌ Wave 0 |
| KEY-03 | After `make fix-hostkeys`, both backends report the same ed25519 fingerprint | integration | `sh scripts/smoke.sh hostkey` | ❌ Wave 0 |
| KEY-03 | The fix signals sshd, not just the filesystem (guard: a copy without HUP must NOT pass) | integration | `sh scripts/smoke.sh hostkey` | ❌ Wave 0 |
| KEY-04 | Same command succeeds against NEW after the fix | integration | `sh scripts/smoke.sh hostkey` | ❌ Wave 0 |
| KEY-04 | `known_hosts` md5 identical across the fix | integration | `sh scripts/smoke.sh hostkey` | ❌ Wave 0 |
| WALK-01 | `WALKTHROUGH.md` exists and its step headings appear in the D-55 order | doc-lint | `sh scripts/smoke.sh walkthrough` | ❌ Wave 0 |
| WALK-02 | Every fenced `bash` command in `WALKTHROUGH.md` is either a defined `make` target or a command that exists | doc-lint | `sh scripts/smoke.sh walkthrough` | ❌ Wave 0 |
| WALK-02 | Every file path referenced in `WALKTHROUGH.md` exists in the repo | doc-lint | `sh scripts/smoke.sh walkthrough` | ❌ Wave 0 |
| WALK-03 | Every step section contains all three blocks (command / expect / say) | doc-lint | `sh scripts/smoke.sh walkthrough` | ❌ Wave 0 |
| WALK-03 | The traps named in D-57 each appear in `WALKTHROUGH.md` | doc-lint | `sh scripts/smoke.sh walkthrough` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `sh scripts/smoke.sh hostkey` and/or `sh scripts/smoke.sh walkthrough` — the sections owned by the task
- **Per wave merge:** `sh scripts/smoke.sh` (full, 186 + new) **and** `sh scripts/smoke.sh proxy` (the 17/17 guard, asserted exactly)
- **Phase gate:** full suite green, selector left on `old`, `git status` clean, before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `section_hostkey` in `scripts/smoke.sh` — covers KEY-01..KEY-04. **Destructive** (flips the selector, arms and fixes the gotcha, writes the client's `known_hosts`); must follow `guard_check`'s trap-restore discipline exactly: back up state, `trap … EXIT INT TERM`, restore the selector to `old`, re-arm `server-new`'s keys, and clear `/root/.ssh/known_hosts*` on the way out.
- [ ] `section_walkthrough` in `scripts/smoke.sh` — the doc-lint section. This is the honest proxy for ROADMAP criterion 5 (see below).
- [ ] Dispatcher entries for both new sections, plus their placement in the `all` chain. Place `section_hostkey` **last**, after `section_ssh`, for the same reason `section_ssh` follows `section_cutover`: it is the most destructive and it leaves the rig in the state the next section expects.
- [ ] No framework install required — the harness already exists.

### On ROADMAP criterion 5 ("someone who has never seen the demo can follow it cold")

This cannot be mechanically verified and should not be claimed as verified. The honest proxy is a **four-part executable contract**, all of which `section_walkthrough` can assert:

1. **Every command is runnable verbatim.** Every fenced `bash` block in `WALKTHROUGH.md` is either a `make` target that exists in the `Makefile`'s `.PHONY` list, or a binary on `PATH`. No pseudo-commands, no `…`, no placeholders.
2. **Every referenced path exists.** Every `` `path/like/this` `` in the document resolves to a real file in the repo.
3. **No undefined prerequisite.** Every command appearing in a step is either in the pre-flight checklist or produced by an earlier step. Assertable as: the set of `make` targets used in steps ⊆ (pre-flight targets ∪ targets introduced by earlier steps).
4. **Structural completeness.** Every step heading is followed by all three D-54 blocks, and the step headings appear in the D-55 order.

Passing all four means the document is *self-contained and executable*. It does **not** mean it is *comprehensible* — whether the takeaway prose lands with a room of humans is a judgement no assertion can make. The plan should therefore carry an explicit `checkpoint:human-verify` task: **one person who has not seen the demo runs `WALKTHROUGH.md` top to bottom on a clean checkout and reports every point at which they had to guess.** That checkpoint is the only real evidence for criterion 5, and the VERIFICATION document should say so plainly rather than claiming mechanical coverage.

### On the full-run rehearsal (research question 10)

**Recommendation: yes, and it is already written.** `section_hostkey` as specified above *is* the end-to-end rehearsal — prime on OLD → flip → gotcha → fix → success — because those are the only steps that can prove KEY-01..KEY-04 anyway. It was executed in full in this session and all seven assertions passed. Adding it costs nothing beyond the assertions the requirements already demand.

Weighed honestly:
- **Slow?** No. Measured under 20 s, dominated by `docker compose exec` round-trips. It is comparable to `section_cutover`.
- **Destructive?** Yes — it flips the selector and arms/fixes the gotcha. But `section_cutover` and `guard_check` are already destructive and already trap-restored; this follows the same established idiom rather than introducing a new hazard.
- **Value:** it is the only thing that stops `WALKTHROUGH.md` rotting. A document that describes a five-step narrative, backed by a test that executes that same five-step narrative, cannot drift silently.

What it deliberately does **not** cover: the browser beats (incognito, the 301 contrast, the status page). Those are already human-verified from Phases 1–2 and re-automating them here would be scope creep.

## Security Domain

`security_enforcement` is `true`, `security_asvs_level` is 1.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| V2 Authentication | yes | Unchanged from Phase 3 — ed25519 key auth from the `client` container, `demo:demo` retained as the documented fallback. **This phase adds no credential and weakens no auth path.** |
| V3 Session Management | no | No web session, no cookie, no token anywhere in the project |
| V4 Access Control | yes (narrow) | The `demo-keys` volume's rw-on-client / `:ro`-on-backends asymmetry is unchanged. The fix reaches into `server-new`'s `/etc/ssh` via `compose exec` — a *host-operator* privilege, not a container-to-container one. Neither backend gains any handle on the other |
| V5 Input Validation | yes (narrow) | `make rearm` and `make fix-hostkeys` take no user input. Keep them argument-free; do not add a "which server" parameter that could `rm -f /etc/ssh/ssh_host_*` on the wrong container |
| V6 Cryptography | yes | **Never hand-roll.** All key material is produced by `ssh-keygen -A` and moved byte-for-byte by `tar`. No key is generated, parsed, converted or re-encoded by any script in this phase |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Host key material written to the host filesystem or committed | Information Disclosure | The fix streams `tar \| tar` between containers; nothing lands on the host. Assert `git ls-files` contains no key material (the suite already does this) |
| Two backends permanently sharing host keys via a mounted volume | Spoofing | Rejected as a fix mechanism — it would also destroy KEY-01. The transfer is a one-shot copy into a writable layer, reversible by `make rearm` |
| A `--force-recreate`-based re-arm stranding nginx on a stale upstream IP | Denial of Service (self-inflicted, on stage) | In-place regeneration only; if a recreate is unavoidable, follow with `nginx -s reload` (Pitfall 4) |
| Teaching the audience to disable host-key checking | *Reputational* — the demo is the attack surface | The `-o StrictHostKeyChecking=no` pins live **only** in `verify.sh` and `section_ssh`, each with an inline comment saying demo-only and naming the phase. Two smoke assertions already enforce that those comments exist. **Presenter mode must never carry them**, and the walkthrough must be explicit that `accept-new` is not the same as `no` |
| A parameterised destructive target (`make rearm SERVER=…`) run against the wrong container | Tampering | Keep both new targets argument-free and hard-coded to `server-new` |
| Publishing port 22 to make the demo "cleaner" | Elevation of Privilege | D-38 stands. Nothing in this phase requires it |

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Docker Compose v2 | everything | ✓ | in use, `docker compose` verified | — |
| Running demo stack | all empirical work | ✓ | 5 services healthy | `make up` |
| `ssh` / `ssh-keygen` in `client` | presenter mode, the wrong fix | ✓ | OpenSSH 10.0p2 | — |
| `sshd` + `ssh-keygen -A` in backends | key generation, re-arm | ✓ | Alpine openssh | — |
| `tar` in both backends | the fix | ✓ | BusyBox | — |
| `/run/sshd.pid` in backends | `kill -HUP` | ✓ | present, PID 16 | `pgrep -f 'sshd -D'` |
| GNU Make 3.81 | new targets | ✓ | macOS system make | — |
| `/etc/hosts` entry for `app.demo.test` | browser beats only | ✓ | `make status` reports `hosts: OK` | `--resolve` for curl; browser beats need it |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** none.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `UpdateHostKeys` defaulting to `yes` dates from OpenSSH 8.5 | State of the Art | Low — the *behaviour* was measured directly in this session on OpenSSH 10.0p2; only the version attribution is from training knowledge. The mitigation (`-o UpdateHostKeys=no`) is verified working regardless |
| A2 | `StrictHostKeyChecking=accept-new` was introduced in OpenSSH 7.6 | Alternatives Considered | Low — same shape. The option works in the shipped client; only the introduction version is unverified, and nothing depends on it |
| A3 | Docker may assign a *different* IP when a service is force-recreated | Pitfall 4 | Medium — in this session the IP was **reused** (`172.19.0.4` before and after), so the hazard was not reproduced. It is standard Docker behaviour that IPs are not guaranteed stable across recreate, and nginx's parse-time resolution is verified from `proxy/nginx.conf`. The recommendation (avoid `--force-recreate`) is cheap insurance either way; a plan that ignores it risks an intermittent stage failure |
| A4 | The `What's next … Gordon` hint is TTY-gated Compose behaviour | Pitfall 5 | Low — both the appearance under a pty and its suppression by `DOCKER_CLI_HINTS=false` were measured. Only the *reason* (TTY gating) is inferred |
| A5 | A human reviewer is available to run the criterion-5 checkpoint | Validation Architecture | Medium — if no second person exists, criterion 5 must be recorded as **judgement, unverified** in VERIFICATION.md rather than quietly marked passed |

## Open Questions

1. **How hard should the walkthrough lean on "`ssh-keygen -R` is the wrong fix"?**
   - What we know: it works, in three lines, for one client (verified); and it requires a second, blind trust decision to actually connect (verified). Both facts are strong.
   - What's unclear: tone. CONTEXT's open concern flags this as a presentation judgement the user may want to set personally. There is a real difference between "here is the instinct, and here is why it does not scale" and "this is what people do wrong."
   - Recommendation: write it as **demonstration then contrast** — show `-R` succeeding without editorial, then ask the room how many laptops are on their network. Let the audience draw the conclusion. That framing survives either preference and does not need the user to arbitrate before execution.

2. **Should `make rearm` exist, given D-51 names `make reset` as the re-arm path?**
   - What we know: `reset` works and takes 16.5 s; in-place re-arm works and takes ~1 s with no rebuild and no IP churn.
   - What's unclear: whether adding a second re-arm command contradicts D-51 or merely refines it.
   - Recommendation: ship both and document `make reset` as the headline (honouring D-51 verbatim) with `make rearm` as the between-takes fast path. The smoke section needs a fast, non-rebuilding re-arm regardless — it cannot call `make reset` from inside the suite.

3. **Does the README's Phase 3 SSH example need correcting in this phase?**
   - What we know: as written it shows a clean first connection that a fresh rig does not produce (Pitfall 6).
   - Recommendation: yes, correct it — routing it through `make ssh` fixes the inaccuracy and introduces presenter mode in the same edit. Small, and it is exactly the class of defect criterion 5 exists to catch.

## Sources

### Primary (HIGH confidence)

- **The live stack**, 2026-07-21 — every Finding above. Commands run against `demo` Compose project: `ssh`, `ssh-keygen -lf`, `ssh-keygen -R`, `ssh-keygen -A`, `sshd -T`, `kill -HUP`, `tar`, `md5sum`, `docker compose exec/restart/up --force-recreate`, `docker inspect`, `make reset`, `sh scripts/flip.sh`, `sh scripts/verify.sh`, `sh scripts/smoke.sh`.
- **Repo source read in full or in relevant part** — `compose.yaml`, `Makefile`, `backend/Dockerfile`, `backend/entrypoint.sh`, `backend/supervisord.conf`, `client/Dockerfile`, `client/entrypoint.sh`, `proxy/nginx.conf`, `proxy/active-backend.conf`, `scripts/smoke.sh` (§`section_ssh`, `guard_check`, dispatcher), `scripts/verify.sh`, `README.md`, `.claude/CLAUDE.md`.
- **`.planning/phases/03-ssh-through-the-stream-proxy/03-VERIFICATION.md`** — the prior live reproduction of the mismatch and the 186/17 baselines.
- **`.planning/phases/01|02|03-*-CONTEXT.md`**, `REQUIREMENTS.md`, `ROADMAP.md`, `04-CONTEXT.md`.

### Secondary (MEDIUM confidence)

- OpenSSH behavioural semantics (`UpdateHostKeys`, `accept-new`, SIGHUP re-exec, `ssh-keygen -A` gap-filling) — each confirmed by direct measurement in this session; version attributions are training knowledge (see A1, A2).

### Tertiary (LOW confidence)

- None. No claim in this document rests on an unverified web result. No web search was performed: every question was answerable by running a command against the stack, which is a stronger source.

## Metadata

**Confidence breakdown:**
- Standard stack: **HIGH** — no new dependency; every tool executed in the target container.
- Architecture / mechanism: **HIGH** — the full narrative (prime → flip → gotcha → fix → success) was executed end to end and all seven candidate assertions passed.
- Pitfalls: **HIGH** for 1, 2, 3, 5, 6, 7, 8 (each reproduced); **MEDIUM** for 4 (the hazard is real and the mitigation is cheap, but the failure did not reproduce — see A3).
- Validation architecture: **HIGH** — the proposed smoke section was written and run in this session.
- Criterion 5: **acknowledged as judgement.** The four-part doc-lint contract is a proxy, and this document says so rather than pretending otherwise.

**Rig state on completion:** `sh scripts/smoke.sh` → **186 passed, 0 failed**. `sh scripts/smoke.sh proxy` → **17 passed, 0 failed**. Selector on `old`. Backend ed25519 fingerprints distinct (`4g8uAcs1…` / `MvVzTXHP…`). Client `/root/.ssh` holds only `config`. `git status` clean apart from the pre-existing `.planning/config.json` modification, which this session did not touch.

**Research date:** 2026-07-21
**Valid until:** 2026-08-20 (30 days — the stack is fully pinned; the only drift risk is an OpenSSH default changing under an Alpine base-image bump)

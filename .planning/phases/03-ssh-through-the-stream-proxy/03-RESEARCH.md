# Phase 3: SSH Through the Stream Proxy - Research

**Researched:** 2026-07-21
**Domain:** nginx `ngx_stream_*` TCP proxying, OpenSSH 10.x client/server behaviour, POSIX shell assertion harnesses
**Confidence:** HIGH — every load-bearing claim below was executed against the running stack in this session, not recalled

---

<user_constraints>
## User Constraints (from CONTEXT.md)

> ⚠️ These decisions were **AUTO-SELECTED** (fully-autonomous mode), not user-answered. They are
> treated as locked. **Research found no hard technical blocker against any of D-37..D-46.**
> D-39 — the strongest and most fragile-looking claim — is **empirically confirmed** (§Q1).

### Locked Decisions

- **D-37 [AUTO]:** The **`client` container is the canonical SSH source**, exactly as it is for HTTP. The presenter runs `docker compose exec client ssh demo@app.demo.test`. Inside the Docker network the proxy genuinely listens on **port 22**, so the "SSH on port 22" claim is literally true, not a workaround.
- **D-38 [AUTO]:** Port 22 is **not published to the host**. Nothing in the repo may bind a privileged host port.
- **D-39 [AUTO]:** The `stream` block reuses **the same `proxy/active-backend.conf` include** the HTTP side uses. `map` is valid in both the `http` and `stream` contexts, while `upstream` is not shareable between them. The presenter can say truthfully: **one file, one word, both protocols.**
- **D-40 [AUTO]:** `worker_shutdown_timeout` stays **unset**, and the comment Phase 2 left in `nginx.conf` gets resolved here. An in-flight SSH session surviving the reload is a *feature* worth narrating.
- **D-41 [AUTO]:** **Key-based auth from the client container**, keypair generated at build or first run, public key installed on both backends. Password auth for `demo` stays enabled as a documented fallback. The key is a demo credential with no value and never leaves the compose network.
- **D-42 [AUTO]:** The SSH **login banner** names the backend as `OLD` or `NEW` with its hostname, driven by the same `BACKEND_ID` env var as everything else (D-16).
- **D-43 [AUTO]:** The banner must appear **before** the shell prompt and be visible even for a non-interactive `ssh … <command>` invocation, because the verify script (EVID-04) reads it programmatically.
- **D-44 [AUTO]:** `scripts/verify.sh <expected>` — issues an HTTP request and an SSH connection, reports which backend answered each, and **exits non-zero on any mismatch**. Extends the existing POSIX-shell idiom.
- **D-45 [AUTO]:** The script asserts **both protocols agree with each other**, not just each against the expectation.
- **D-46 [AUTO]:** SSH connections are **not** added to the status page's request table. The `stream` module's logging is separate and lands in `make logs`.

### Claude's Discretion

- Which SSH client image the `client` container uses, and whether `openssh-client` is already present from Phase 1 (it was installed there deliberately — check before adding).
- The `stream` log format and where it writes, subject to `make logs` surfacing it.
- How the client's public key reaches both backends (build-time copy, entrypoint, or a mounted authorized_keys).
- Whether the verify script shells out to `docker compose exec` or runs inside the client container.

### Deferred Ideas (OUT OF SCOPE)

- SSH connection counter on the status page (D-46).
- Publishing port 22 to the host (D-37/D-38).
- Severing in-flight SSH sessions on reload via `worker_shutdown_timeout` (D-40).

### Anti-scope (from the research brief and CONTEXT.md)

- **Do NOT stage the host-key mismatch failure or its fix.** Do NOT write the presenter walkthrough. Both are Phase 4.
- This research **reports what Phase 4 inherits** (§Q5) and stops there.

</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| **BACK-04** | Each backend's SSH login banner states its own identity (OLD or NEW) and hostname | §Q3 — `Banner` via an `/etc/ssh/sshd_config.d/*.conf` drop-in, rendered by `entrypoint.sh` from `BACKEND_ID`/`BACKEND_HOSTNAME`. **A plain append to `sshd_config` is not always sufficient — see §Q4 Pitfall S-2.** |
| **BACK-05** | Presenter can log into either backend over SSH with a known credential or key | §Q4 — verified: key auth works with `AuthorizedKeysFile` pointed at a root-owned shared-volume path; `demo:demo` password fallback already exists from Phase 1 |
| **SSH-01** | Client can `ssh` to the nginx host on port 22 and land on the active backend | §Q1 — verified end to end from the `client` container to `app.demo.test:22` |
| **SSH-02** | nginx uses the `stream` module to proxy raw TCP on port 22, not an HTTP redirect | §Q1 — the exact eight-line block D-13 predicted, `nginx -t` clean, verified proxying |
| **SSH-03** | The SSH session shows the active backend's identity banner on login | §Q3 — banner reaches the client on **stderr**, pre-auth, before the prompt; survives the TCP hop unchanged |
| **CUT-04** | SSH sessions opened after the flip land on `server-new`, provable from the login banner | §Q1/§Q3 — verified: identical `ssh` command returned `BANNER … OLD server-old` then `BANNER … NEW server-new` across `sh scripts/flip.sh new` |
| **EVID-04** | A verify script issues an HTTP request and an SSH connection and reports which backend answered each | §Q9 — exact flag set, timeout discipline, and the three idioms that silently break it |
| **EVID-05** | The verify script exits non-zero if the observed backend does not match the expected one | §Q9 — **the single biggest trap: a pipeline masks `ssh`'s exit code.** Measured. |

</phase_requirements>

---

## Summary

Phase 3 is unusually low-risk for a phase that adds a whole new protocol, and the reason is that
Phase 1 paid for it in advance. D-13's choice of a `map` over an `upstream` was made speculatively;
this session **executed** the payoff and it works exactly as predicted. Appending the literal
eight-line `stream { }` block that `proxy/nginx.conf` already carries as a comment produces a config
that passes `nginx -t`, reloads gracefully, proxies SSH from the `client` container to whichever
backend `proxy/active-backend.conf` selects, and switches backend the instant `sh scripts/flip.sh`
runs — with **zero regressions**: `sh scripts/smoke.sh proxy` stayed at 17/17 and the full suite at
120/120 with the stream block live.

The genuinely new engineering in this phase is not the stream block. It is three smaller things, each
of which has a non-obvious failure mode measured below: (1) **how the identity banner is configured**,
because Alpine's stock `sshd_config` carries an *active* `AuthorizedKeysFile` at line 45 and
first-directive-wins means a naive append is silently ignored — the `Include /etc/ssh/sshd_config.d/*.conf`
at line 15 is the only reliable seam; (2) **how the keypair reaches both backends** without a private
key in git and without a second image, for which a shared named volume plus `AuthorizedKeysFile
/keys/authorized_keys` is verified working (sshd re-reads it per authentication attempt, so there is
no start-ordering race at all); and (3) **the verify script's exit-code discipline**, where
`ssh … | head` returns 0 on a host-key catastrophe — measured in this session, and precisely the bug
that would make EVID-05 a lie.

D-40 is confirmed as narratable truth: an in-flight SSH session pinned to a `worker process is
shutting down` continued printing `server-old` for its full duration while a new `ssh` in the same
second landed on `server-new`. And §Q5 confirms Phase 4's entire premise works end to end today —
one hostname, two host keys, `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED` reproduced verbatim —
without Phase 3 needing to stage anything.

**Primary recommendation:** Append the commented block from `proxy/nginx.conf` verbatim, add a
`log_format`/`access_log /dev/stdout` pair and one stream-local `map` for an uppercase `backend=`
label, wire the banner and `AuthorizedKeysFile` through `/etc/ssh/sshd_config.d/10-demo.conf`,
distribute the keypair via a `demo-keys` named volume written by a new `client` entrypoint, and write
`scripts/verify.sh` with `timeout 10 ssh -o BatchMode=yes -o ConnectTimeout=5` captured into a
variable — never a pipeline.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| TCP transport of SSH on :22 | **Proxy (nginx `stream`)** | — | This is the phase's entire claim: nginx is the L4 intermediary. Nothing else may touch the bytes. |
| Backend selection | **Shared config file** (`proxy/active-backend.conf`) | Proxy (`map` in both contexts) | D-39. The selector is *data*; both protocol contexts read it. One file, one word. |
| Identity assertion (SSH) | **Backend (sshd `Banner`)** | — | Same honesty rule as D-11: only the backend may claim to be the backend. The proxy's stream log carries the *selector*, which is a different claim. |
| Identity assertion (HTTP) | Backend (`X-Backend` header) | Proxy (log echo only) | Unchanged from Phase 1/2. |
| Authentication material | **Client container** (generates) | Shared volume → backends (consume, read-only) | Mirrors the Phase 2 evidence-integrity idiom: the writer is one tier, the reader is another and it is read-only. |
| Host key material | **Backend, at container start** | — | `ssh-keygen -A` in `entrypoint.sh` (Phase 1). Untouched — it is Phase 4's precondition. |
| Routing evidence (SSH) | **Proxy stream access log → stdout** | `make logs` | D-46. Explicitly NOT the status service's JSON sink. |
| Assertion of the whole claim | **`scripts/verify.sh`** (runs in `client`) | `scripts/smoke.sh ssh` section | D-44/D-45. |

---

## Q1 — The shared selector across contexts (D-39). **VERIFIED — the claim holds.**

**Verdict: D-39 is correct in every part. "One file, one word, both protocols" is literally true.**
`[VERIFIED: executed against the running stack, 2026-07-21]`

The exact block already written as a comment at the foot of `proxy/nginx.conf` was appended
unmodified:

```nginx
stream {
    upstream old { server server-old:22; }
    upstream new { server server-new:22; }
    include /etc/nginx/demo/active-backend.conf;
    server { listen 22; proxy_pass $active_backend; }
}
```

Results:

| Check | Result |
|-------|--------|
| `nginx -t` with `active-backend.conf` included in **both** `http` and `stream` | `syntax is ok` / `test is successful` |
| `nginx -s reload` | exit 0, `signal process started` |
| `netstat -lnt` in the proxy container | `0.0.0.0:22 LISTEN` appeared alongside `0.0.0.0:9092` |
| `ssh demo@app.demo.test` from the `client` container | reached a real sshd — host key offered, auth negotiated |
| Fingerprint via proxy with selector `old` | `SHA256:SHPajDTLtaKS2mrxhXantKpQKqoxso316yB0wHnnEZI` == `server-old`'s |
| Same after `sh scripts/flip.sh new` | `SHA256:ZOl3Mh8QHFvcIlk/N3Wiu6Jw08JtnYVe26XtX17Zewo` == `server-new`'s |
| `ssh … hostname` before / after flip | `server-old` → `server-new` |

**Why it works, precisely — three separate facts the planner should be able to state:**

1. **`ngx_stream_map_module` is built by default under `--with-stream`.** It is opt-*out*
   (`--without-stream_map_module`), so it does not appear in `nginx -V` output. `nginx -V` on
   `nginx:1.30-alpine` shows `--with-stream`, `--with-stream_realip_module`,
   `--with-stream_ssl_module`, `--with-stream_ssl_preread_module` — the map module's absence from
   that list is **not** evidence it is missing. `[VERIFIED: nginx -V in the proxy container]`
2. **`$server_port` is a valid `ngx_stream_core_module` variable.** An unknown variable used as a
   `map` key is a config-time error; `nginx -t` passed, which proves it resolves. `[VERIFIED]`
3. **`$active_backend` in `http` and `$active_backend` in `stream` are two independent variables in
   two independent namespaces.** There is no redefinition conflict, and the file can be included
   twice at top level with no restructuring. `[VERIFIED]`

> **Presenter-honesty nuance worth one line in the plan:** because the map body is only
> `default old;`, the map's *key* (`$server_port`) is never actually consulted — every lookup falls
> to `default`. This makes D-39 **more** robust than it needs to be, not less: even if `$server_port`
> meant something different in the stream context, the selector would behave identically. The file's
> shape is chosen for how it reads on a projector, and it happens to be maximally portable.

**No blocker found. D-39 stands.**

---

## Q2 — Reload behaviour and in-flight SSH sessions (D-40). **VERIFIED — D-40 is narratable truth.**

`[VERIFIED: executed, 2026-07-21]`

Method: opened a 40-second SSH session through the proxy from the `client` container running
`for i in $(seq 1 40); do echo "tick $i $(hostname)"; sleep 1; done`, logging to a file. At tick ~5,
ran `sh scripts/flip.sh new`. Observed for 6 more seconds.

| Observation | Value |
|-------------|-------|
| Session ticks before flip | `tick 3 server-old`, `tick 4 server-old` |
| Session ticks **after** flip | `tick 10 server-old`, `tick 11 server-old`, `tick 12 server-old` |
| A **new** `ssh … hostname` issued after the flip | `server-new` |
| `ps` in the proxy container | two workers: `nginx: worker process is shutting down` (PID 1618) **and** `nginx: worker process` (PID 1673) |

**The mechanism, stated exactly:** on `nginx -s reload` the master forks new workers and tells the
old ones to shut down gracefully. With `worker_shutdown_timeout` unset (nginx's default: no timeout),
an old worker does not exit while it holds an open connection. The stream connection is bound to that
worker for its lifetime, so it keeps relaying to `server-old` until the client or server closes it.
New TCP connections are accepted by the new worker generation and use the new selector.

This is the same graceful-reload machinery Phase 2 measured a 26–90 ms interleave on for HTTP. The
difference is not in kind but in duration: an HTTP request finishing in milliseconds makes the old
worker exit almost immediately; an SSH session pins it indefinitely.

**Implications the planner must carry forward:**

- **The Phase 2 comment in `nginx.conf` can now be resolved with a measurement, not a hedge.** Replace
  the "DEFERRED QUESTION FOR PHASE 3" prose with the observed behaviour and the D-40 rationale.
- **The presenter line writes itself:** *"Your existing session is untouched — that's what graceful
  means. Open a new one and you're on the new box."* This is a genuine operational property of a real
  cutover and is worth more to the narrative than severing sessions would be.
- **One operational consequence to document, not fix:** a forgotten long-lived SSH session leaves an
  old worker (and its old config) alive indefinitely. Across many takes this could accumulate workers.
  `docker compose exec proxy ps` shows them. This is nginx behaving correctly and the demo's sessions
  are short; **do not** add `worker_shutdown_timeout` to "tidy" it — that is the explicitly deferred
  decision.
- **Smoke-suite hazard:** an assertion that opens a long SSH session must close it, or the next
  section's reload leaves a stale worker and `ps`-based assertions become nondeterministic. Use
  `timeout`-bounded, short-lived connections in the suite.

---

## Q3 — SSH banner delivery (D-42, D-43). **VERIFIED — only `Banner` satisfies D-43.**

`[VERIFIED: executed against server-old and server-new, 2026-07-21]`

Three candidate mechanisms were configured simultaneously and probed under four invocation shapes.

| Invocation | `Banner` (pre-auth) | `/etc/motd` + `PrintMotd yes` (post-auth) |
|-----------|---------------------|-------------------------------------------|
| `ssh host hostname` (non-interactive, no pty) — **the verify script's shape** | ✅ printed, on **stderr** | ❌ **absent** |
| `ssh -tt host hostname` (forced pty, still a command) | ✅ printed | ❌ **absent** |
| `ssh host` (interactive login shell) | ✅ printed, then… | ✅ printed, then the prompt |
| `ssh -q …` or `-o LogLevel=QUIET` or `-o LogLevel=ERROR` | ❌ **suppressed** | n/a |

**Conclusions, in priority order:**

1. **`Banner` is the only mechanism that satisfies D-43.** MOTD is emitted by sshd only for an
   interactive *login shell*; `ssh host command` never runs one, and forcing a pty with `-tt` does not
   change that. **The verify script must read `Banner`, and BACK-04 must be implemented as `Banner`.**
   `[VERIFIED]`
2. **The banner arrives on the client's stderr, not stdout.** `ssh host hostname 2>/dev/null` returns
   only `server-old`. Any capture must use `2>&1`. This is a feature: the command's stdout stays a
   clean machine channel while the banner is the human/identity channel.
   `[VERIFIED]`
3. **`-q` / `LogLevel=ERROR` / `LogLevel=QUIET` silently suppress the banner.** Measured:
   `LogLevel=ERROR` → captured output was the empty string; default LogLevel → `BANNER-LINE OLD
   server-old`. **This is the most likely way a future maintainer breaks EVID-04** while "cleaning up
   noisy output". It deserves a comment in `verify.sh` and ideally a smoke assertion that greps
   `verify.sh` for `-q`/`LogLevel=`. `[VERIFIED]`
4. **Ordering satisfies D-42/D-43 in the interactive case too**: banner → motd → prompt, in that
   order. Confirmed with a pty:
   ```
   BANNER-LINE OLD server-old
   MOTD-LINE OLD server-old
   server-old:~$
   ```
5. **The banner survives the stream hop unchanged.** Confirmed through `app.demo.test:22` on both
   sides of a flip — `BANNER-LINE OLD server-old` then `BANNER-LINE NEW server-new` from the identical
   command. The stream module relays bytes; it neither sees nor alters the SSH protocol.
   `[VERIFIED]`

**Recommendation (BACK-04 implementation):** render `/etc/ssh/banner` in `backend/entrypoint.sh` from
the same `BACKEND_ID` / `BACKEND_HOSTNAME` pair `envsubst` already uses for the HTTP surfaces
(D-16 — the two identity surfaces cannot drift because they come from one variable), and enable it via
a drop-in (§Q4 Pitfall S-2). Keep the banner short — it lands on stderr in every scripted invocation
and a multi-line ASCII box will read as noise in the verify output. Two lines maximum, with the
literal words `OLD`/`NEW` and the hostname, matching BACK-03's `OLD server-old` shape so the same grep
anchors both protocols.

**Optionally set `PrintMotd`/motd as well** for the interactive stage path — it costs nothing and it
is what the presenter's audience actually sees when a shell opens. But it is *decoration*; the
contract is `Banner`.

---

## Q4 — Key-based auth from the client container (D-41)

### Recommended mechanism: a `demo-keys` named volume + `AuthorizedKeysFile`

`[VERIFIED: each component executed individually, 2026-07-21]`

```
client (rw)  ──generates──▶  demo-keys volume  ──ro──▶  server-old  sshd
                             /keys/id_ed25519           server-new  AuthorizedKeysFile
                             /keys/authorized_keys                  /keys/authorized_keys
```

**Why this shape and not the alternatives:**

| Approach | Verdict |
|----------|---------|
| Commit a keypair to the repo | ❌ **Reject.** A private key in git looks like a real credential leak to anyone who clones or scans the repo, regardless of how obviously throwaway it is. The demo already carries `demo:demo`, which is *visibly* a joke; a PEM block is not. |
| `RUN ssh-keygen` in `client/Dockerfile` only | ⚠️ Half a solution. The private key stays out of git (good), but the **public** key must still reach the backends, which are a different image. Needs a second mechanism anyway. |
| Bake `authorized_keys` into `backend/Dockerfile` | ❌ Requires the private key to be committed (see row 1) or two coupled builds. |
| `make up` pushes the pubkey via `docker compose exec` | ⚠️ Works, but adds an imperative step outside `docker compose up`, weakening ENV-01, and raw `docker compose up -d --wait` (D-20 says it must work standalone) would then produce a rig where SSH auth silently fails. |
| **Shared named volume + `AuthorizedKeysFile`** | ✅ **Recommended.** No committed key, no second image, no host state, and — the decisive property — **sshd reads `AuthorizedKeysFile` at each authentication attempt, so there is no start-ordering race.** The backends start before the client; they simply need the volume mounted. By the time anyone types `ssh`, the client has written it. |

**Verified sub-claims:**

- A fresh Docker named volume mounts as `drwxr-xr-x root root`. `StrictModes yes` (Alpine's default)
  is satisfied for an `AuthorizedKeysFile` outside the user's home when the path chain is root-owned
  and not group/world-writable. `[VERIFIED: docker run + ls -ld on a scratch volume]`
- With `/home/demo/.ssh` **deleted** and `AuthorizedKeysFile /keys/authorized_keys` in effect, key
  auth from the client succeeded and returned `server-old`. `[VERIFIED]`
- The `client` image already ships `ssh`, `ssh-keygen` and `ssh-keyscan`
  (`openssh-client-default`, `openssh-keygen` present in `apk info`). **No `client/Dockerfile` change
  is required for tooling** — Phase 1's D-18 foresight holds. `[VERIFIED]`
- `ssh-copy-id` is **not** present. Do not plan around it.

**Implementation notes for the planner:**

- The `client` service currently has `command: ["sleep","infinity"]` and no entrypoint. Add a tiny
  `client/entrypoint.sh` that generates the keypair **if absent** and writes `authorized_keys`, then
  `exec "$@"`. Idempotence matters: `make up` runs repeatedly and the volume survives `down`.
- `chmod 600` the private key and `644` the `authorized_keys`; `ssh` refuses a group-readable private
  key.
- Mount the volume **`:ro` on both backends** and read-write only on the client. This deliberately
  mirrors the Phase 2 evidence-integrity idiom (the tier that consumes cannot alter) and gives the
  presenter the same one-line explanation twice.
- `make reset` runs `down -v`, which removes the volume — keys regenerate on the next `up`. Correct
  behaviour, worth a comment.
- **Do not touch `ssh-keygen -A` in `backend/entrypoint.sh`.** Host keys must keep being generated
  per container start so the two backends differ. That is Phase 4's precondition and there is a
  smoke assertion depending on it.
- **Keep password auth enabled.** `demo:demo` already exists (`backend/Dockerfile`) and D-41 keeps it
  as the documented fallback. Do not add `PasswordAuthentication no`.

### Pitfall S-2 (the one that will actually bite) — `sshd_config` first-directive-wins

`[VERIFIED: measured failure and fix, 2026-07-21]`

Alpine's stock `/etc/ssh/sshd_config` contains:

```
15:  Include /etc/ssh/sshd_config.d/*.conf
45:  AuthorizedKeysFile	.ssh/authorized_keys      # ← ACTIVE, not commented
```

sshd uses the **first** obtained value for a keyword. Appending `AuthorizedKeysFile /keys/...` to the
end of the file is **silently ignored** — `sshd -T` still reported `authorizedkeysfile
.ssh/authorized_keys` and key auth failed with `Permission denied (publickey,password,...)`. This cost
a debugging cycle in research and would cost one in execution.

The `Include` at line 15 comes *before* line 45, so a drop-in **does** win. Verified fix:

```sh
mkdir -p /etc/ssh/sshd_config.d
printf 'AuthorizedKeysFile /keys/authorized_keys\nBanner /etc/ssh/banner\n' \
  > /etc/ssh/sshd_config.d/10-demo.conf
```

→ `sshd -T` reported `banner /etc/ssh/banner` and `authorizedkeysfile /keys/authorized_keys`, and key
auth succeeded. **Use a drop-in for every sshd setting this phase adds, uniformly** — `Banner` happens
to work as an append (there is no active `Banner` line) but mixing two mechanisms invites exactly this
bug next time.

Verify it in the smoke suite with `sshd -T`, not by grepping the config file: `sshd -T` reports the
**effective** value and is the only check that would have caught this.

---

## Q5 — `known_hosts` through a TCP proxy: what Phase 4 inherits. **VERIFIED END TO END.**

> **This section reports. It stages nothing.** No repo change was made and none is recommended in
> Phase 3.

`[VERIFIED: reproduced verbatim, 2026-07-21]`

**Current state, measured:**

| Fact | Value |
|------|-------|
| `server-old` ed25519 host key | `SHA256:SHPajDTLtaKS2mrxhXantKpQKqoxso316yB0wHnnEZI` |
| `server-new` ed25519 host key | `SHA256:ZOl3Mh8QHFvcIlk/N3Wiu6Jw08JtnYVe26XtX17Zewo` |
| They differ | **Yes** — `ssh-keygen -A` runs per container start (`backend/entrypoint.sh`), never in a build layer |
| Key seen by the client at `app.demo.test:22`, selector `old` | `SHPaj…` (server-old's) |
| Same, after `sh scripts/flip.sh new` | `ZOl3M…` (server-new's) |
| Hostname the client sees | `app.demo.test` — **one name, two keys** |

**The failure Phase 4 needs, reproduced:**

```
$ ssh -o UserKnownHostsFile=/root/.ssh/kh_test -o StrictHostKeyChecking=yes demo@app.demo.test hostname
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
IT IS POSSIBLE THAT SOMEONE IS DOING SOMETHING NASTY!
...
The fingerprint for the ED25519 key sent by the remote host is
SHA256:ZOl3Mh8QHFvcIlk/N3Wiu6Jw08JtnYVe26XtX17Zewo.
...
Offending ED25519 key in /root/.ssh/kh_test:2
Host key for app.demo.test has changed and you have requested strict checking.
Host key verification failed.
```

**Verdict: Phase 4's entire narrative is already mechanically true.** No Phase 3 work is needed to
enable it, and no Phase 3 work should be done to enable it.

**What Phase 4 inherits — the precise handover:**

1. **The mechanism is free.** Distinct per-container host keys plus one proxied hostname produce the
   warning with no contrivance. KEY-01 is already satisfied by `backend/entrypoint.sh` as written.
2. **The trigger is `known_hosts` persistence in the client container.** Today the client's
   `/root/.ssh/known_hosts` is ephemeral (no volume, no bind mount) and is wiped by any container
   recreate. **For Phase 4 to stage KEY-02 reliably, the client's `known_hosts` must persist across
   the flip within a single take** — which it does naturally, since the flip does not recreate the
   client. No volume is strictly required; Phase 4 should decide whether it wants one.
3. **Phase 4's fix (KEY-03) is a host-key transfer, and the shape is already obvious**: copy
   `server-old`'s `/etc/ssh/ssh_host_*` into `server-new` and `pkill -HUP sshd`. `ssh-keygen -A` is
   idempotent-by-absence — it only generates keys that do not exist — so the transfer survives an
   sshd restart but **not** a container recreate. That is the correct property for a demo you want to
   be able to reset.
4. **⚠️ The Phase 3/Phase 4 collision the planner must pre-empt.** If `scripts/verify.sh` and the new
   smoke `ssh` section use a **persistent** `known_hosts` with default `StrictHostKeyChecking`, then
   the moment Phase 4 stages KEY-02 the Phase 3 assertions will start failing **for the wrong
   reason** — a host-key error, not a routing error. **Phase 3's routing assertions must be orthogonal
   to host-key state.** Use `-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no` in
   `verify.sh` and in the smoke `ssh` section, with a comment saying exactly why. This is the single
   most valuable thing Phase 3 can do *for* Phase 4 without staging anything.
   `[VERIFIED: reasoning grounded in the reproduced failure above]`
5. **`ssh-keyscan` is the clean, auth-free oracle** for "which backend is behind :22 right now" and
   is present in the client image. Phase 4 will likely want it; Phase 3 may use it in the smoke
   suite. `ssh-keyscan -t ed25519 app.demo.test | ssh-keygen -lf -` returns a fingerprint in ~0.1 s
   and needs no credential.

---

## Q6 — Stream logging

`[VERIFIED: executed, 2026-07-21]`

### What works

```nginx
stream {
    log_format demo_stream '$remote_addr -> :$server_port ssh backend=$stream_label '
                           'selector=$active_backend upstream=$upstream_addr status=$status '
                           'bytes=$upstream_bytes_sent/$upstream_bytes_received sess=$session_time';
    access_log /dev/stdout demo_stream;

    upstream old { server server-old:22; }
    upstream new { server server-new:22; }
    include /etc/nginx/demo/active-backend.conf;
    map $active_backend $stream_label { default "?"; old OLD; new NEW; }   # stream-local, NOT the shared file

    server { listen 22; proxy_pass $active_backend; }
}
```

Produced, verbatim, in `docker compose logs proxy`:

```
172.19.0.6 -> :22 ssh backend=OLD selector=old upstream=172.19.0.2:22 status=200 bytes=3718/4518 sess=0.089
```

A **second, stream-local `map`** for the uppercase label is verified working. It must live in the
`stream` block, **not** in `proxy/active-backend.conf` — that file must stay five lines (CONTEXT.md,
Reusable Assets).

### How it differs from the HTTP access log — and the honesty point

| | HTTP `demo` format | Stream `demo_stream` format |
|---|---|---|
| When written | on response completion (ms) | **on connection close** — a 10-minute SSH session logs nothing for 10 minutes |
| Identity source | `$upstream_http_x_backend` — **the backend's own header** | no such thing exists; there is no protocol to read |
| `$status` | the backend's HTTP status | nginx's **own** stream status: `200` ok, `400`/`403`/`500`/`502`/`503` |
| Available `$upstream_*` | `_addr`, `_response_time`, `_http_*` | `_addr`, `_bytes_sent`, `_bytes_received`, `_connect_time`, `_first_byte_time`, `_session_time` |

> **⚠️ Honesty caveat the planner must carry into the config comments.** The HTTP log's `backend=`
> field is the *backend asserting its own identity* (D-11: "no tier of this rig ever synthesises an
> identity"). The stream log's `backend=` is **the proxy reporting its own selector** — nginx cannot
> read an identity out of an opaque TCP stream. These are different epistemic claims wearing the same
> field name.
>
> Two defensible resolutions; **pick one deliberately and comment it**:
> - **(a) Keep `backend=`** so `make logs-demo`'s existing `awk` colouring works on SSH lines for
>   free, and add a config comment stating the provenance difference explicitly.
> - **(b) Use a distinct token** (`ssh_backend=` / `selector=` only) so the two claims are never
>   conflated, and extend `logs-demo`'s `awk` with two more patterns.
>
> **Recommendation: (a) plus the comment plus `selector=` retained alongside.** The demo's whole point
> is that one word drives both protocols, and a shared field name reinforces that on the projector.
> The honesty is preserved by keeping `selector=` in the same line — the reader can see the proxy is
> reporting its own choice.

### Reaching `make logs`

`access_log /dev/stdout demo_stream;` — confirmed present in `docker compose logs -f proxy`. `make logs`
already tails `proxy server-old server-new`, so **no Makefile change is required for `logs`**. If
option (b) is chosen, `logs-demo`'s `awk` needs two new patterns (mind the doubled `$$` — Makefile
Pitfall 9).

### Interaction with the Phase 2 evidence sink — **the trap**

`/var/log/demo/access.log` is read by `status/status.py`. Its parser:

```python
try:
    obj = json.loads(line)
except ValueError:
    continue  # torn trailing line — skip, never raise
```

So writing stream lines there **would not crash the status page** — the lines are silently discarded.
That is worse than crashing: the writes would be invisible, unexplained, and would grow a file the
status service scans on every poll while contributing nothing.

**Verdict: the stream `access_log` MUST go to `/dev/stdout` only.** Never to `/var/log/demo/access.log`.
D-46 already says SSH stays out of the request table; this is the mechanical reason. Add a config
comment saying so, and consider a smoke assertion that `/var/log/demo` does not appear inside the
`stream` block.

*(If a future phase ever wants SSH on the status page — the deferred D-46 counter — the correct move
is a second `log_format … escape=json` writing to a **separate** file, not co-mingling in the sink
whose whole design assumes one JSON object per line from one producer.)*

---

## Q7 — The Phase 1/2 regression surface. **MEASURED: zero regressions.**

`[VERIFIED: full suite executed with the stream block live, 2026-07-21]`

| Guard | Result with the stream block live |
|-------|-----------------------------------|
| `sh scripts/smoke.sh proxy` | **17 passed, 0 failed** |
| `sh scripts/smoke.sh` (full) | **120 passed, 0 failed** |

**Every specific hazard, checked:**

| Hazard | Outcome |
|--------|---------|
| `stream` at top level breaks `http` parsing | No. Sibling blocks, independent. |
| Duplicate `$active_backend` definition | No. Separate variable namespaces. `[VERIFIED]` |
| `D-15 no host port 22 binding exists` (smoke) | **Still passes** — D-38 publishes nothing. `docker compose ps` shows no `:22->`. |
| `HTTP-01 honesty: no add_header in proxy/nginx.conf` | Still passes — nothing added introduces `add_header`. **But note the assertion is a `grep -ci` over the whole file with comments stripped; new stream comments must not contain the string `add_header`.** |
| `T-01-13 Location target is literal` (greps `return 301`) | Unaffected. |
| `D-22 every demo-hostname token is the reserved .test form` | Unaffected — the stream block uses `server-old`/`server-new`, not a hostname token. |
| `T-02-16` sudo/escalation-token assertions | Unaffected — no new `sudo` text. |
| **`guard_check` (5 of the 17): writes `default nwe;` and asserts `nginx -t` passes AND reload succeeds** | **Still passes.** With the stream block present, `nginx -t` returned ok and `nginx -s reload` returned 0. The invalid selector is a **runtime** failure on both sides, not a parse failure. `[VERIFIED — this was the highest-risk assertion and it survives]` |
| Cold start (`up`) with a stream block | Unaffected. `stream`'s `upstream ... server server-old:22` resolves at parse time exactly like the http one, and compose already gates `proxy` on both backends being `service_healthy`. Same hostnames, same gate. |

**Behaviour under an invalid selector, for the record** `[VERIFIED]`:

```
http  9092  → 503, body names 'nwe'      (the http $backend_is_valid guard — unchanged)
ssh     22  → connection closed by peer; ssh rc=255
proxy log   → [error] no port in upstream "nwe", ... server: 0.0.0.0:22
            → 172.19.0.6 -> :22 ssh selector=nwe upstream=- status=500 bytes=-/- sess=0.000
```

> **A stream block cannot serve the 503-equivalent.** The `$backend_is_valid` guard lives in `http`
> and has no stream analogue that would mean anything to an SSH client — `ngx_stream_return_module`
> could emit text, but an SSH client receiving arbitrary bytes just fails differently and less
> legibly. **Recommendation: do not build a stream guard.** The `[error] no port in upstream "nwe"`
> line plus `status=500` in the stream access log is already a legible diagnosis, and the 9092 guard
> catches the same typo two seconds earlier in the presenter's day. Say this in a comment so a future
> reader does not think it was overlooked.

**Regression-detection plan for execution:** run `sh scripts/smoke.sh proxy` (17/17) immediately after
the `nginx.conf` edit lands and before anything else, then the full suite before the phase closes.
Both were green in research, so a failure means the plan diverged from the verified block.

---

## Q8 — Healthcheck and oracle coverage of the stream side

`[VERIFIED: executed, 2026-07-21]`

**Can nginx be "healthy" on HTTP while the stream listener is dead?**

- **Listener down, HTTP up: not reachable.** It is one nginx master serving both contexts. `nginx -t`
  validates the whole file, and a failure to bind `:22` aborts nginx entirely — there is no state
  where `:8081/nginx-health` answers and `:22` is not listening. Structural, not lucky.
- **Stream *path* broken while HTTP is healthy: yes, easily, and it was reproduced.** With
  `default nwe;` the `:8081` oracle returned `nwe` and `:8081/nginx-health` returned `ok` while every
  SSH connection was closed with `status=500`. **The `:8081` oracle proves the reload landed; it does
  not prove the SSH path works.**

**⚠️ Do NOT extend the compose healthcheck.** Two hard reasons:

1. The existing healthcheck deliberately probes `:8081` and not `:9092` precisely because
   `guard_check` writes an invalid selector on purpose and the container would flap unhealthy
   mid-suite. A port-22 end-to-end probe has the **identical** problem — `guard_check` would break the
   stream path for several seconds every run.
2. `python:3.13-alpine`-style ecosystem quirks aside, the proxy's healthcheck is `curl`-based and
   cheap by design; an SSH handshake per 3-second interval is neither.

**Do extend the smoke suite instead**, with two assertions at different altitudes:

| Altitude | Assertion | Note |
|----------|-----------|------|
| Listener | `docker compose exec -T proxy nc -z 127.0.0.1 22` | **`127.0.0.1`, NOT `localhost`** — see the finding below |
| End to end | `ssh-keyscan -t ed25519 app.demo.test` from the `client` returns the active backend's fingerprint | auth-free, ~0.1 s, and orthogonal to Phase 4's host-key state |

### 🔎 New finding: `listen 22;` in `stream` binds **IPv4 only**

`[VERIFIED]`

```
proxy (nginx stream):   0.0.0.0:22 LISTEN            ← IPv4 only
server-old (sshd):      0.0.0.0:22  and  :::22       ← both families
```

Consequently, inside the proxy container:

```
nc -z 127.0.0.1 22  → OPEN
nc -z ::1       22  → CLOSED
nc -z localhost 22  → CLOSED   ← busybox nc tries ::1 first and does not retry
```

The existing `BACK-01/BACK-02 sshd on :22` assertions use `nc -z localhost 22` and pass **only because
sshd binds both families**. Copying that idiom to the proxy would produce a false failure. This is the
exact hazard `compose.yaml` already documents for the `status` service's busybox `wget` healthcheck —
same root cause, second occurrence. **Use `127.0.0.1` for anything probing the proxy's stream
listener, and comment it with a pointer to the existing note.**

*(Adding `listen [::]:22;` would also work but changes the demo's surface for no narrative gain, and
`0.0.0.0:22` reads more cleanly on screen. Not recommended.)*

---

## Q9 — The verify script (D-44/D-45)

`[VERIFIED: each flag and failure mode executed, 2026-07-21]`

### 🚨 The bug that would make EVID-05 a lie

Measured this session, verbatim:

```sh
ssh -o StrictHostKeyChecking=yes demo@app.demo.test hostname 2>&1 | head -25
echo "EXIT=$?"      # → EXIT=0
```

…while the output was `WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!` and
`Host key verification failed.` **The pipeline's exit status is `head`'s, not `ssh`'s.** A verify
script written this way reports success on a total failure. It is the most natural way to write the
script and it is wrong.

**Rule: capture into a variable with command substitution, then test `$?` on the very next line.**
Never pipe. Never `| head`, `| grep`, `| tee` in the same command as the assertion.

```sh
out=$(timeout 10 ssh -o BatchMode=yes -o ConnectTimeout=5 \
      -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      demo@app.demo.test hostname 2>&1)
rc=$?
```

### The verified flag set, with the reason for each

| Flag | Why — measured |
|------|----------------|
| `2>&1` | **Mandatory.** The banner is on stderr; the command result is on stdout. Both are needed. |
| `-o BatchMode=yes` | Kills every interactive prompt. Without it a missing key falls back to a password prompt and blocks. |
| `-o ConnectTimeout=5` | Bounds the **TCP connect** only. Measured: an unreachable host returned `rc=255` in exactly `3.00s` with `ConnectTimeout=3`. |
| `-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null` | **Makes the routing assertion orthogonal to host-key state — the Phase 4 collision guard (§Q5.4).** Cost: a `Warning: Permanently added …` line on stderr every run, which is why you **grep** the captured output rather than compare it. |
| `timeout 10 …` wrapper | **Also mandatory.** `ConnectTimeout` does **not** cover the post-connect banner exchange or auth. If nginx accepts the TCP connection but the upstream never replies, `ssh` waits on sshd's `LoginGraceTime` (120 s default). `timeout` is present in the `client` image (`/usr/bin/timeout`) and was measured killing a hung command. |
| **NOT** `-q`, **NOT** `-o LogLevel=ERROR/QUIET` | **Each suppresses the banner entirely** (§Q3.3). Measured: captured output became the empty string. |
| **NOT** `-tt` | Unnecessary (the banner needs no pty) and dangerous: `ssh -tt host </dev/null` **hung indefinitely** in research and had to be killed. |

`timeout` in the client image returns **143** (SIGTERM), not 124, when it fires. Test `rc != 0`, do
not test for a specific code.

### Determining which backend answered

Two independent readings, and **the script should take both** — that is D-45's "both protocols agree"
principle applied one level down:

| Reading | Channel | What it proves |
|---------|---------|----------------|
| The **banner** — grep the captured output for `OLD`/`NEW` | stderr | **BACK-04/SSH-03/CUT-04.** The backend asserting its own identity. This is the contractual one. |
| The **remote command** — `ssh … hostname` on stdout | stdout | Corroboration that the shell really ran there. |

Both were captured in one invocation in research:

```
Warning: Permanently added 'app.demo.test' (ED25519) to the list of known hosts.
BANNER-LINE NEW server-new
server-new
```

Anchor the grep the way BACK-03's assertions do (`^OLD server-old$` style) so a banner naming both
words cannot pass both branches.

### Recommended `scripts/verify.sh` shape (D-44/D-45)

```
usage: sh scripts/verify.sh <old|new>

1. resolve expected → OLD / NEW label
2. HTTP:  curl -fsS --max-time 5 http://localhost:9092/whoami        → capture, check rc
3. SSH:   docker compose exec -T client sh -c '<the ssh idiom above>' → capture, check rc
4. report BOTH observed values on their own labelled lines, always — the presenter reads this
5. exit non-zero if EITHER disagrees with <expected>  (EVID-05)
6. exit non-zero if the two disagree with EACH OTHER  (D-45) — with a distinct message,
   because "HTTP on NEW, SSH on OLD" is the interesting failure and deserves its own words
```

Follow `smoke.sh`/`flip.sh` conventions: POSIX `sh`, no `set -e` (so both protocols are always
reported rather than aborting after the first), `usage()` + `exit 2` on bad args, and a distinct exit
code vocabulary if useful (2 = usage, 1 = mismatch). Wire it as `make verify` alongside `make flip`.

**D-44's "shells out to `docker compose exec` or runs inside the client container" (discretion):**
recommend **shelling out from the host**, matching `flip.sh` exactly — the HTTP half already needs
`curl http://localhost:9092` from the host, and splitting the script across two execution contexts
would be worse than one `docker compose exec -T client` line.

---

## Standard Stack

No new packages, images, or dependencies are required. Everything this phase needs is already present.

### Core (all already in the repo)

| Component | Version | Purpose | Verified present |
|-----------|---------|---------|------------------|
| `nginx:1.30-alpine` | pinned in `compose.yaml` | `ngx_stream_core`, `ngx_stream_proxy`, `ngx_stream_map`, `ngx_stream_log` | ✅ `nginx -V` shows `--with-stream`; map/log modules are default-on |
| `openssh` (backend image) | Alpine 3.x / OpenSSH 10.x | sshd + `ssh-keygen -A` | ✅ `backend/Dockerfile` `apk add openssh` |
| `openssh-client`, `openssh-keygen` (client image) | Alpine 3.22 | `ssh`, `ssh-keygen`, `ssh-keyscan` | ✅ `apk info` in the running client |
| `coreutils`/busybox `timeout` | — | bounding the verify script's SSH probe | ✅ `/usr/bin/timeout` in the client |
| POSIX `sh` | — | `smoke.sh` / `flip.sh` / `verify.sh` | ✅ existing idiom |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| nginx `stream` | HAProxy / socat | Contradicts the project's core claim (CLAUDE.md: "the demo is specifically about nginx behaviour"). Rejected. |
| `AuthorizedKeysFile` on a shared volume | committed keypair, build-time bake, `exec`-push | §Q4 table — each is worse on a specific, named axis |
| SSH banner via `Banner` | `/etc/motd` + `PrintMotd` | **Technically fails D-43** — motd is absent for non-interactive invocations (§Q3). Not an alternative; a wrong answer. |
| `ssh … hostname` as the identity reading | banner grep | Both. Banner is the contract (BACK-04); `hostname` corroborates. |

**Installation:** none.

---

## Package Legitimacy Audit

**Not applicable — this phase installs no external packages.** No `npm`/`pip`/`cargo`/`apk` addition
is recommended by this research. Every image is already pinned in `compose.yaml` and every binary
required (`ssh`, `ssh-keygen`, `ssh-keyscan`, `timeout`, `nc`, `curl`) was verified present in the
running containers this session.

**Packages removed due to [SLOP] verdict:** none.
**Packages flagged as suspicious [SUS]:** none.

---

## Architecture Patterns

### System Architecture Diagram

```
                      docker network "demo"  (nothing below binds a privileged host port — D-38)

  presenter
     │  docker compose exec client ssh demo@app.demo.test        (D-37: port 22, literally)
     ▼
 ┌──────────┐   TCP :22   ┌────────────────────────── proxy (nginx 1.30) ─────────────────────┐
 │  client  │────────────▶│                                                                    │
 │          │             │  stream {                    http {                                │
 │ ssh      │   HTTP      │    upstream old :22            upstream old :80                    │
 │ ssh-key- │─────:9092──▶│    upstream new :22            upstream new :80                    │
 │  scan    │             │    ┌───────────────────────────────────────────┐                   │
 │ curl     │             │    │ include active-backend.conf  ← ONE FILE    │  ◀── D-39         │
 └──────────┘             │    │   map $server_port $active_backend        │      one word,    │
      ▲                   │    │       { default old; }                    │      both         │
      │                   │    └───────────────────────────────────────────┘      protocols    │
      │                   │       │  read by stream          read by http  │                   │
      │                   │       ▼                                 ▼      │                   │
      │                   │   proxy_pass $active_backend    proxy_pass http://$active_backend  │
      │                   │       │                                 │                          │
      │                   │   access_log /dev/stdout        access_log /dev/stdout  demo       │
      │                   │     demo_stream (D-46: NOT       access_log /var/log/demo/         │
      │                   │     the json evidence sink)        access.log  evidence            │
      │                   │                                  :8081  ← reload oracle (HTTP only │
      │                   └──────────┬───────────────────────────────┬───── proves stream? NO) │
      │                              │                               │                          
      │                    raw TCP   ▼                     HTTP      ▼                          
      │                   ┌────────────────────┐          ┌────────────────────┐               
      │                   │    server-old      │          │    server-new      │               
      │                   │ BACKEND_ID=OLD     │          │ BACKEND_ID=NEW     │               
      │                   │  sshd :22          │          │  sshd :22          │               
      │                   │   Banner ──────────┼──────────┼──▶ "OLD server-old"│               
      │                   │   AuthorizedKeysFile /keys/authorized_keys  (ro)   │               
      │                   │   ssh-keygen -A at START → host keys DIFFER ◀── Phase 4 precondition
      │                   │  nginx :80  X-Backend: OLD    │  X-Backend: NEW    │               
      │                   └─────────▲──────────┘          └─────────▲──────────┘               
      │                             │        demo-keys volume       │                           
      └──── generates keypair ──────┴───────────(ro)────────────────┘                           
            (client entrypoint, rw)                                                             

  status service ── reads /var/log/demo/access.log (JSON, ro) ── SSH lines never go here (D-46/§Q6)
```

### Recommended file layout (delta only)

```
proxy/
├── nginx.conf              # + top-level stream {} block; DEFERRED-QUESTION comment resolved (D-40)
└── active-backend.conf     # UNCHANGED — must stay five lines
backend/
├── entrypoint.sh           # + render /etc/ssh/banner from BACKEND_ID/BACKEND_HOSTNAME
├── Dockerfile              # + write /etc/ssh/sshd_config.d/10-demo.conf  (drop-in, NOT an append)
└── templates/
    └── banner.template     # new — same envsubst allowlist idiom as default.conf.template
client/
├── Dockerfile              # + ENTRYPOINT (openssh-client already present — do NOT re-add)
└── entrypoint.sh           # new — idempotent keygen into the demo-keys volume, then exec "$@"
scripts/
├── verify.sh               # new — EVID-04/05
└── smoke.sh                # + section_ssh, dispatched like the others
compose.yaml                # + demo-keys volume; rw on client, :ro on both backends. NO new ports.
Makefile                    # + verify target; logs-demo awk only if §Q6 option (b) is chosen
```

### Pattern: identity flows from one variable, never re-asserted

`BACKEND_ID` → `envsubst` → three surfaces: the HTML body (BACK-03), the `X-Backend` header (D-11),
and now `/etc/ssh/banner` (BACK-04). The proxy adds nothing. Extending the existing `VARS` allowlist
in `backend/entrypoint.sh` is the whole change — the allowlist is explicit for a reason (it would
otherwise eat nginx's own `$host`), so **add the banner template to the same `envsubst` invocation
pattern rather than introducing a second rendering mechanism.**

### Anti-Patterns to Avoid

- **Piping `ssh` output in an assertion.** Masks the exit code. Measured (§Q9). The single most
  important rule in this phase.
- **`-q` / `LogLevel=ERROR` on the verify `ssh`.** Suppresses the banner the assertion depends on.
- **Appending `AuthorizedKeysFile` to `sshd_config`.** Silently ignored (§Q4 Pitfall S-2).
- **`nc -z localhost 22` against the proxy.** IPv6-first, and the stream listener is IPv4-only (§Q8).
- **Writing stream logs to `/var/log/demo/access.log`.** Silently discarded by the status parser (§Q6).
- **Extending the compose healthcheck to cover :22.** `guard_check` would flap it unhealthy (§Q8).
- **Adding content to `proxy/active-backend.conf`.** It must stay five lines — it is the file on the
  projector. Put the label `map` in the `stream` block.
- **Any `ssh-keygen` in a build layer.** Would give both backends the same host key and destroy
  Phase 4.
- **Staging the host-key mismatch.** Anti-scope. Report and stop.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Bounding a hung SSH probe | a background PID + `sleep` + `kill` loop | `timeout 10 ssh …` | `/usr/bin/timeout` is already in the client image; the hand-rolled version races and leaks processes |
| Reading which host key :22 presents | connect + parse `ssh -v` debug output | `ssh-keyscan -t ed25519 host \| ssh-keygen -lf -` | auth-free, stable output, ~0.1 s, already installed |
| Confirming an sshd setting took effect | `grep` the config file | `sshd -T \| grep -i <keyword>` | `sshd -T` reports the **effective** value — the only check that catches the first-wins trap (§Q4) |
| Distributing the demo keypair | a bespoke sync script or `expect` | shared named volume + `AuthorizedKeysFile` | sshd re-reads the file per auth attempt; there is no ordering problem to solve |
| An uppercase OLD/NEW label in stream logs | shell post-processing of the log | a second stream-local `map` | verified working, and stays inside the config the presenter shows |
| Guarding an invalid selector on the stream side | `ngx_stream_return_module` text | nothing — let the `[error]` log line do it | an SSH client cannot render a 503; the HTTP guard catches the same typo (§Q7) |

**Key insight:** almost every temptation in this phase is to *add a mechanism* where an existing one
already covers the case. The phase's whole thesis is that one selector drives two protocols; the
implementation should stay similarly thin.

---

## Common Pitfalls

### Pitfall S-1: The pipeline that swallows the exit code
**What goes wrong:** `verify.sh` reports success while SSH failed catastrophically.
**Why:** `$?` after a pipeline is the *last* command's status. Measured: `EXIT=0` on
`Host key verification failed.`
**How to avoid:** command substitution into a variable, `rc=$?` on the next line, never a pipe.
**Warning signs:** any `ssh … | ` in an assertion; `verify.sh` that never fails in testing.

### Pitfall S-2: `sshd_config` first-directive-wins
**What goes wrong:** an appended `AuthorizedKeysFile` is silently ignored; key auth fails with a
generic `Permission denied (publickey,password,keyboard-interactive)` that looks like a key problem.
**Why:** Alpine's stock `sshd_config` has an **active** `AuthorizedKeysFile` at line 45 and
`Include /etc/ssh/sshd_config.d/*.conf` at line 15.
**How to avoid:** always use a drop-in `/etc/ssh/sshd_config.d/10-demo.conf`.
**Warning signs:** `sshd -T` disagreeing with the tail of `sshd_config`. Check `sshd -T` first, always.

### Pitfall S-3: Quiet flags silence the banner
**What goes wrong:** EVID-04 finds no `OLD`/`NEW` and the assertion "fails" for a reason unrelated to routing.
**Why:** the client prints the pre-auth banner at default log level; `-q`, `LogLevel=QUIET` and
`LogLevel=ERROR` all suppress it. Measured.
**How to avoid:** default `LogLevel`; tolerate the `Permanently added` line by grepping, not comparing.
**Warning signs:** a captured output that is exactly the empty string.

### Pitfall S-4: `localhost` vs the IPv4-only stream listener
**What goes wrong:** a smoke assertion reports the proxy's :22 closed while it is demonstrably open.
**Why:** `listen 22;` in `stream` binds `0.0.0.0` only; busybox `nc`/`wget` try `::1` first and do not retry.
**How to avoid:** `127.0.0.1` for anything probing the proxy. (`compose.yaml` already documents this
class of bug for the status healthcheck — cite it.)

### Pitfall S-5: `-tt` with no stdin hangs forever
**What goes wrong:** the smoke suite blocks; in research a command had to be killed after 120 s.
**Why:** a forced pty with `</dev/null` opens an interactive shell that never sees EOF the way it expects.
**How to avoid:** never use `-tt` in scripted paths. It is unnecessary — the banner needs no pty.

### Pitfall S-6: Long-lived SSH sessions pin old nginx workers
**What goes wrong:** `docker compose exec proxy ps` accumulates `worker process is shutting down`
entries across takes; a `ps`-based assertion becomes nondeterministic.
**Why:** D-40's intended behaviour (§Q2) — with `worker_shutdown_timeout` unset, a worker holding a
connection never exits.
**How to avoid:** bound every scripted session with `timeout`; close demo sessions between takes.
**Do NOT** "fix" it with `worker_shutdown_timeout` — that is the explicitly deferred decision.

### Pitfall S-7 (Phase 4 collision): host-key state leaking into routing assertions
**What goes wrong:** every Phase 3 SSH assertion starts failing the moment Phase 4 stages KEY-02.
**Why:** a persistent `known_hosts` plus default `StrictHostKeyChecking` makes a routing test also a
host-key test.
**How to avoid:** `-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no` in `verify.sh` and the
smoke `ssh` section, **with a comment naming Phase 4 as the reason**.

### Pitfall S-8 (inherited): the `add_header` honesty grep
`smoke.sh` asserts `grep -ci "add_header"` == 0 over comment-stripped `proxy/nginx.conf`. New stream
comments must not contain that string. Cheap to trip, cheap to avoid.

---

## Code Examples

All verified in this session against the running stack.

### The stream block, complete
```nginx
# Source: verified in proxy/nginx.conf, 2026-07-21 — nginx -t ok, reload ok, 120/120 smoke
stream {
    log_format demo_stream '$remote_addr -> :$server_port ssh backend=$stream_label '
                           'selector=$active_backend upstream=$upstream_addr status=$status '
                           'bytes=$upstream_bytes_sent/$upstream_bytes_received sess=$session_time';
    access_log /dev/stdout demo_stream;   # NEVER /var/log/demo/access.log — see §Q6

    upstream old { server server-old:22; }
    upstream new { server server-new:22; }

    include /etc/nginx/demo/active-backend.conf;   # THE SAME FILE the http block includes (D-39)
    map $active_backend $stream_label { default "?"; old OLD; new NEW; }

    server { listen 22; proxy_pass $active_backend; }
}
```
Observed log line:
`172.19.0.6 -> :22 ssh backend=OLD selector=old upstream=172.19.0.2:22 status=200 bytes=3718/4518 sess=0.089`

### sshd drop-in (the only reliable seam)
```sh
# Source: verified — `sshd -T` confirmed both values took effect and key auth succeeded
mkdir -p /etc/ssh/sshd_config.d
printf 'AuthorizedKeysFile /keys/authorized_keys\nBanner /etc/ssh/banner\n' \
  > /etc/ssh/sshd_config.d/10-demo.conf
sshd -T | grep -iE '^(banner|authorizedkeysfile)'
#   banner /etc/ssh/banner
#   authorizedkeysfile /keys/authorized_keys
```

### The verify script's SSH probe
```sh
# Source: verified — returns rc=0 and both readings; rc!=0 and empty on any failure
out=$(timeout 10 ssh \
        -o BatchMode=yes \
        -o ConnectTimeout=5 \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        demo@app.demo.test hostname 2>&1)
rc=$?                                  # ← next line. NEVER after a pipe.
# out contains, in order:
#   Warning: Permanently added 'app.demo.test' (ED25519) to the list of known hosts.
#   <banner: "NEW server-new">          ← stderr, the BACK-04/SSH-03 contract
#   server-new                          ← stdout, corroboration
```

### The auth-free routing oracle
```sh
# Source: verified — selector old then new across `sh scripts/flip.sh new`
ssh-keyscan -t ed25519 app.demo.test 2>/dev/null | ssh-keygen -lf -
#   256 SHA256:SHPajDTLtaKS2mrxhXantKpQKqoxso316yB0wHnnEZI app.demo.test (ED25519)   # == server-old
#   256 SHA256:ZOl3Mh8QHFvcIlk/N3Wiu6Jw08JtnYVe26XtX17Zewo app.demo.test (ED25519)   # == server-new
```

---

## State of the Art

| Old approach | Current approach | Impact here |
|--------------|------------------|-------------|
| Everything in one `sshd_config` | `Include /etc/ssh/sshd_config.d/*.conf` (OpenSSH 8.2+, Alpine ships it enabled) | The only reliable way to override `AuthorizedKeysFile` here (§Q4) |
| `StrictHostKeyChecking=ask` default | `accept-new` is common in modern configs; Alpine's client still prompts/auto-adds with a warning | Explains the `Permanently added` stderr noise; grep, don't compare |
| DSA / older key types | ed25519 default; `ssh-keygen -A` generates rsa + ecdsa + ed25519 | Phase 4's transfer must move **all** `/etc/ssh/ssh_host_*`, not just ed25519 |
| Separate L4 proxy (HAProxy/stunnel) | nginx `stream`, in-tree since 1.9.0, default-on under `--with-stream` | The project's whole premise; no extra component |

**Deprecated / not applicable:** nothing in this phase depends on a deprecated mechanism.

---

## Runtime State Inventory

*Not a rename/refactor/migration phase — but three runtime-state items are load-bearing enough to record.*

| Category | Items found | Action required |
|----------|-------------|-----------------|
| Stored data | `demo-keys` named volume (**new**) holding the demo keypair + `authorized_keys`; survives `down`, removed by `down -v` | Client entrypoint must be **idempotent** — regenerate only if absent |
| Live service config | sshd's effective config is read at start + `SIGHUP`; `AuthorizedKeysFile` is re-read **per authentication attempt** | No restart needed when the client writes the key; a banner change does need a HUP or restart |
| OS-registered state | **None.** D-38 publishes no host port; nothing is registered with the host OS | None — verified `docker compose ps` shows no `:22->` |
| Secrets / env vars | `BACKEND_ID` (existing, drives the banner); the demo keypair (new, volume-only, never in git, never on the host) | Add the volume path to `.gitignore` only if it is ever bind-mounted — with a named volume, nothing to ignore |
| Build artifacts | `demo-backend:1` image must be rebuilt for the banner template + drop-in; the `client` image for the new entrypoint | `make up` already runs `--build`; note it so a plain `docker compose up` without `--build` is not used to verify |

**Research-session residue:** all runtime edits made during this research (test banners, `/etc/motd`,
`sshd_config` mutations, `authorized_keys`, the appended stream block) were reverted;
`docker compose up -d --force-recreate` was run on `server-old`, `server-new`, `proxy` and `client`,
the evidence log truncated, and the suite re-verified at **120/120** with the selector on **OLD** and
the proxy's :22 **closed**. `git status` shows only the pre-existing `.planning/config.json`
modification. **Working tree clean, stack healthy, selector OLD.**

---

## Validation Architecture

`workflow.nyquist_validation` is `true` in `.planning/config.json`, so this section is required.

### Test Framework

| Property | Value |
|----------|-------|
| Framework | `scripts/smoke.sh` — POSIX `sh`, hand-rolled `assert <label> <condition>`, section-dispatched. No third-party runner. |
| Config file | none — the script *is* the config. Sections dispatched by `$1` (`backends`, `proxy`, `redirect`, `cutover`; Phase 3 adds `ssh`). |
| Quick run command | `sh scripts/smoke.sh ssh` |
| Full suite command | `make test` (== `sh scripts/smoke.sh` == all sections) |
| Current baseline | **120 assertions, 0 failures**, re-verified this session — *and re-verified green with the Phase 3 stream block live*. `sh scripts/smoke.sh proxy` = **17/17**. |

Conventions that must be honoured (established Phase 1, reaffirmed Phase 2): deliberately **not**
`set -e` so every assertion runs; any destructive assertion backs up what it touches and restores via
a `trap` on `EXIT INT TERM` (`guard_check()` is the reference implementation); every section leaves
the rig selecting **OLD**.

### Phase Requirements → Test Map

| Req ID | Behavior | Test type | Automated command | File exists? |
|--------|----------|-----------|-------------------|-------------|
| SSH-02 | `proxy/nginx.conf` contains a top-level `stream` block that `proxy_pass`es, and contains no redirect on the SSH path | unit | `sh scripts/smoke.sh ssh` — assert `grep -q '^stream {' proxy/nginx.conf` and `awk` the stream block contains `proxy_pass $active_backend` | ❌ Wave 0 |
| SSH-02 | The stream block includes **the same file** the http block includes (D-39, the phase's headline claim) | unit | assert `active-backend.conf` appears exactly **twice** in `proxy/nginx.conf` (once per context), and that `proxy/active-backend.conf` is still **5 lines** | ❌ Wave 0 |
| SSH-01 | nginx is listening on :22 inside the proxy container | integration | `docker compose exec -T proxy nc -z 127.0.0.1 22` — **`127.0.0.1`, not `localhost`** (§Q8) | ❌ Wave 0 |
| SSH-01 | An `ssh` from the `client` to `app.demo.test:22` reaches the **active** backend | integration | capture the §Q9 idiom; assert stdout contains `server-old` with selector `old` | ❌ Wave 0 |
| BACK-05 | Key auth works, non-interactively, to **both** backends directly | integration | `ssh -o BatchMode=yes … demo@server-old hostname` and `…@server-new` → `server-old` / `server-new` | ❌ Wave 0 |
| BACK-05 | The sshd settings actually took effect (guards Pitfall S-2) | integration | `docker compose exec -T server-old sshd -T \| grep -i '^authorizedkeysfile /keys'` — **`sshd -T`, not a config grep** | ❌ Wave 0 |
| BACK-04 | Each backend's banner names its own identity and hostname, anchored like BACK-03 | integration | direct `ssh …@server-old true 2>&1` captured → `grep -q 'OLD server-old'`; same for NEW | ❌ Wave 0 |
| BACK-04 | The banner is `Banner`, not motd — i.e. it survives a non-interactive invocation (D-43) | integration | the capture above uses `ssh host <command>`; passing **is** the proof | ❌ Wave 0 |
| SSH-03 | The banner survives the stream hop | integration | same capture via `app.demo.test` instead of the backend directly | ❌ Wave 0 |
| CUT-04 | The **identical** `ssh` command string returns OLD then NEW across a flip (CUT-02's SSH twin) | integration | store `CMD` in a variable; assert OLD; `sh scripts/flip.sh new`; assert **the same `$CMD`** → NEW; restore to `old` via `trap` | ❌ Wave 0 |
| CUT-04 | The host key presented at :22 changes with the selector (auth-free corroboration) | integration | `ssh-keyscan -t ed25519 app.demo.test` fingerprint == the active backend's `/etc/ssh/ssh_host_ed25519_key.pub` | ❌ Wave 0 |
| D-40 | An in-flight session survives a reload while a new one lands on the new backend | integration | background a `timeout 20 ssh … 'sleep 8; hostname'`; flip; assert the backgrounded one still reports the **old** backend and a fresh one reports the new. **Must be `timeout`-bounded (Pitfall S-6).** | ❌ Wave 0 |
| EVID-04 | `verify.sh <expected>` reports **both** protocols' observed backend on labelled lines | integration | `sh scripts/verify.sh old` → stdout names HTTP and SSH readings; exit 0 | ❌ Wave 0 |
| EVID-05 | `verify.sh` exits **non-zero** on a mismatch | integration | `! sh scripts/verify.sh new` while the selector is `old` | ❌ Wave 0 |
| EVID-05 | `verify.sh` exits non-zero when the **two protocols disagree** (D-45) — distinct message | integration | hard to induce naturally; assert the code path exists: `grep -q` for the disagreement branch **and** exercise it by pointing the SSH probe at a fixed backend | ❌ Wave 0 |
| EVID-05 | `verify.sh` cannot mask an ssh failure in a pipeline (Pitfall S-1) | unit | assert no line in `verify.sh` matches `ssh .*|` in an assertion position; and that `-q`/`LogLevel=` never appear (Pitfall S-3) | ❌ Wave 0 |
| EVID-05 | `verify.sh` terminates rather than hangs | integration | `timeout 30 sh scripts/verify.sh old` exits well under the bound | ❌ Wave 0 |
| D-38 | No host port 22 binding exists (existing assertion, must keep passing) | unit | already in `section_proxy` — **verified still passing with the stream block live** | ✅ exists |
| D-46 | The stream block never writes to the JSON evidence sink | unit | assert the stream block contains no `/var/log/demo` | ❌ Wave 0 |
| Regression | Phase 1's 17 and the full 120 survive | integration | `sh scripts/smoke.sh proxy` == 17/17; `make test` == 120+/0 | ✅ exists |

### Sampling Rate

- **Per task commit:** `sh scripts/smoke.sh ssh` (the new section only — seconds)
- **Per wave merge:** `sh scripts/smoke.sh proxy && sh scripts/smoke.sh ssh` — the 17/17 guard is the
  canonical regression tripwire and is cheap
- **Phase gate:** full `make test` green (120 + the new `ssh` section), plus `sh scripts/verify.sh old`
  exit 0 and `! sh scripts/verify.sh new`, before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `section_ssh()` in `scripts/smoke.sh` + dispatch entry + `all` inclusion — covers SSH-01/02/03,
      BACK-04/05, CUT-04, D-40, D-46
- [ ] `scripts/verify.sh` — covers EVID-04/05; it is both deliverable and test subject
- [ ] `make verify` target
- [ ] A `trap`-based restore in `section_ssh` returning the selector to **old** (the suite's invariant)
- [ ] No framework install needed — the harness exists and is the established idiom

---

## Security Domain

`security_enforcement: true`, `security_asvs_level: 1`.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard control |
|---------------|---------|------------------|
| V2 Authentication | **yes** | SSH public-key auth (`AuthorizedKeysFile`); `demo:demo` password retained as a documented, deliberately-worthless fallback (D-41). Nothing is reachable from the host — D-38. |
| V3 Session Management | no | No web sessions; SSH session lifetime is OpenSSH's concern |
| V4 Access Control | **yes** | Unprivileged `demo` user (Phase 1 `adduser -D`); keypair readable only inside the compose network; backends mount the key volume **read-only** |
| V5 Input Validation | partial | The stream proxy relays opaque bytes and parses nothing. The selector is validated on the HTTP side (`$backend_is_valid`); on the stream side an invalid value fails closed (connection closed, `status=500`) — verified §Q7 |
| V6 Cryptography | **yes** | **Never hand-rolled** — `ssh-keygen`, OpenSSH ed25519 defaults, host keys generated per container start |
| V7 Error handling / logging | **yes** | Stream access log to stdout only; **must not** reach the JSON evidence sink (§Q6). No credential ever appears in a log line |
| V14 Configuration | **yes** | Ports loopback-bound or unpublished; no privileged host port; no container-runtime socket mounted anywhere |

### Known Threat Patterns for this stack

| Pattern | STRIDE | Standard mitigation | Status here |
|---------|--------|---------------------|-------------|
| **T-03-01** Private key committed to git and later mistaken for a real credential | Information Disclosure | Generate at runtime into a named volume; never a repo file | §Q4 recommendation — **the reason the volume approach was chosen** |
| **T-03-02** Privileged host port 22 bound, colliding with or shadowing a real sshd | Tampering / DoS on the presenter's machine | D-38: publish nothing. Verified by an existing smoke assertion | Mitigated, asserted |
| **T-03-03** The SSH demo credential reachable from conference wifi | Spoofing | No host publish at all — strictly stronger than Phase 1's loopback binding | Mitigated |
| **T-03-04** `StrictHostKeyChecking=no` in the verify script normalising a genuinely unsafe habit | Spoofing (MITM) | It is scoped to a throwaway demo network with `UserKnownHostsFile=/dev/null`, and it is required to keep the routing assertion orthogonal to Phase 4 (§Q5.4). **Must carry a comment saying it is demo-only and why** — this repo is read on stage and will be copied | Accept with mandatory comment |
| **T-03-05** `StrictModes` bypassed by a world-writable key path | Elevation of Privilege | Named-volume mount is `root:root 755`; `authorized_keys` `644`, private key `600` | Verified §Q4 |
| **T-03-06** Stream log lines poisoning the JSON evidence sink and forging a `backend=` row | Tampering / Repudiation | The sink stays JSON-only from one producer; stream logs go to stdout (§Q6). The status service's mount remains read-only | Mitigated by design |
| **T-03-07** Long-lived session pinning an old worker as a resource-exhaustion vector | DoS | Non-issue at demo scale; explicitly accepted under D-40 and documented (Pitfall S-6) | Accepted, documented |

---

## Project Constraints (from CLAUDE.md)

| Directive | Effect on this phase |
|-----------|---------------------|
| Tech stack is **nginx (with `stream`) + Docker Compose** — "the demo is specifically about nginx behaviour" | HAProxy/socat are non-starters. The stream block is the mandated mechanism. |
| **SSH must be port 22** "to make the *no client change* point honestly" | D-37's in-network :22 satisfies this literally. Do not proxy on an alternate port and alias it. |
| **Must run entirely locally, no cloud account or cost** | Nothing added; no registry beyond the already-pinned images. |
| **One command to bring the whole demo up** | The keypair mechanism must work under plain `docker compose up -d --wait` (D-20), not only under `make up`. This is why the client-entrypoint + volume approach beats an `exec`-push at `make up` time. |
| GSD workflow enforcement — no direct repo edits outside a GSD command | This research made temporary edits for measurement and reverted all of them; tree verified clean. |

---

## Assumptions Log

| # | Claim | Section | Risk if wrong |
|---|-------|---------|---------------|
| A1 | `ngx_stream_map_module` is opt-*out* (`--without-stream_map_module`) rather than opt-in, which is why it is absent from `nginx -V` output | §Q1 | **Low** — the *behaviour* is VERIFIED (the map works); only the build-flag explanation is from training knowledge. If the planner wants the sentence in a config comment, phrase it as "included by default under `--with-stream`" rather than naming the flag. |
| A2 | sshd re-reads `AuthorizedKeysFile` on **every** authentication attempt (hence no start-ordering race) | §Q4 | **Low-medium.** Strongly supported by the verified test (the file was created after sshd started and auth succeeded without a HUP), but not read from the OpenSSH source this session. If wrong, the mitigation is a client-side `pkill -HUP sshd` — cheap. **Worth confirming during execution with a deliberate late-write test.** |
| A3 | sshd's `LoginGraceTime` default is 120 s, which is the worst-case hang the `timeout` wrapper guards against | §Q9 | **Low** — the `timeout` wrapper is correct regardless of the exact number; only the stated figure would be wrong. |
| A4 | Phase 4's host-key transfer will work because `ssh-keygen -A` only generates *missing* keys | §Q5.3 | **Low, and it is Phase 4's problem.** Reported as inheritance, not relied on here. Phase 4 should verify it. |
| A5 | The `Warning: Permanently added` line appears on **every** run under `UserKnownHostsFile=/dev/null` | §Q9 | **None** — VERIFIED in four separate invocations. Listed only because the verify script's output formatting depends on it. |

---

## Open Questions

1. **Stream log field name: `backend=` or `selector=`? (§Q6)**
   - *What we know:* both work; `backend=` gets `make logs-demo` colouring free; the two fields carry
     epistemically different claims (backend self-report vs proxy selector).
   - *What's unclear:* whether the project's honesty discipline (D-11's "no tier synthesises an
     identity") should extend to field *naming*.
   - *Recommendation:* emit **both** — `backend=OLD selector=old` — and comment the distinction. Costs
     one token on the line and forecloses the argument.

2. **Should the client's `known_hosts` be persisted in a volume?**
   - *What we know:* Phase 3 explicitly must **not** need it (assertions use `/dev/null`). Phase 4
     needs `known_hosts` to persist across a flip, which it already does within a take.
   - *What's unclear:* whether Phase 4 wants persistence across `docker compose down` too.
   - *Recommendation:* **do not add it in Phase 3.** Leave the decision entirely to Phase 4. Flagged
     here so Phase 4 does not have to rediscover it.

3. **Does `make logs-demo`'s `awk` need extending?**
   - Depends entirely on question 1. If `backend=OLD` is emitted, no Makefile change at all.

4. **Should `flip.sh` gain an SSH-side proof (a step-5 analogue)?**
   - *What we know:* one reload covers both contexts (verified). The `:8081` oracle proves the HTTP
     side only (§Q8). `verify.sh` will prove both, on demand.
   - *Recommendation:* **leave `flip.sh` alone.** It is a carefully-tuned six-step sequence with
     measured timings; adding an SSH handshake to the money-shot command adds latency and a new
     failure mode on stage. `verify.sh` is the right home for the SSH proof, and D-44 says so.

---

## Environment Availability

| Dependency | Required by | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Docker Engine | everything | ✓ | 29.5.3 | — |
| Docker Compose | everything | ✓ | 5.1.4 | — |
| `nginx:1.30-alpine` with `--with-stream` | SSH-02 | ✓ | pinned, running | — |
| `ngx_stream_map_module` | D-39 | ✓ | **behaviourally verified** | — |
| `openssh` sshd in the backend image | BACK-04/05 | ✓ | Alpine pkg, running under supervisord | — |
| `ssh` / `ssh-keygen` / `ssh-keyscan` in the client image | SSH-01, EVID-04 | ✓ | `openssh-client-default`, `openssh-keygen` | — |
| `timeout` in the client image | EVID-04 | ✓ | `/usr/bin/timeout` | — |
| `nc` in the proxy image | smoke `ssh` section | ✓ | busybox | `curl` cannot do a bare TCP check; `nc` is required |
| POSIX `sh`, `sed`, `awk`, `diff` on the host | scripts | ✓ | macOS defaults, already exercised by 120 assertions | — |
| Host port 22 | — | **not needed** (D-38) | — | n/a |

**Missing dependencies with no fallback:** none.
**Missing dependencies with fallback:** none.

---

## Sources

### Primary (HIGH confidence)
- **Direct execution against the running stack**, 2026-07-21 — every §Q finding. Specifically:
  `nginx -t`, `nginx -s reload`, `netstat -lnt`, `ps` in the proxy container; `ssh`, `ssh-keyscan`,
  `ssh-keygen -lf`, `timeout` from the client container; `sshd -T`, `pkill -HUP sshd` in both
  backends; `docker compose logs proxy`; `docker volume create`/`docker run` ownership probe;
  `sh scripts/smoke.sh` (full, 120/120) and `sh scripts/smoke.sh proxy` (17/17) **with the stream
  block live**, and again after revert.
- Repository source read in full: `proxy/nginx.conf`, `proxy/active-backend.conf`, `compose.yaml`,
  `backend/{Dockerfile,entrypoint.sh,supervisord.conf}`, `client/Dockerfile`, `scripts/smoke.sh`,
  `scripts/flip.sh`, `status/status.py`, `Makefile`.
- `.planning/` artifacts: `REQUIREMENTS.md`, `ROADMAP.md`, `03-CONTEXT.md`, `01-CONTEXT.md`,
  `02-CONTEXT.md`, `02-VALIDATION.md`, `.claude/CLAUDE.md`, `.planning/config.json`.

### Secondary (MEDIUM confidence)
- Alpine's stock `/etc/ssh/sshd_config` as shipped in the running `server-old` container (line
  numbers 15 and 45 read directly — this is primary for *this* image, secondary as a general claim
  about Alpine).

### Tertiary (LOW confidence)
- Training knowledge only, flagged in the Assumptions Log: the `--without-stream_map_module` build-flag
  name (A1), sshd's per-attempt `AuthorizedKeysFile` read semantics (A2), and the 120 s
  `LoginGraceTime` default (A3). **No web search was performed** — every question in the brief was
  answerable by experiment on the running stack, which is a stronger source.

---

## Metadata

**Confidence breakdown:**

| Area | Level | Reason |
|------|-------|--------|
| D-39 shared selector across contexts | **HIGH** | Executed end to end, both directions of a flip, 120/120 regression clean |
| D-40 reload / in-flight sessions | **HIGH** | Directly observed, including the `worker process is shutting down` state |
| Banner mechanism (D-42/D-43) | **HIGH** | Four invocation shapes compared; the `-q`-suppression trap measured |
| Key distribution (D-41) | **MEDIUM-HIGH** | Every component verified individually; the assembled `client`-entrypoint + volume wiring was not built end to end (that is the phase's work). A2 is the residual assumption. |
| Phase 4 inheritance (§Q5) | **HIGH** | The `REMOTE HOST IDENTIFICATION HAS CHANGED` failure reproduced verbatim through the proxy |
| Stream logging (§Q6) | **HIGH** | Log line produced; the status parser's skip-on-`ValueError` behaviour read from source |
| Regression surface (§Q7) | **HIGH** | Full suite executed with the stream block live, including the `guard_check` worst case |
| Verify-script mechanics (§Q9) | **HIGH** | The exit-code-masking bug and the banner-suppression bug both reproduced |

**Research date:** 2026-07-21
**Valid until:** ~2026-08-20 (30 days). The findings are pinned to `nginx:1.30-alpine` and
`alpine:3.22`; they go stale only if those pins move. `[VERIFIED: images pinned in compose.yaml]`

**Working tree at end of research:** clean (only the pre-existing `.planning/config.json`
modification). **Stack:** healthy, all five services up, selector on **OLD**, proxy :22 closed,
`make test` **120/120**.

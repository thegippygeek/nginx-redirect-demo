# WALKTHROUGH — the presenter's script

Read this one in order. `README.md` is the reference material that explains how the rig
works; this document is the script you actually run, in front of people, under time
pressure. Every step carries three blocks in the same order — **Run**, **Expect**, **Say** —
so you can find the one you need by position rather than by reading.

The demo shows a hostname being migrated from one server to another with nobody on the
client side changing anything. This is the v2 story: there are now **two full stacks**
behind the switch, so you validate the new one end to end *before* you commit, flip both
protocols over in one reload, walk straight into the one thing that genuinely breaks on
migration day — SSH host-key verification — fix it the wrong way and then the right way,
**roll the whole thing back in a single reload with nothing torn down**, and finish by
proving the old stack was never touched at all. Eleven beats, about **fifteen minutes**
with narration, or **eight** if you skip the browser contrast.

---

## Pre-flight checklist

Every item below has already caused a real failure during this project's own development.
Work through them before the room fills up, not while it watches.

- [ ] **The hosts entry is present.** One-time, by hand, on your machine:
      `echo '127.0.0.1  app.demo.test' | sudo tee -a /etc/hosts`.
      The browser runs outside Docker and cannot query Docker's DNS. Without this line the
      browser and the `client` container are using two different names on stage, and *"the
      hostname never changed"* is the exact claim this demo rests on.
- [ ] **The rig is up and green.** Run `make up`, then confirm with `make status`: every
      service `healthy` or `running`, and a `hosts: OK` line at the foot. `make up`
      builds — a plain `docker compose up -d` without a build can leave you verifying
      against a stale image. `make up` also clears the evidence log for you.
- [ ] **A private / incognito browser window is already open.** A `301 Moved Permanently`
      is cacheable *indefinitely* by specification and browsers honour that enthusiastically.
      In a normal window a second take jumps straight to the target without ever contacting
      nginx, no redirect appears in the log, and the contrast beat quietly lies to the room.
- [ ] **The evidence log is cleared.** `make up` does it; `make clear-evidence` is the
      explicit lever. Otherwise the projected status page opens mid-count with a previous
      take's numbers and everything looks second-hand.
- [ ] **The selector is on OLD.** `make flip-old` puts it back and clears the evidence in
      the same command. The demo opens and closes on OLD.
- [ ] **The gotcha is armed.** The two backends must be presenting *different* SSH host
      keys. A fresh `make reset` guarantees it (about 16 s, full rebuild — the documented
      re-arm path). Between takes, `make rearm` reaches the same state in about a second
      without a rebuild.
- [ ] **The Docker hint block is suppressed** in the shell you will present from:

      export DOCKER_CLI_HINTS=false

      Compose appends a trailing `What's next: … Gordon → docker ai …` block after any
      command that exits non-zero — but **only when output is a terminal**. So it never
      appears in the test suite and always appears on the projector, directly underneath
      the failure the room is meant to be reading. `make ssh` sets it for you; exporting it
      covers everything else you type.
- [ ] **The status page is full-screened on the second display:** `http://localhost:9094/`.
      It refreshes itself once a second. Put it there and forget it exists.

---

## The demo

### 1. Validate the new stack, pre-cutover

**Run**

```bash
make verify-new-stack
```

**Expect** — one HTTP request and one SSH connection, taken from inside the `client`
container straight at the new stack's own alias `app-new.demo.test`, both reporting NEW
*before you have flipped anything*:

```
VERIFY: expecting NEW over app-new.demo.test (pre-flip, direct to the new stack, from the client container)
HTTP  http://app-new.demo.test/whoami   ->  NEW server-new
SSH   demo@app-new.demo.test:22          ->  NEW server-new  [banner; remote hostname: server-new]
OK  both protocols report NEW — the expectation holds on HTTP and on SSH.
```

**Say** — "Before I touch live traffic I want to know the destination is actually up. This
talks directly to the new stack on its own name and it answers NEW on both protocols —
while the switch in front of it is still sending every real request to the old box. That is
what the two-stack topology buys you over a naive cutover: you commit to the flip *after*
you have seen the new side answer, not before and hope."

### 2. Show OLD through the switch

**Run**

```bash
make verify
```

**Expect** — the amber **OLD** banner in the incognito window at
`http://app.demo.test:9092/`, with the URL bar still reading exactly what you typed, and in
the terminal:

```
VERIFY: expecting OLD (selector word: old)
HTTP  http://localhost:9092/whoami       ->  OLD server-old
SSH   demo@app.demo.test:22              ->  OLD server-old  [banner; remote hostname: server-old]
OK  both protocols report OLD — the expectation holds on HTTP and on SSH.
```

**Say** — "Same address, the one the audience uses. Right now everything lands on the old
box, over HTTP *and* over SSH, and the name I typed is the name I am still looking at.
Somebody answered on my behalf and I cannot tell from here which somebody it was. That
gap between what I typed and who answered is the whole migration."

### 3. The redirect contrast — the other way

**Run**

```bash
make contrast
```

**Expect**

```
PROXIED   9092 ->
  final=http://localhost:9092/whoami  redirects=0
REDIRECT  9093 ->
  final=http://app.demo.test:9090/whoami  redirects=1
```

**Say** — "Same destination, two mechanisms. Port 9092 proxied me and my address never
moved — zero redirects. Port 9093 told me to go somewhere else and I went, so I am now
holding a different address, and my browser will remember it. That is the difference
between a migration the client never notices and one it has to be told about. Everything
after this is the first mechanism."

*(If you have the projector on the browser, put the two tabs side by side instead: `:9092`
leaves the URL bar alone, `:9093` visibly rewrites it to `:9090`. The URL bar is the whole
argument. This is the beat that needs the incognito window.)*

### 4. Prime the SSH trust on OLD — load-bearing, do not skip

**Run**

```bash
make ssh
```

**Expect** — the old server's pre-auth banner and a shell on it. Type `exit` to come back.

```
OLD server-old
server-old:~$
```

**Say** — "That first line is the machine naming itself before I have even authenticated.
My SSH client has just written down which key this name presented, and it will hold that
record until something contradicts it. That is not me being paranoid — every SSH client on
earth does this by default, which is exactly why the next few minutes matter."

*This step is what arms the gotcha, and it is the one that gets fumbled.* The client's trust
record is keyed on **the name you typed**, so connecting to a backend's own service name
records a different, useless entry and nothing will fire later. `make ssh` hard-codes the
proxied hostname so it cannot be got wrong. Worth stating out loud once: `make ssh` records
an *unseen* host on first sight and still refuses a *changed* one — that is a different
thing from switching host-key verification off, which this demo never does and never
teaches.

### 5. The flip — one word, one reload

**Run**

```bash
make flip-new
```

**Expect** — the diff is what the room watches change, followed by the config test, the
graceful reload and one confirming request:

```
FLIP: old -> new

--- switch/active-proxy.conf (before)
+++ switch/active-proxy.conf (after)
@@ -1,5 +1,5 @@
 # switch/active-proxy.conf — THE ONLY FILE THE PRESENTER EDITS
 # Change old to new to cut over. Nothing else.
 map $server_port $active_backend {
-    default old;
+    default new;
 }

nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful

curl -fsS http://localhost:9092/whoami  ->  NEW server-new
```

**Say** — "One word, in a five-line file, two of them comments. No container restarted, no
client reconfigured, no DNS change, no address change. Reload the browser and the identical
request is now answered by the other box." *(Then reload the incognito tab: the banner goes
green **NEW**, the URL bar has not moved. On the status page, `CONFIG SAYS NEW` sits above
`TRAFFIC SHOWS OLD` for a beat and then the two readings converge — that gap is the cutover
happening.)*

### 6. The gotcha  ⚠ DESTRUCTIVE — re-arm with `make rearm` before the next take

**Run**

```bash
make ssh
```

**Expect** — thirteen lines and a hard refusal. The fingerprint on the eighth line is the
new server's and is different on every run, so do not compare it to anything:

```
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@    WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!     @
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
IT IS POSSIBLE THAT SOMEONE IS DOING SOMETHING NASTY!
Someone could be eavesdropping on you right now (man-in-the-middle attack)!
It is also possible that a host key has just been changed.
The fingerprint for the ED25519 key sent by the remote host is
SHA256:<a different value on every run>.
Please contact your system administrator.
Add correct host key in /root/.ssh/known_hosts to get rid of this message.
Offending ED25519 key in /root/.ssh/known_hosts:1
Host key for app.demo.test has changed and you have requested strict checking.
Host key verification failed.
```

Exit status: **255**. The last line on screen is `Host key verification failed.` — provided
`DOCKER_CLI_HINTS` was exported in pre-flight.

**Say** — "Nothing about the hostname changed. Nothing about the port changed. What changed
is *which machine is behind them* — and my client noticed, because the proxy relayed the
server's real key straight through without touching it. That is also the proof that this is
a raw TCP relay and not something terminating my connection: a device that terminated it
would have presented its own key and I would never have known the backend moved. This is
the thing that actually breaks on migration day, and it breaks for every client at once."

*If it does not fire:* you skipped beat 4, or the fix is still applied from a previous take,
or you never flipped. Three conditions have to hold together — a trust record for
`app.demo.test` recorded while the selector was on old, two backends still presenting
different keys, and a flip. A session left open *before* the flip keeps talking to its
original backend for its whole life, so an old terminal will show nothing at all. Open a
new one.

### 7. The wrong fix — the instinct, and it works

**Run**

```bash
docker compose exec client ssh-keygen -R app.demo.test
make ssh
```

**Expect**

```
# Host app.demo.test found: line 1
/root/.ssh/known_hosts updated.
Original contents retained as /root/.ssh/known_hosts.old
Warning: Permanently added 'app.demo.test' (ED25519) to the list of known hosts.
NEW server-new
server-new:~$
```

**Say** — "That is what everybody reaches for, and look: it works. Now count what it cost.
It was two commands, not one — deleting the record did not connect me, it removed my
client's *objection*; I still had to trust whatever answered next, and I trusted it without
checking anything. And it fixed exactly one machine. That record lives on every laptop,
every CI runner, every jump box, every automation controller that has ever connected to this
name. How many of those can you reach this afternoon?"

*Back to the armed state before beat 8:* `make rearm`, then `make flip-old`, then `make ssh`
(type `exit`), then `make flip-new`. Four commands, about ten seconds. You are re-priming
the client against the old box and flipping again, which is beats 4 and 5 replayed.

### 8. The right fix — move the identity, not the objection

**Run**

```bash
make fix-hostkeys
make ssh
```

**Expect** — the fix reports in under a second, and the *identical* command that failed in
beat 6 now lands on the new server without a single client-side edit:

```
FIX: transferring server-old's host keys to server-new
  streaming six host-key files (/etc/ssh/ssh_host_*)
  telling sshd on server-new to load them (SIGHUP, pid preserved)
  SHA256:<the old server's fingerprint>  (ED25519, now presented by BOTH servers)
done — server-new is wearing server-old's cryptographic identity.

NEW server-new
server-new:~$
```

**Say** — "I did not touch the client. Its trust record is byte-for-byte what it was before
— same file, same single line. What changed is the server: the new box now presents the old
box's cryptographic identity, and I told the running daemon to pick it up, because sshd
loads its keys once at startup and a file copy on its own does nothing. **Cryptographic
identity inherited, application identity new** — the banner still says server-new, but the
key it presented is server-old's. That is what a real cutover does, because you cannot reach
into every client on the network and tell it to forget something."

*This survives a container restart* — the entrypoint's key generator only fills in keys that
are missing, so a restart mid-demo cannot ambush you by undoing it. The reasoning in full is
in `scripts/fix-hostkeys.sh`.

### 9. Instant rollback — no teardown

**Run**

```bash
make flip-old
make verify
```

**Expect** — one switch reload sends both protocols back to OLD; `make flip-old` truncates
the evidence log and issues no request of its own, so the confirmation is the follow-up
`make verify`, not a status-page counter:

```
FLIP: new -> old

--- switch/active-proxy.conf (before)
+++ switch/active-proxy.conf (after)
@@ -1,5 +1,5 @@
-    default new;
+    default old;

VERIFY: expecting OLD (selector word: old)
HTTP  http://localhost:9092/whoami       ->  OLD server-old
SSH   demo@app.demo.test:22              ->  OLD server-old  [banner; remote hostname: server-old]
OK  both protocols report OLD — the expectation holds on HTTP and on SSH.
```

**Say** — "Watch what I did *not* do. I did not tear anything down, I did not rebuild, I did
not restart a container. One word back, one reload, and both protocols are on the old box
again — this is the rollback you actually want at 2am when the new stack misbehaves. And
notice I confirm it with `make verify` rather than reading the projected counters: `make
flip-old` is the reset direction, it zeroes the evidence log and issues no traffic of its
own, so the honest confirmation is a fresh request, not a number the flip just cleared."

### 10. The old proxy was never touched

**Run**

```bash
make proxies-untouched
```

**Expect** — the sha256 of the two static proxy configs, identical to what they were before
the whole cutover-and-rollback cycle:

```
c08ead2d84bacde04367ef87b28cf8c2310c8fec345b2b51846ecac590e022cb  proxy-old/nginx.conf
1eea86ad2945330cabb01a7d27d900e5cbbe68d15d13317b204f207d4cb01736  proxy-new/nginx.conf
```

**Say** — "This is the proof, not the claim. Across everything we just did — validate,
flip, break, fix, roll back — the only file that ever changed is one word in the switch's
selector. The two proxies in front of the backends are byte-for-byte what they were when we
started; here are their checksums. Nothing about the old path was disturbed to stand the new
one up, which is exactly why the rollback was a single reload and not a recovery."

### 11. Reset for the next take

**Run**

```bash
make reset
```

**Expect** — a full teardown and rebuild, ending on the status table:

```
demo-old     Up (healthy)
demo-new     Up (healthy)
demo-proxy   Up (healthy)
hosts: OK  app.demo.test -> 127.0.0.1
```

**Say** — nothing; this is between takes. *(For the record, out loud if anyone asks: it
tears the rig down with volumes, rebuilds, regenerates both backends' host keys and rewrites
the selector back to `old`.)*

`make reset` is the documented re-arm path: about **16 seconds**, and it leaves everything
— selector, evidence log, both key sets, the client's trust record — in the state a cold
checkout starts in. If you are running takes back to back, `make rearm` reaches the armed
key state in about **one second** in place, with no rebuild: it gives the new server a fresh
identity and clears the client's trust record, but it does **not** flip the selector back or
clear the evidence log — pair it with `make flip-old` if you want the full opening state.
Its reasoning is in `scripts/rearm.sh`.

---

## Known traps

Every one of these has already bitten during development.

- **The browser caches the 301.** The contrast beat needs a private / incognito window, or
  devtools with "Disable cache" ticked. In a normal window the second take never contacts
  nginx at all, no redirect is logged, and the contrast beat silently stops being a
  contrast. `make contrast` on the command line is immune — `curl` does not cache — and is
  the backup path when a projector cannot show a URL bar.
- **SSH runs from the `client` container, and that is not a cheat.** Inside the Docker
  network the proxy genuinely listens on **port 22**, so "SSH on port 22, no client-side
  change" is literally true — there is no `-p` flag anywhere in this demo. Binding a
  privileged port on your laptop would depend on host state and would simply fail on any
  machine already running its own `sshd`. Nothing here publishes port 22.
- **Port 9093 does not follow the flip.** After the cutover, `:9092` lands on NEW while
  `:9093` still redirects clients to the original backend on `:9090`. That is deliberate and
  worth saying out loud rather than being caught by it mid-demo: the proxy is the migration
  mechanism and the redirect is not. A redirect hands the client a new address and the
  client keeps it — often indefinitely — so it cannot be moved back and forth the way an
  upstream can. The status page counts only 9092 traffic for the same reason.
- **`make flip-old` is the reset direction, and it truncates the evidence log.** The
  rollback beat confirms with `make verify`, never with the projected counters, because
  `flip-old` zeroes the evidence log and issues no confirming request of its own (that is
  what keeps a reset from flashing a stale convergence sequence). If you narrate the status
  page during the rollback you will be describing numbers the flip just cleared. Re-confirm
  with a fresh request.
- **`make reset` is the re-arm path.** The host-key gotcha only fires while the two backends
  present different keys, and the right-fix beat deliberately destroys that. `make reset`
  (about 16 s, full rebuild) is the documented way back; `make rearm` (about 1 s, in place)
  is the between-takes fast path. Re-arming the keys is not enough on its own — you must
  re-prime the client on the old box, which is the priming beat.
- **`make verify` cannot see a host-key problem, by design.** It pins the test-mode SSH
  options, which discard the client's trust record entirely, so it is structurally incapable
  of noticing that a host key changed. This has been measured: presenter-mode SSH failing
  with status 255 at the same moment `make verify EXPECT=new` printed `OK  both protocols
  report NEW` and exited zero. **Never reach for it to diagnose the gotcha** — you will
  conclude the rig is fine and the failure was a fluke. It is answering a different question:
  *"did the routing land?"*, not *"does the client trust what it landed on?"* That is a
  feature, and it is the sharpest illustration there is of why this repository has two named
  connection modes. See `README.md` for both of them.
- **An already-open session sees nothing.** A terminal opened before the flip keeps talking
  to its original backend for its whole life — that is what *graceful* means. Every beat
  after a flip needs a fresh connection.

---

*Reference material, the two connection modes, the exit-code vocabulary and the mechanism
itself: `README.md`. The one file the cutover edits: `switch/active-proxy.conf`. The fix
and the re-arm, with their reasoning in full: `scripts/fix-hostkeys.sh` and
`scripts/rearm.sh`.*

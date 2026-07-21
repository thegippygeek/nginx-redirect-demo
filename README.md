# Server Migration Redirect Demo

A laptop-local Docker Compose rig that shows a hostname being migrated from one
server to another with nginx — and the client never noticing.

Two backends (`server-old`, `server-new`) built from **one image**, differing only
in an identity env var. An nginx proxy in front of them. The audience watches a
request land on OLD, watches one word change in one small file, and watches the
same request land on NEW without a single client-side change.

Phase 1 brings the rig up and proves HTTP lands on OLD through the proxy,
alongside the 301-redirect approach for contrast. Phase 2 adds **the cutover
itself** — one word, one reload, no restart — and **the projected status page on
port 9094** that lets a room watch it happen. Phase 3 puts **SSH on port 22**
through the same proxy and the same one-word selector, and adds `make verify`,
which asserts both protocols landed on the same backend. Phase 4 adds **the SSH
host-key gotcha** — the thing that genuinely breaks on migration day — and the
fix that scales to a real fleet. All four are covered below.

**Running the demo? Read [`WALKTHROUGH.md`](WALKTHROUGH.md) instead.** This
README is reference material, organised by subject and read out of order. The
walkthrough is the script: eight beats, in order, each with the exact command,
the output to expect and what to say. They are deliberately not copies of each
other.

---

## One-time setup — a prerequisite, not a startup step

Your host machine needs `app.demo.test` to resolve to `127.0.0.1`:

```bash
echo '127.0.0.1  app.demo.test' | sudo tee -a /etc/hosts
```

**Why this exists.** The browser runs on your host, outside Docker, and cannot
query Docker's embedded DNS. The `client` container resolves `app.demo.test`
through Docker DNS for free; the browser cannot. Without the `/etc/hosts` line
the browser and the `client` container would be using two different names on
stage — and "the hostname never changed" is the exact claim this demo rests on.
One name, both clients (D-03, D-04).

**This is a host-OS change, performed once, by hand, by you.** Nothing in this
repository writes to `/etc/hosts` or escalates privileges — no setup script, no
`make install`, no bootstrap step. The line above is the only host state the
demo touches, and removing that line is the complete uninstall. `make status`
checks for the entry and prints this exact command if it is missing.

It is a prerequisite for the **browser** demo only. Every automated check passes
without it — the `client` container uses Docker DNS, and the host-side checks use
`localhost`.

---

## Starting the demo

```bash
docker compose up -d --wait
```

That is the whole thing. One command, no arguments, no environment file.

A Makefile is provided as a convenience wrapper, and `make up` does the same
thing plus an evidence-log clear and a status print. The Makefile is **convenience only** — nothing
essential is hidden behind it, and every target is a one-line `docker compose`
invocation you could type yourself (D-20).

---

## Ports

| Port | Service | Role |
|------|---------|------|
| 9090 | `server-old` | direct access to the Old box |
| 9091 | `server-new` | direct access to the New box |
| 9092 | `proxy` | **the migration endpoint** — transparent reverse proxy |
| 9093 | `proxy` | the redirect listener — the other way of doing it |
| 9094 | `status` | **the projected status page** — the surface the room watches |

**Narration mnemonic:** *"90 is the Old box, 91 is the New box, 92 proxies, 93
redirects, 94 shows you."* Five adjacent numbers, monotonic, and the "92 proxies
/ 93 redirects" pairing is the one line that keeps them straight while you talk.

The direct backend ports exist for a reason beyond convenience: they let you say
"here are two separate boxes" *before* nginx enters the story, and they give the
301 redirect a real, reachable destination to point at (D-05).

All five are bound to `127.0.0.1` only. The rig is never offered to conference
wifi.

---

## The contrast demo (HTTP-04)

This is the conceptual crux. Same destination, two different mechanisms — and
only one of them is invisible to the client.

### In the browser (the primary path)

**Open a private / incognito window first.** This matters more than it sounds:
a `301 Moved Permanently` is cacheable **indefinitely** by specification, and
browsers honour that enthusiastically. In a normal window, a second run jumps
straight to the target without ever contacting nginx — no 301 appears in the
log, and the demo looks broken on stage. A private window, or devtools with
"Disable cache" ticked, avoids it entirely.

1. Visit **`http://app.demo.test:9092/`** — the amber **OLD** banner appears.
   The URL bar still reads `app.demo.test:9092`, exactly what you typed.
   *Someone answered on your behalf and you cannot tell.*

2. Visit **`http://app.demo.test:9093/`** — the same amber **OLD** banner, but
   the URL bar has visibly changed to `app.demo.test:9090`.
   *You were told to go somewhere else, and you went.*

Put the two tabs side by side. The difference in the URL bar is the entire
point: only the first mechanism lets a migration happen without the client
changing anything.

### On the command line (the backup path)

```bash
make contrast
```

```
PROXIED   9092 ->
  final=http://localhost:9092/whoami  redirects=0
REDIRECT  9093 ->
  final=http://app.demo.test:9090/whoami  redirects=1
```

Two labelled lines, one command — the technical backup view for when a projector
cannot show a URL bar (D-09). `curl` does not cache, so this path is immune to
the 301-caching trap above and can be run as many times as you like.

Note: the redirect target is reachable from the **host browser** (via the
`/etc/hosts` entry plus the published 9090), but **not** from inside the `client`
container, where `app.demo.test` resolves to the proxy — which does not listen
on 9090. Do not demo the redirect from inside the client container; the browser
is its home.

---

## The cutover (CUT-01/02/03/05 — the money shot)

The flip changes **one word** in `proxy/active-backend.conf` and reloads nginx.
Nothing restarts, nothing on the client side changes, and the identical command
now gets a different box.

### Three commands, one mechanism

```bash
make flip-new     # cut over to the New box
make flip-old     # cut back — this is also the between-takes reset
make flip         # toggle whatever is currently selected
```

`make flip` is the memorable one and the fastest to type. The named targets are
the unfumbleable ones: if you have lost your place on stage, `make flip-new` does
what it says regardless of where the rig currently is (D-33).

Each one prints the diff before it reloads. **That diff is what the audience
watches change:**

```diff
--- proxy/active-backend.conf (before)
+++ proxy/active-backend.conf (after)
@@ -1,5 +1,5 @@
 map $server_port $active_backend {
-    default old;
+    default new;
 }
```

Then it validates the config, reloads gracefully, proves the reload actually
landed by asking the running config what it now selects, waits for the worker
handover, and issues one confirming request:

```
curl -fsS http://localhost:9092/whoami  ->  NEW server-new
```

That confirming request exists to seed the status page's traffic reading for the
take that is *starting*. `make flip-old` is the reset direction and therefore
issues no request at all — it clears the evidence instead, and says so.

Run the same command from anywhere — the host, the `client` container, a
browser — and the URL is the one you always typed. That is the whole claim.

### The more dramatic option: edit it live

If you would rather have the file open on screen and change the word by hand,
do — then `make reload`. The file is five lines, two of them comments, and the
edit is one word. Phase 1's `$backend_is_valid` guard exists precisely for this
path: a typo'd selector still passes `nginx -t` and still reloads cleanly, and
without the guard it would 502 every request mid-cutover. With it you get a
legible 503 that names the offending value on screen (D-34).

### The flip refuses when a backend is down

```
REFUSING TO FLIP: server-new is not answering /healthz.
  nginx parses BOTH upstream blocks on every reload, so this would
  fail in either direction and the running config would silently
  stay put. proxy/active-backend.conf has NOT been modified.
```

This is not defensiveness for its own sake. nginx resolves upstream hostnames at
config-parse time and parses **both** `upstream` blocks on every reload, so one
dead backend blocks the flip in *both* directions — and a reload whose config
fails to load leaves nginx quietly serving the previous configuration. The gate
runs before the file is touched, so a refusal leaves the repo byte-identical
rather than claiming a cutover that never happened (D-35).

### Watching it happen

```bash
make logs         # raw, all three services — the authentic view
make logs-demo    # the same log, colour-labelled OLD/NEW, readable from the back
```

Both tail the proxy **and** both backends (D-32). Seeing the request arrive at
`server-new` is what proves it truly landed there rather than being answered
from somewhere upstream. `make logs` is the one for a technical audience;
`make logs-demo` prefixes a colour-coded `OLD`/`NEW` label so the moment the
flip lands is visible across a room.

### Between takes

```bash
make flip-old         # flips back AND clears the evidence
make clear-evidence   # clears the evidence without flipping
```

`make flip-old` is the between-takes reset (D-36). It puts the rig back on OLD
and truncates the evidence log, so the next take's counters, request table and
since-flip clock all start from zero — nothing looks second-hand. **No container
is restarted**, which is the point CUT-05 exists to make.

Phase 1's `make reset` is still there and still does a full teardown, but it is
not the between-takes path: using it would undercut the "no teardown needed"
claim the cutover is demonstrating.

`make up` also clears the evidence. The log lives in a named volume that survives
`docker compose down`, so without that a down-and-up cycle would resume a previous
take's counters mid-count — which looks second-hand, which is the exact thing the
reset exists to prevent. Raw `docker compose up -d --wait` still works standalone
and simply inherits the prior log; `make clear-evidence` is the explicit lever.

---

## The status page — what the room watches (EVID-02, EVID-03)

```
http://localhost:9094/
```

**Put this on the projector before you start, and leave it there.** It is not a
confidence monitor for you and it is not an after-the-fact artifact — it is the
surface the audience is looking at while you flip. Full-screen it on the second
display and then forget it exists.

Three properties worth knowing before you rely on it:

- **It refreshes itself once a second.** You never reach for a key mid-flip. The
  flip lands on screen on its own (D-24).
- **Nothing on it is clickable.** It is non-interactive by contract (D-24) — no
  buttons, no links, no controls, no hover states. If something on it looks
  clickable, that is a defect, because it teaches the room that you are driving
  the page when you are not.
- **It reads the evidence, it does not produce it.** Both of its mounts are
  read-only. The tier that reports the evidence provably cannot alter it, which
  is what makes the reading believable rather than merely nice.

### The two readings, and why they are deliberately separate

The page shows two things, one above the other, never merged:

```
CONFIG SAYS      [ NEW ]        <- what the file on disk selects
                                <- the sync marker sits between them
TRAFFIC SHOWS     O L D         <- what the access log actually recorded
```

**`CONFIG SAYS`** is read from `proxy/active-backend.conf` — your stated intent,
the moment you save the file. **`TRAFFIC SHOWS`** is read from the proxy's access
log — what nginx actually did, which is a different question and, for a few
seconds, a different answer.

Between the two sits a marker carrying one of three captions:

| Marker | Meaning |
|--------|---------|
| `IN SYNC` | The running config and the observed traffic agree |
| `WAITING FOR RELOAD` | The file has changed and nginx has not picked it up yet |
| `AWAITING FIRST REQUEST` | The evidence is empty — nothing has been served yet |

**That gap is the demo.** Edit the file and the top reading flips to `NEW` while
the bottom one still says `OLD` and the marker starts pulsing; reload, and the
room watches the two readings converge. The gap is visible for exactly as long as
the reload takes, and closing it in front of the audience is the most instructive
part of the whole mechanism.

A single merged "ACTIVE: NEW" reading was considered and **rejected** (D-27). It
is smaller and it is worse: it hides the one moment that explains how a cutover
actually works. Do not "simplify" the two readings into one.

The most dramatic way to show this is the live-edit path: open
`proxy/active-backend.conf` on screen, change the word by hand, let the room see
`CONFIG SAYS NEW` sitting above `TRAFFIC SHOWS OLD`, talk over it for a beat, then
`make reload`.

### What it does when it cannot tell

If the proxy is down, or the config is unreadable, or the log is gone, the page
goes to an unmistakable **UNAVAILABLE** state: the whole surface desaturates,
gains a diagonal hazard border no other state has, blanks *both* readings and both
counters to em-dashes, and replaces the request table with a line naming which
source failed and why.

It never shows a stale-but-plausible backend. That is a feature, not a bug: a page
confidently reading `OLD` while nginx is dead is strictly worse than one admitting
it cannot tell — particularly with an audience watching, because the first one
makes a liar of you and the second one does not (D-28).

There is no half-lit state either. If it cannot read *one* of its sources it goes
fully unavailable rather than rendering a live traffic reading beside a blank
config, which would look like a working page and would not be one.

### The four states

| State | What you see |
|-------|--------------|
| **Normal** | Both readings live, the request table filling, the counters moving |
| **No traffic yet** | Readings blanked to em-dashes, `AWAITING FIRST REQUEST` — the state just after a reset |
| **Unavailable** | Desaturated, hazard-bordered, every reading blank, the failing source named |
| **Evidence cleared** | A 10-second confirmation overlay along the bottom, everything beneath it reset to zero |

They are pairwise distinguishable from across a room with no caption, which is the
point: you should never have to explain to the audience what they are looking at.

### Between takes, on screen

`make flip-old` is the between-takes reset (D-36) and the status page is where you
confirm it landed. It puts the rig back on OLD **and** truncates the evidence, so
the counters, the request table, the flip boundary and the since-flip clock all go
to zero at once — the status service holds no state of its own, so they reset
atomically. An `EVIDENCE CLEARED` overlay confirms it for ten seconds. **No
container is restarted**, which is the point CUT-05 exists to make.

The reset direction deliberately issues **no** confirming request of its own. A
request there would move the traffic reading for a few hundred milliseconds before
the truncation caught up, and the page — correctly — would fire the flip animation
for it. Spending the money shot on a reset is a small thing that looks like a bug
from the tenth row, so the reset seeds nothing and therefore requests nothing.

### When something goes wrong

Two failure modes are worth knowing by heart, because they are the two you will
actually hit.

**The flip refuses.**

```
REFUSING TO FLIP: server-new is not answering /healthz.
```

A backend is not up. Nothing has been modified — `proxy/active-backend.conf` is
byte-identical and nginx is untouched, so you can say "the check stopped it" and
mean it. Recover with:

```bash
docker compose up -d --wait server-new     # or server-old
```

Then run the flip again. See the section above for why one dead backend blocks the
flip in *both* directions.

**A request path is longer than the column.** It truncates with an ellipsis and
never wraps, so every row keeps the same height and the flip boundary does not
appear to move. Note that the table shows the path *without* its query string —
that is the field nginx logs as the path, and the query string is recorded
separately. If you want to demonstrate truncation on stage, use a long path
segment (`/whoami/a-very-long-segment-…`), not a long `?query=…`.

**The sync marker pulses and never resolves.** `CONFIG SAYS` has moved and
`TRAFFIC SHOWS` has not followed. The file changed but nginx did not pick it up —
the reload did not take. **The terminal is where the reason is**, not the page: the
flip prints the `nginx -t` result and the reload's exit status, and one of them
will have failed. The page is reporting the situation correctly; it is telling you
the truth about a reload that did not happen.

If the page itself goes unavailable and stays there, check the fourth container:

```bash
docker compose ps status
docker compose logs status
```

### One known asymmetry — carried from Phase 1, and intended

**After the flip, port 9092 lands on NEW while port 9093 still redirects clients
to the original backend on 9090.** The redirect listener does not follow the
cutover.

That is correct and it is worth saying out loud rather than being caught by it
mid-demo: the proxy is the migration mechanism and the redirect is not. A redirect
hands the client a new address and the client remembers it — often
*indefinitely*, since a 301 is cacheable by specification — so it cannot be moved
back and forth the way an upstream can. The contrast is the whole point of having
both ports.

The status page counts only 9092 traffic for the same reason: counting the
redirect listener would misreport the cutover, since it never moved.

---

## SSH on port 22 — the same one word (Phase 3)

The cutover is not an HTTP trick. The proxy carries **raw TCP** on port 22 as
well, selected by the same five-line file, so `ssh` follows the flip exactly the
way `curl` does.

### The command

```bash
make ssh
```

```
OLD server-old
server-old:~$
```

That target is `docker compose exec client ssh …` with the presenter-mode
options pinned — see [the two connection modes](#the-two-connection-modes)
below. Typing the bare `ssh` invocation instead works only once the client has
already recorded this host: on a fresh rig, with an empty trust record and the
default setting, it stops to ask you to confirm a fingerprint and blocks there
until you answer — and with no terminal attached it does not even ask, it exits
non-zero with a bare `Host key verification failed.` That is dead air on stage
at the very first SSH beat, which is why the documented path goes through the
target.

`OLD server-old` is the backend's own pre-auth banner — the machine naming
itself the instant the connection opens, before authentication, exactly as
`/whoami` does over HTTP. Nothing in the proxy writes it.

**Why it runs from the `client` container.** Inside the Docker network the proxy
genuinely listens on **port 22**, so "SSH on port 22, no client-side change" is
literally true rather than a workaround — there is no `-p` flag anywhere. Binding
a privileged host port instead would depend on host state and would simply fail
on any machine already running its own `sshd`. **Nothing in this repository binds
a privileged host port**; `docker compose ps` shows nothing on 22.

### The cutover, over SSH

```bash
make flip-new
make ssh          # the identical command
```

```
NEW server-new
server-new:~$
```

The command is byte-identical either side of the flip. That is the whole claim.

**One caveat, and it is Phase 4's entire subject:** if the client has already
recorded this hostname's key while the selector was on OLD, the connection above
does *not* succeed — it refuses, loudly, with
`WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!`. That is correct behaviour by
every SSH client on earth, and it is the thing that actually breaks on migration
day. See [The host-key gotcha](#the-host-key-gotcha-and-the-fix-that-scales-phase-4).

**Worth narrating:** a session that was already open keeps talking to its
original backend for its entire life, while a session opened after the flip lands
on the new one. That is what *graceful* means — nginx hands the new configuration
to a new worker generation and lets the old one finish its connections — and it
is a genuine operational property of a real cutover, not a demo artefact.

### The two connection modes

There are exactly two named ways to SSH in this repository, and they have
opposite intentions about trust. Confusing them is the single most likely way to
lose a demo.

| Mode | Where it lives | What it does with trust |
|------|----------------|-------------------------|
| **presenter mode** | `make ssh` | **Remembers.** A real trust record, strict checking, `accept-new` on first sight and `UpdateHostKeys` pinned off. This is the only mode in which the host-key gotcha is reachable |
| **test mode** | `scripts/verify.sh` and the smoke suite's SSH section | **Discards.** The trust record is pointed at `/dev/null`, so a changed host key cannot be observed at all |

**The consequence, plainly:** a presenter who runs the test-mode form on stage
gets no gotcha, sees a clean login where the demo needed a refusal, and has no
signal telling them why. Test mode exists so that the routing assertions cannot
trip over a host-key change — it is deliberately blind, and it must stay that
way.

**`accept-new` is not the same thing as switching host-key verification off.**
It records a host it has *never seen before* without stopping to ask — no prompt,
no dead air on the priming beat — and it still refuses a host whose key has
*changed*, with the full warning banner and a non-zero exit. This demo never
teaches a room to disable the check. The blanket-disable form appears in exactly
two files here — `scripts/verify.sh` and `scripts/smoke.sh` — each with an inline
comment saying it is demo-only and naming the reason, and the suite asserts those
comments still exist.

### `make verify` — the assertion (EVID-04/EVID-05)

One command, both protocols, one labelled line each:

```bash
make verify EXPECT=new
```

```
VERIFY: expecting NEW (selector word: new)
HTTP  http://localhost:9092/whoami       ->  NEW server-new
SSH   demo@app.demo.test:22              ->  NEW server-new  [banner; remote hostname: server-new]
OK  both protocols report NEW — the expectation holds on HTTP and on SSH.
```

Both readings are printed on **every** run, in that fixed order, in every
outcome — including when one of the two protocols fails outright, so you are
never left inferring which reading is missing. `make verify` on its own checks
for `old`, which is the state the demo opens and closes in.

It exits non-zero when the answer is wrong, with three distinct codes:

| Exit | Means |
|------|-------|
| `1` | a reading disagrees with what you asked for, or a probe could not be taken |
| `2` | the command was typed wrong — deliberately **not** `1`, so a fumble can never read as a failed cutover |
| `3` | **the two protocols disagree with each other** |

**`3` is the one to point at.** "HTTP is on NEW but SSH is still on OLD" is the
interesting failure, and it gets its own code and its own words because reporting
it as a plain mismatch would throw away the only thing you need to know. The
smoke suite exercises that branch for real rather than merely checking it exists.

### The mechanism, on screen

Open `proxy/nginx.conf` and scroll to the bottom. The `stream` block is eight
lines, and the line to point at is the `include`:

```nginx
include /etc/nginx/demo/active-backend.conf;
```

It is the **same path** the `http` block includes, a hundred and ninety lines
higher up. One file, one word, both protocols — the selector is data, and both
protocol contexts read it.

### The rebuild note

The backend and client images both changed in this phase. A plain
`docker compose up -d` **without a build** will not pick them up, and you would
be verifying against a stale image. `make up` and `make reset` both build; use
one of those.

### The keys

The demo keypair is generated by the `client` container on first run, into a
Docker named volume the backends mount read-only. It is **never written to the
host filesystem and never committed** — `git ls-files` contains no key material,
which the smoke suite asserts. `make reset` tears volumes down, so the keys
regenerate on the next bring-up.

`demo:demo` remains as the documented password fallback if you want to connect
from your own terminal rather than the `client` container.

---

## The host-key gotcha and the fix that scales (Phase 4)

The cutover moves HTTP and SSH together and the client never notices — with one
exception, and it is the most valuable thing in the demo.

### What breaks

An SSH client records the host key it was shown, keyed on **the name you typed**.
Connect once while the selector is on OLD, flip, and connect again, and the
identical command refuses:

```
WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!
```

Thirteen lines, exit status 255, ending on `Host key verification failed.` and
naming the offending line of the client's trust record. Nothing is wrong; the
client is doing exactly its job.

**Why it reaches the client at all is itself the evidence.** The proxy relays the
key exchange untouched — it never sees, terminates, caches or rewrites a host
key. A Layer-7 device would have terminated the connection and presented its own
key, and the client would never have learned that the backend moved. The gotcha
firing is the proof that this is a genuine Layer-4 relay.

### The fix

```bash
make fix-hostkeys
```

It gives `server-new` `server-old`'s host keys — six files, streamed container to
container, never through a host path — **and then signals the running daemon**
with a hangup so it loads them. Both halves are required: sshd reads its host
keys once at startup and holds them in memory, so a copy on its own is a measured
silent no-op that looks exactly like a fix that did not work. Never narrate this
step as "we copied the keys"; say "we gave the new server the old server's
identity, and told sshd to pick it up."

Measured at 0.44 s, and it survives a container restart, so it cannot be undone
under you mid-demo.

Afterwards the client connects with its trust record byte-for-byte unchanged, and
`server-new`'s public key still carries `root@server-old` in its comment field.
That is cosmetic, it has no protocol effect, and it is the most vivid evidence in
the room that the new server is wearing the old server's cryptographic identity.
Do not "fix" it — point at it.

The instinct is to run `ssh-keygen -R` on the client instead. It works, and it is
the wrong answer: it is two steps rather than one, the second of which is
trusting whatever answers next without checking, and it fixes exactly one
machine. `WALKTHROUGH.md` shows both, in that order, for that reason.

### Putting it back

```bash
make reset      # ~16 s, full rebuild — the documented re-arm path
make rearm      # ~1 s, in place — the between-takes fast path
```

Re-arming the keys is not sufficient on its own: the client also has to record
the old box's key again *before* the flip, or the failure has nothing to
contradict. `WALKTHROUGH.md` gives the exact sequence.

### `make verify` cannot see this, deliberately

The verification script pins test mode, so it is structurally incapable of
observing a host-key problem. This has been measured: presenter-mode SSH failing
with status 255 at the same moment `make verify EXPECT=new` reported
`OK  both protocols report NEW` and exited zero.

That is a feature, not a gap. It answers *"did the routing land?"*, not *"does
the client trust what it landed on?"* — two different questions that want two
different tools. Do not reach for it to diagnose the gotcha; it will tell you the
rig is fine, and it will be right.

---

## What "the client never changes" means (HTTP-02 — the verification contract)

This is the claim the whole demo rests on, and it is easy to test against the
wrong thing. Being explicit about what is being verified:

**HTTP-02 is verified as URL invariance.** The client's requested URL — scheme,
host, port and path — is byte-identical before and after traversing the proxy.
The evidence:

- `curl -w '%{url_effective}'` with `-L` returns the URL that was typed
- `curl -w '%{num_redirects}'` returns `0` — nothing moved the client
- the proxy access log records `app.demo.test:9092` as the host and port the
  client asked for, and that field stays constant across the Phase 2 flip

**HTTP-02 is NOT verified via the client's source IP** — and this is not a
shortcut, it is unsatisfiable here. On macOS Docker Desktop every host-originated
request is SNAT'd to the Linux VM gateway `192.168.65.1` before nginx ever sees
it. `$remote_addr` shows `192.168.65.1` for every host request regardless of how
the proxy is configured, so it cannot evidence client-address invariance no
matter what you do. A reader who tests HTTP-02 against source IP will conclude
the demo failed on grounds that have nothing to do with the demo.

Practical note: if you want a meaningful source address in the log, issue the
request from the `client` container, where the real container IP is preserved:

```bash
docker compose exec client curl -sS http://app.demo.test:9092/whoami
# proxy log: 172.19.0.5 -> app.demo.test:9092 "GET /whoami HTTP/1.1" 200 ... backend=OLD
```

---

## Command reference

| Target | What it does |
|--------|--------------|
| `make up` | `docker compose up -d --build --wait`, clear the evidence log, then a status print |
| `make down` | `docker compose down` — stops the rig, keeps the images |
| `make status` | service/status/ports table, plus an `/etc/hosts` check with the exact fix line if missing |
| `make check` | alias for `status` |
| `make logs` | live tail of the proxy **and both backends** — this is where `backend=OLD` flips to `backend=NEW` |
| `make logs-demo` | the same tail, colour-labelled OLD/NEW and timestamped, readable from the back of a room |
| `make flip` | toggle the active backend — gate, rewrite, diff, validate, reload, prove, confirm |
| `make flip-new` | cut over to the New box explicitly |
| `make flip-old` | cut back to the Old box **and clear the evidence** — the between-takes reset |
| `make clear-evidence` | truncate the evidence log without flipping |
| `make verify` | did the cutover land, **on both protocols**? one HTTP request, one SSH connection, one labelled line each, non-zero on any disagreement (`make verify EXPECT=new`) |
| `make test` | the full smoke suite (`sh scripts/smoke.sh`) — five sections, including the cutover, the SSH hop and the UI token audit |
| `make contrast` | the proxied-vs-redirected side-by-side, two labelled lines |
| `make reload` | `nginx -t`, then a graceful `nginx -s reload`, then a verifying request — never a container restart |
| `make reset` | full teardown and rebuild, **and** restore of the flip include to OLD — also the documented re-arm of the host-key gotcha (~16 s) |
| `make ssh` | **presenter mode** — SSH from the `client` container to `app.demo.test` with a real trust record and strict checking. The only mode in which the host-key gotcha is reachable, and therefore the one that deliberately exits non-zero after a flip |
| `make fix-hostkeys` | give `server-new` `server-old`'s host keys **and** signal the running daemon to load them — the fix that touches no client (~0.4 s) |
| `make rearm` | put the gotcha back in place: a fresh identity for `server-new` and a cleared trust record on the client, no rebuild (~1 s) — the between-takes fast path |

**`make reset` is the between-takes command.** It runs `docker compose down -v`
*and* rewrites `proxy/active-backend.conf` back to `old`. Both halves are
necessary: `down -v` removes containers, volumes and networks but does not touch
host files, so a previous take's flip would otherwise leave the demo opening on
NEW. Together they guarantee a byte-identical clean starting state on every run
(D-21).

Every target is a thin wrapper. `sh scripts/smoke.sh [backends|proxy|redirect|cutover|ssh]`
runs a single section if you want a faster loop. `cutover` is the slow one — it
flips repeatedly, stops and restarts containers, and puts the rig back on OLD when
it finishes.

---

## Layout

```
.
├── compose.yaml                  # the whole rig, one command
├── Makefile                      # the presenter's command surface
├── README.md                     # you are here
├── proxy/
│   ├── nginx.conf                # upstreams, log formats, the 9092 proxy, the 9093 redirect, the 8081 oracle, the stream block on :22
│   └── active-backend.conf       # <- THE ONE FILE THE CUTOVER EDITS (5 lines)
├── status/
│   ├── status.py                 # the evidence service — recomputes everything per request, holds no state
│   └── index.html                # the projected page: one file, no build step, no external reference
├── backend/
│   ├── Dockerfile                # one image, instantiated twice
│   ├── entrypoint.sh             # renders templates, generates host keys, execs supervisord
│   ├── supervisord.conf          # nginx + sshd in one container
│   └── templates/
│       ├── default.conf.template # X-Backend header, /healthz, /whoami
│       ├── banner.template       # the sshd pre-auth identity banner — same string as /whoami
│       └── index.html.template   # the big colour-coded OLD/NEW banner
├── client/
│   ├── Dockerfile                # the in-network command source (curl, ssh)
│   └── entrypoint.sh             # idempotent keygen into the demo-keys volume
└── scripts/
    ├── flip.sh                   # the cutover: gate, rewrite, validate, reload, prove, confirm-or-reset
    ├── verify.sh                 # did it land, on BOTH protocols? exits 0/1/2/3
    └── smoke.sh                  # every mechanically checkable requirement
```

`proxy/active-backend.conf` is the file to have open on screen during the
cutover. It is five lines, two of them comments, and the flip changes exactly one
word in it. Everything else — the upstream targets, the validity guard, the log
format — lives in `nginx.conf` so that file stays readable on a projector.

---

## SSH

`sshd` is built into the backend image, both backends listen on port 22 **inside**
their containers, and since Phase 3 the proxy relays raw TCP on port 22 to
whichever one the selector names. **No host port is bound for it** —
`docker compose ps` shows nothing on 22.

The `client` container is the canonical SSH source: it reaches the proxy entirely
over the Docker network, with no host port published and no client-side flag.
That framing is what lets the "no client change" claim stay fully honest — a
presenter typing `ssh -p 2222` would have quietly conceded the point.

The presenter-facing walkthrough is [SSH on port 22 — the same one word](#ssh-on-port-22--the-same-one-word-phase-3).

---

## No cloud, no cost

Everything here runs on your laptop.

- Every image is a Docker Official Image (`nginx:1.30-alpine`, `alpine`) pulled
  anonymously. No `docker login`, no private registry, no registry credentials.
- No cloud SDK, no cloud account, no provisioning step, no bill.
- No `.env` file, no secrets file, no credential of any kind in this repository.
- The only credential that exists at all is a deliberately obvious throwaway SSH
  login inside the backend containers, which is published to no host port and
  reachable only from within the Docker network.

The complete uninstall is `docker compose down -v`, deleting this directory, and
removing the one `/etc/hosts` line you added at the top of this README.

---

## A note on privilege

No Makefile target, shell script, or compose entry in this repository executes
privileged commands or modifies host OS state. The escalation command appears in
exactly two places — this README, and the remediation line `make status` prints
when the `/etc/hosts` entry is missing — and in both it is text for you to read
and decide on, never something the repository runs.

That is deliberate. A demo rig you can throw away without wondering what it
changed is worth more than one that saves you thirty seconds of setup.

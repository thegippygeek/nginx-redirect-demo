#!/usr/bin/env python3
"""status.py — the evidence service (D-25, EVID-02, EVID-03).

Recomputes the ENTIRE world from two files plus one liveness probe on every
request. It holds no counter, no cursor, no cache and no remembered last value.

That is not minimalism for its own sake. In a demo whose whole value is
credibility, stored state is the enemy: every cached counter and remembered
backend is a way for the projected page to be confidently wrong. Because
nothing is remembered:

  * D-36's between-takes reset is a single `: > access.log`, and the counters,
    the table, the boundary and the since-flip clock all reset atomically.
  * Truncation-under-a-reader — the classic tailing bug — cannot happen,
    because there is no offset to invalidate.
  * `docker compose restart status` loses nothing.
  * build() is a pure function of its inputs, so a test harness can drive it
    directly. Importing this module runs no I/O, binds no socket and starts no
    listener; the bind and serve call sit under the main guard at the bottom.

THREE inputs, not two (RESEARCH Pitfall 6). After `docker compose stop proxy`
the evidence file remains perfectly readable, so a service that derives its
state by reading files alone keeps rendering a confident backend reading
indefinitely — the stale-but-plausible banner D-28 forbids. The active
probe against the proxy's unpublished :8081 listener is the only input that
can detect a dead proxy, and it costs no evidence line because that listener
has `access_log off`.

Python 3 standard library only. No package is installed, ever: if
implementation pressure suggests one, the design has drifted.
"""

import json
import os
import re
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# ---------------------------------------------------------------- settings
#
# All optional, all with working defaults, so the demo introduces no .env file
# and no secret. Neither file path is ever derived from a request (T-02-12).

LOG_PATH = os.environ.get("DEMO_LOG_PATH", "/var/log/demo/access.log")
CONF_PATH = os.environ.get("DEMO_CONF_PATH", "/etc/nginx/demo/active-backend.conf")
INDEX_PATH = os.environ.get("DEMO_INDEX_PATH", "/app/index.html")
PROXY_PROBE = os.environ.get("DEMO_PROXY_PROBE", "http://proxy:8081/nginx-health")
PROBE_TIMEOUT = float(os.environ.get("DEMO_PROBE_TIMEOUT", "1.5"))
PORT = int(os.environ.get("DEMO_PORT", "9094"))
# Inside the container the listener must accept from the bridge network, or the
# published port cannot reach it. The loopback restriction is applied where it
# belongs — on the HOST publishing in compose.yaml (`127.0.0.1:9094:9094`,
# T-02-05), asserted by `docker compose port status 9094`.
BIND = os.environ.get("DEMO_BIND", "0.0.0.0")

# The migration port. :9093 redirects deliberately do NOT follow the flip
# (Phase 1 known constraint), so counting them would misreport the cutover.
TRAFFIC_PORT = "9092"

# 8 rows of history; with a boundary present the boundary object steals one, so
# 3 post-flip rows above + 4 pre-flip rows below (02-UI-SPEC "Overflow").
WINDOW = 8
BOUNDARY_PIN = 3
PRE_FLIP_ROWS = WINDOW - 1 - BOUNDARY_PIN
# While the boundary is younger than this the pin holds, protecting the money
# shot from scrolling away during the 60 s the presenter is talking about it.
PIN_SECONDS = 60.0

DEFAULT_RE = re.compile(r"^\s*default\s+([A-Za-z0-9_.-]+)\s*;")
MAP_OPEN_RE = re.compile(r"^\s*map\s+\S+\s+\S+\s*\{")
MAP_ENTRY_RE = re.compile(r"^\s*(\S+)\s+([A-Za-z0-9_.-]+)\s*;")


def _reason(exc):
    """A path-plus-reason error string and nothing else (T-02-09).

    No traceback and no environment: this string is projected in front of a
    room, and the presenter needs to diagnose without reading a stack.
    """
    return (getattr(exc, "strerror", None) or str(exc)).lower()


# ------------------------------------------------------------- the readers


def read_config(path=None):
    """Returns (value, extra_map_entries, error). D-27's INTENT reading.

    Comments are stripped BEFORE matching, and that is load-bearing: the
    canonical file's second line is

        # Change `old` to `new` to cut over. Nothing else.

    and contains BOTH backend words. A whole-file grep, or a `default` match
    that is not anchored to the start of a line, reads the presenter's prose as
    configuration and reports the wrong backend on the projector.

    Only `default` is parsed. Any other map entry is collected and reported
    rather than silently ignored, because Phase 3 (D-13) includes this same
    file from the `stream` block and the map is keyed on $server_port — a
    port-keyed override must surface, not vanish.
    """
    path = CONF_PATH if path is None else path
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            raw = fh.read()
    except OSError as exc:
        return None, [], "{} — {}".format(path, _reason(exc))

    value = None
    extras = []
    in_map = False
    for line in raw.splitlines():
        line = line.split("#", 1)[0]  # comments FIRST
        if not line.strip():
            continue
        if MAP_OPEN_RE.match(line):
            in_map = True
            continue
        if in_map and "}" in line:
            in_map = False
            continue
        matched = DEFAULT_RE.match(line)
        if matched:
            if value is None:
                value = matched.group(1).upper()
            continue
        if in_map:
            entry = MAP_ENTRY_RE.match(line)
            if entry:
                extras.append("{} {}".format(entry.group(1), entry.group(2)))

    if value is None:
        return None, extras, "{} — no `default <backend>;` line found".format(path)
    return value, extras, None


def read_log(path=None):
    """Returns (rows, error). D-27's EVIDENCE reading.

    Reads the WHOLE file every call. No stored offset, no cursor, no cache: an
    offset-tracking reader must detect truncation or it silently reads nothing
    forever after a D-36 reset. At ~165 bytes/line a 90-second take is tens of
    lines, so the re-read is free.

    A line that will not parse is SKIPPED, never raised on. nginx writes each
    line with a single write(), but a reader that opens the file mid-write can
    still see a partial trailing line, and /api/status must still answer 200.
    """
    path = LOG_PATH if path is None else path
    try:
        with open(path, "r", encoding="utf-8", errors="replace") as fh:
            raw = fh.read()
    except OSError as exc:
        return [], "{} — {}".format(path, _reason(exc))

    rows = []
    for line in raw.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            obj = json.loads(line)
        except ValueError:
            continue  # torn trailing line — skip, never raise
        if isinstance(obj, dict):
            rows.append(obj)
    return rows, None


def probe_proxy(url=None, timeout=None):
    """The THIRD input. Returns True only if nginx actually answered.

    Deliberately not optional and deliberately not the traffic port: :8081 is
    unpublished and has `access_log off`, so this probe writes no evidence line
    and cannot inflate the counters the audience is watching (Pitfall 7).

    Every path is resolved at CALL time, not at definition time. Binding these
    as parameter defaults would freeze them at import and make build() undrivable
    against fixtures — the plan requires the opposite.
    """
    url = PROXY_PROBE if url is None else url
    timeout = PROBE_TIMEOUT if timeout is None else timeout
    try:
        with urllib.request.urlopen(url, timeout=timeout) as resp:
            return 200 <= getattr(resp, "status", resp.getcode()) < 400
    except Exception:
        # A dead container fails DNS resolution, a dead process fails connect,
        # a wedged one fails the timeout. All three mean the same thing here.
        return False


# ---------------------------------------------------------- the derivation


def _msec(row):
    try:
        return float(row.get("ms", 0.0))
    except (TypeError, ValueError):
        return 0.0


def _hhmmss(row):
    """HH:MM:SS from the log line's own timestamp — never from the wall clock.

    Taken verbatim out of $time_iso8601 so the value cross-references exactly
    against the raw `make logs` tail running in the adjacent terminal (D-30).
    """
    stamp = str(row.get("t", ""))
    if "T" in stamp:
        return stamp.split("T", 1)[1][:8]
    ms = _msec(row)
    if ms:
        return time.strftime("%H:%M:%S", time.localtime(ms))
    return ""


def _as_int(value):
    try:
        return int(value)
    except (TypeError, ValueError):
        return 0


def _render_row(row):
    return {
        "time": _hhmmss(row),
        "path": str(row.get("path", "")),
        "status": _as_int(row.get("status")),
        "backend": str(row.get("backend", "")).upper(),
        "ms": _msec(row),
        "bhost": str(row.get("bhost", "")),
    }


def _unavailable(detail, failing_source, served_at):
    """All-or-nothing (D-28, UI-SPEC 3a). EVERY reading is blanked.

    A half-lit page is the most dangerous thing this surface can render: it
    looks operational, so nobody questions it, and whichever half is still live
    gets read as authoritative. `counts` keeps both keys because the contract
    guarantees their presence — they are zeroed, never a retained last value,
    and the page renders em dashes off `state`, not off these numbers.
    """
    return {
        "state": "UNAVAILABLE",
        "detail": detail,
        "failing_source": failing_source,
        "config": None,
        "traffic": None,
        "traffic_host": None,
        "traffic_at": None,
        "sync": "CANNOT_DETERMINE",
        "counts": {"OLD": 0, "NEW": 0},
        "rows": [],
        "boundary": None,
        "since_flip_s": None,
        "extra_map_entries": [],
        "served_at": served_at,
        "log_path": LOG_PATH,
    }


def build(now=None):
    """The whole contract, recomputed from scratch. A pure function of the
    two files and the probe — see the module docstring for why."""
    now = time.time() if now is None else now
    served_at = time.strftime("%H:%M:%S", time.localtime(now))

    cfg, extras, cfg_err = read_config()
    rows, log_err = read_log()
    proxy_ok = probe_proxy()

    # The gate, first and unconditional. Three inputs; any one failing takes
    # the whole page down rather than lighting half of it.
    if cfg_err or log_err or not proxy_ok:
        if cfg_err and log_err:
            failing = "log+config"
        elif cfg_err:
            failing = "config"
        elif log_err:
            failing = "log"
        else:
            failing = "proxy"
        detail = cfg_err or log_err or "{} — not answering".format(PROXY_PROBE)
        return _unavailable(detail, failing, served_at)

    # Only requests a backend actually ANSWERED, on the migration port. The
    # $backend_is_valid 503 guard and the :9093 redirect both log an empty
    # backend (nginx renders an unset variable as "" under escape=json), and
    # neither belongs in a reading of the cutover.
    served = [
        r
        for r in rows
        if str(r.get("port", "")) == TRAFFIC_PORT and str(r.get("backend", ""))
    ]

    counts = {"OLD": 0, "NEW": 0}
    for row in served:
        backend = str(row["backend"]).upper()
        if backend in counts:
            counts[backend] += 1

    if not served:
        return {
            "state": "NO_TRAFFIC",
            "detail": None,
            "failing_source": None,
            "config": cfg,
            "traffic": None,
            "traffic_host": None,
            "traffic_at": None,
            "sync": "AWAITING_FIRST_REQUEST",
            "counts": counts,
            "rows": [],
            "boundary": None,
            "since_flip_s": None,
            "extra_map_entries": extras,
            "served_at": served_at,
            "log_path": LOG_PATH,
        }

    # "Traffic shows X" is the LAST request, never a window and never a
    # majority: a window leaves the reading ambiguous when the presenter pauses
    # to talk, and a debounce would delay the money shot by one request.
    last = served[-1]
    traffic = str(last["backend"]).upper()

    # Scanning BACKWARDS yields the MOST RECENT transition and stops there,
    # which is both UI-SPEC's "only the most recent boundary renders" rule and
    # what absorbs the measured 26-90 ms reload interleave in a single step.
    split = None
    for i in range(len(served) - 1, 0, -1):
        if str(served[i]["backend"]).upper() != str(served[i - 1]["backend"]).upper():
            split = i
            break

    boundary = None
    since_flip_s = None
    if split is not None:
        flip_ms = _msec(served[split])
        age = round(max(0.0, now - flip_ms), 1) if flip_ms else 0.0
        boundary = {
            "at": _hhmmss(served[split]),
            "ms": flip_ms,
            "from": str(served[split - 1]["backend"]).upper(),
            "to": str(served[split]["backend"]).upper(),
            "row_index": 0,  # filled in below, from the window actually built
            "age_s": age,
        }
        since_flip_s = age

    # Windowing. row_index is computed HERE, from the rows actually returned,
    # so it is by construction "the count of rows rendered ABOVE the boundary"
    # (02-UI-SPEC.md:456) rather than a second derivation the page could
    # disagree with. Rows above the boundary are post-flip by definition, so
    # this equals min(3, post_flip_row_count): 0 at the instant of a fresh-take
    # flip, then 1 -> 2 -> 3 as post-flip requests arrive, pinned at 3.
    if boundary is not None and boundary["age_s"] < PIN_SECONDS:
        above = served[split:][-BOUNDARY_PIN:]
        below = served[:split][-PRE_FLIP_ROWS:]
        window = below + above
        boundary["row_index"] = len(above)
    else:
        window = served[-WINDOW:]
        if boundary is not None:
            post_flip = len(served) - split
            if post_flip >= WINDOW:
                # The pin has released and the boundary has migrated off the
                # bottom of the table naturally. Nothing to render.
                boundary = None
                since_flip_s = None
            else:
                boundary["row_index"] = post_flip

    return {
        "state": "OK",
        "detail": None,
        "failing_source": None,
        "config": cfg,
        "traffic": traffic,
        # The backend's OWN hostname, straight from the log line. Empty when the
        # backend did not send one — never synthesised from the backend word,
        # which would be this service asserting something it did not observe.
        "traffic_host": str(last.get("bhost", "")),
        "traffic_at": _hhmmss(last),
        # D-27: two readings, never merged. The gap between them is visible for
        # exactly as long as the reload takes, and watching it close is the most
        # instructive part of the mechanism.
        "sync": "IN_SYNC" if cfg == traffic else "PENDING",
        "counts": counts,
        "rows": [_render_row(r) for r in reversed(window)],
        "boundary": boundary,
        # Computed server-side each poll. A client-side interval keeps counting
        # while the service is dead — precisely the stale-but-plausible failure
        # D-28 forbids.
        "since_flip_s": since_flip_s,
        "extra_map_entries": extras,
        "served_at": served_at,
        "log_path": LOG_PATH,
    }


# --------------------------------------------------------------- the server


class StatusHandler(BaseHTTPRequestHandler):
    """GET only, three fixed routes, no CORS headers, no state-changing verbs.

    No request-derived path ever reaches a file operation: the two inputs come
    from module-level environment defaults, so there is no traversal surface to
    defend (T-02-12).
    """

    protocol_version = "HTTP/1.1"
    server_version = "demo-status"
    sys_version = ""

    def log_message(self, fmt, *args):
        # T-02-09: this service emits no second uncontrolled log stream. The
        # evidence log is the only log the demo asks the audience to trust, and
        # a handler chattering attacker-controlled paths to stderr would put a
        # second, unescaped copy of them into `docker compose logs`.
        return

    def _respond(self, code, body, ctype):
        payload = body if isinstance(body, bytes) else body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(payload)))
        # The page polls every 1-2 s and a cached reading is a stale reading.
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        route = self.path.split("?", 1)[0]
        if route == "/api/status":
            self._respond(
                200, json.dumps(build(), indent=2) + "\n", "application/json"
            )
        elif route == "/healthz":
            self._respond(200, "ok\n", "text/plain; charset=utf-8")
        elif route in ("/", "/index.html"):
            # 02-03 ships this file. Until then a 404 for a file that genuinely
            # does not exist is the correct answer, not a stub.
            try:
                with open(INDEX_PATH, "rb") as fh:
                    self._respond(200, fh.read(), "text/html; charset=utf-8")
            except OSError:
                self._respond(404, "not found\n", "text/plain; charset=utf-8")
        else:
            self._respond(404, "not found\n", "text/plain; charset=utf-8")


# The bind and the serve call sit HERE, under the main guard, and nowhere else.
# Importing this module must run no I/O, bind no socket and start no listener,
# so that build() and the three readers can be driven directly by a test
# harness. A module-scope bind would make every import block forever instead of
# returning — the same hangs-instead-of-erroring failure class as the log-mount
# trap, which looks like a stuck executor rather than a red test.
if __name__ == "__main__":
    server = ThreadingHTTPServer((BIND, PORT), StatusHandler)
    server.daemon_threads = True
    print(
        "status service listening on {}:{} — log={} conf={} probe={}".format(
            BIND, PORT, LOG_PATH, CONF_PATH, PROXY_PROBE
        ),
        flush=True,
    )
    server.serve_forever()

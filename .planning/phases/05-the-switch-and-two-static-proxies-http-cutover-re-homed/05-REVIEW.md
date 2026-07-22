---
phase: 05-the-switch-and-two-static-proxies-http-cutover-re-homed
reviewed: 2026-07-22T00:00:00Z
depth: standard
files_reviewed: 11
files_reviewed_list:
  - switch/nginx.conf
  - switch/active-proxy.conf
  - proxy-old/nginx.conf
  - proxy-new/nginx.conf
  - compose.yaml
  - status/status.py
  - status/test_status.py
  - status/index.html
  - scripts/flip.sh
  - scripts/smoke.sh
  - Makefile
findings:
  critical: 0
  warning: 2
  info: 3
  total: 5
  warning_resolved: 2
  info_resolved: 0
status: warnings_fixed
---

# Phase 5: Code Review Report

**Reviewed:** 2026-07-22
**Depth:** standard
**Files Reviewed:** 11
**Status:** issues_found

## Summary

Phase 5 re-homes v1's single flip-in-place `proxy` into a three-tier blue-green shape (front `switch` → two static `proxy-old`/`proxy-new` → backends) and moves the evidence writer forward one tier. The review concentrated on the phase's stated highest-risk axis — **evidence integrity** — and on nginx correctness, exposure, and shell robustness.

**The security-sensitive axis is clean.** Every focus-area control holds:

- **EV2-02 (identity forgery):** no `add_header X-Backend` exists in `switch/nginx.conf`, `proxy-old/nginx.conf`, or `proxy-new/nginx.conf` (the only matches are full-line comments). The backend's own `X-Backend` rides through both hops untouched; `$upstream_http_x_backend` at the switch reads the backend's assertion. No proxy can forge `backend=NEW`.
- **Log injection:** the switch's `evidence` JSON `log_format` keeps `escape=json` (line 48).
- **Open redirect:** 9093 returns the literal `http://app.demo.test:9090$request_uri` — no `$host`/`$http_host` derivation (line 138).
- **Exposure:** every host-published port is `127.0.0.1`-bound (switch 9092/9093, status 9094, backends 9090/9091); both static proxies publish nothing; container `:22` is published nowhere; no Docker socket is mounted anywhere.
- **nginx correctness:** upstreams `old`/`new` are declared before the `include` (no resolver needed); `proxy_pass http://$active_backend` carries no trailing slash; the `$backend_is_valid`→503 guard is intact; the `depends_on` health cascade (switch→proxy-old/new→backends) is correct for parse-time upstream resolution.
- **`make reset`** rewrites `switch/active-proxy.conf` byte-identically (verified against the shipped file; the `$$`→`$` and single-quoted backticks expand correctly).

No BLOCKER-class defects were found. The findings below are a projector-facing stale-text defect and an integration-test coverage gap for the one net-new requirement (EV2-01), plus minor stale comments.

## Warnings

### WR-01: UNAVAILABLE error surface names a service that no longer exists (`proxy`)

**Status:** FIXED (commit e64442b) — `ERR_BODY` copy and the `Check:` line in `status/index.html` re-pointed to the switch (`docker compose ps switch · docker compose logs switch`), config strings now name the switch's `active-proxy` config and access log. `failing_source` key left as `"proxy"` for API-contract stability, as prescribed.

**File:** `status/index.html:557-568`
**Issue:** The re-homed topology deleted the `proxy` service (it is now `switch` + `proxy-old` + `proxy-new`), but the projected UNAVAILABLE panel still instructs the presenter to run a command against it and describes the wrong files:
```js
var ERR_BODY = {
  log: "Cannot read the proxy access log. Not showing a stale reading.",
  config: "Cannot read the active-backend config. Not showing a stale reading.",   // now active-proxy.conf
  ...
  proxy: "Cannot reach the proxy. Not showing a stale reading.",
  ...
};
...
wrap.appendChild(el("div", "det", "Check: docker compose ps proxy"));   // no such service
```
`docker compose ps proxy` resolves to no service under the Phase 5 compose file, so the one actionable remediation shown on stage when the switch dies mid-demo produces an empty result. For a demo whose entire value is on-stage credibility, a wrong projected recovery command is a real defect — and it surfaces at exactly the worst moment (a live failure). The `status.py` `failing_source` value is still the internal token `"proxy"` (status.py:296), which is fine as an opaque contract key, but the human-readable strings keyed off it are stale.
**Fix:** Re-point the operator-facing text to the switch:
```js
proxy: "Cannot reach the switch. Not showing a stale reading.",
// ...
wrap.appendChild(el("div", "det", "Check: docker compose ps switch"));
```
Also update the `config`/`log`/`log+config` copy to reference `active-proxy.conf` and "the switch access log" so the panel matches the shipped topology. (The internal `failing_source` key may stay `"proxy"` to avoid churning the API contract — only the displayed strings need to change.)

### WR-02: EV2-01 (`remote` field) has no integration assertion in the smoke suite

**Status:** FIXED (commit 0bb56ca) — added an EV2-01 assertion in `section_cutover`'s EVID-03 group that reads `rows[0].remote` from the live `/api/status` and asserts it is present and equals NEITHER the proxy-old NOR proxy-new container IP. `make test` re-run green: 155 passed, 0 failed, with the new assertion passing against the running rig.

**File:** `scripts/smoke.sh` (section_cutover EVID group, ~lines 707-816)
**Issue:** `remote` (the client's real `$remote_addr`) is the one net-new evidence field this phase adds, and EV2-01 is the phase's headline new requirement. All three pieces are present — the JSON `log_format` (`switch/nginx.conf:49`), `_render_row` (`status.py:244`), and the `CLIENT` column (`index.html:341,529`) — but no `make test` assertion proves the field survives end-to-end. `grep -nE 'jrow0.*remote|\.remote|"remote"' scripts/smoke.sh` returns nothing; the only coverage is the `_render_row` unit test in `test_status.py`, which cannot catch a regression where the log_format loses the field, a hop overwrites `$remote_addr`, or the render is dropped. The Research Test Map (05-RESEARCH.md:323) explicitly prescribed an assertion here (`jq -e '.rows[0].remote'` and assert it ≠ a static-proxy container IP). That check is the one that would catch the real EV2-01 failure mode — the switch logging a proxy hop's IP instead of the client's — and it is absent.
**Fix:** Add an assertion in `section_cutover` after a real `:9092` request, e.g.:
```sh
_r0remote=$(jrow0 "$_st" remote)
_po_ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$(docker compose ps -q proxy-old)")
assert "EV2-01 rows[0].remote is the real client address, not the static-proxy IP" \
  "test -n '$_r0remote' && test '$_r0remote' != '$_po_ip'"
```

## Info

### IN-01: Stale `proxy` reference in the `reload` target comment

**File:** `Makefile:96`
**Issue:** The comment reads `Never `docker compose restart proxy` — that contradicts D-14`. The service is now `switch` (the recipe itself is correct at lines 99-101; only the comment is stale). Harmless but misleading to a future editor.
**Fix:** Change the comment to `docker compose restart switch`.

### IN-02: Stale `proxy` reference in status.py module docstring

**File:** `status/status.py:21`
**Issue:** The docstring says `After `docker compose stop proxy` the evidence file remains...`. The tier is now `switch`. Code is correct; comment is stale.
**Fix:** Reword to `docker compose stop switch`. (The `probe_proxy`/`proxy_ok`/`failing="proxy"` identifiers are internal names and may stay for contract stability.)

### IN-03: Deferred SSH sections retain v1 (`proxy` / `active-backend.conf`) topology references

**File:** `scripts/smoke.sh:1065,1099-1111,1300-1491,1963-2222`
**Issue:** `section_ssh`, `section_hostkey`, and their helpers (`selector_now`, `restore_ssh_state`, `finish_ssh_state`) still target `docker compose exec -T proxy`, `proxy/active-backend.conf`, and `:8081/active-backend`. This is intentional and correctly documented: both sections are commented out of the `all` runner with explicit `# Phase 6 (SW-03)` markers (lines 2246, 2261), and the section functions are preserved intact rather than deleted. Because they are gated out of `all` and would fail loudly (not pass) if run standalone against the Phase 5 rig (no `proxy` service exists), there is **no false-green risk** — this satisfies the deferral requirement. Flagged only so the Phase 6 hand-off has an explicit inventory of what must be re-pointed to the switch.
**Fix:** None for Phase 5. In Phase 6, re-point these to `switch`/`switch/active-proxy.conf` and un-gate them in the `all` chain.

---

_Reviewed: 2026-07-22_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_

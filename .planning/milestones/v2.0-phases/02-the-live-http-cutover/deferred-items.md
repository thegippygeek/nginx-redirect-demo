# Deferred items — Phase 02

Out-of-scope discoveries logged during execution. Not fixed here.

## D1 — `flip.sh` truncates the evidence *after* its confirming request (found in 02-03)

**File:** `scripts/flip.sh` (owned by 02-01, outside 02-03's `files_modified`)

**What happens:** in the reset direction, step 6 issues a real
`curl http://localhost:9092/whoami` that lands on OLD and writes an evidence line,
and only then does the `TARGET = old` block truncate the log. The traffic reading
therefore genuinely moves NEW → OLD for the few hundred milliseconds between the
two, and a 1 s poll can land inside that window.

**Consequence:** the status page's convergence sequence — which correctly fires on
a traffic change — can fire once during `sh scripts/flip.sh old`. Measured across
three consecutive reset cycles it fired on 1 of 3. 02-03's acceptance criterion
asks for zero, so the criterion is probabilistic rather than structural as written.
02-03 mitigates on the page side with a cancellation path, but the page cannot see
the truncation coming.

**Structural fix (one line, in `flip.sh`):** move the `: > $EVIDENCE` truncation to
*before* the step-6 confirming request in the reset direction, or skip the
confirming request when `TARGET = old`. Either makes the criterion true by
construction. The confirming request's stated purpose is to seed the projected
page's traffic reading for the take that is *starting*, which the reset direction
does not need.

**Why not fixed in 02-03:** `scripts/flip.sh` is not in this plan's `files_modified`
and the change alters 02-01's asserted flip semantics. Route to 02-04 or a
follow-up.

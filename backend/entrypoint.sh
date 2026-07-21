#!/bin/sh
# backend/entrypoint.sh — renders identity, generates host keys, execs the CMD.
#
# This image ships its OWN entrypoint on purpose. The nginx base image's
# /docker-entrypoint.sh guards all template processing behind
# `if [ "$1" = "nginx" ]`, so under a supervisord CMD it silently no-ops and
# the stock welcome page gets served with no error. See RESEARCH Pitfall 1.
set -e

# An unnamed backend must never serve a page (BACK-03 empty edge).
: "${BACKEND_ID:?BACKEND_ID must be set (expected OLD or NEW)}"
: "${BACKEND_COLOR:=#666666}"
export BACKEND_HOSTNAME="$(hostname)"

# EXPLICIT allowlist. Without it envsubst would eat nginx's own $host,
# $remote_addr and $hostname config variables.
VARS='${BACKEND_ID} ${BACKEND_COLOR} ${BACKEND_HOSTNAME}'
envsubst "$VARS" < /templates/default.conf.template > /etc/nginx/conf.d/default.conf
envsubst "$VARS" < /templates/index.html.template  > /usr/share/nginx/html/index.html
# The SSH identity surface (BACK-04/D-42), rendered from the SAME allowlist as
# the two HTTP surfaces above — one variable, three surfaces, no drift (D-16).
# `sed` only drops the template's own leading `#` documentation: sshd sends this
# file to the client verbatim, so it is the one template that cannot carry
# comments through. The rendered result is a single line, byte-identical to this
# backend's /whoami body. Enabled via /etc/ssh/sshd_config.d/10-demo.conf.
envsubst "$VARS" < /templates/banner.template | sed '/^#/d' > /etc/ssh/banner

# Host keys are generated HERE, at container start — never in a build layer.
# Both backends come from one image (D-16); a build-time ssh-keygen would give
# them identical keys and make Phase 4's KEY-01 host-key mismatch unstageable.
# See RESEARCH Pitfall 2.
ssh-keygen -A

echo "entrypoint: rendered config for BACKEND_ID=${BACKEND_ID} host=${BACKEND_HOSTNAME}"
nginx -t

exec "$@"

#!/bin/sh
# client/entrypoint.sh — generates the demo keypair into the demo-keys volume,
# wires the client to use it, then execs the CMD.
#
# The generation is CONDITIONAL, and that is load-bearing rather than stylistic:
# the demo-keys volume survives `docker compose down` and `make up` is run
# repeatedly, so an unconditional keygen would rotate the key out from under a
# rig the presenter already has running. `make reset` runs `down -v`, which
# removes the volume — the keys then regenerate on the next `up`. That is the
# only intended way to get a fresh pair.
#
# No key material is ever committed or written to the host filesystem (T-03-01):
# a PEM block in git reads as a real credential leak to anyone who clones or
# scans this repo, however obviously throwaway it is — unlike `demo:demo`, which
# is visibly a joke.
set -e

KEY=/keys/id_ed25519

if [ ! -f "$KEY" ]; then
    ssh-keygen -t ed25519 -N '' -C 'demo-rig' -f "$KEY" >/dev/null
    cp "$KEY.pub" /keys/authorized_keys
fi

# 600 on the private key is not cosmetic: ssh refuses to use a group-readable
# private key. 644 on the public half and on authorized_keys satisfies sshd's
# StrictModes for a path outside the user's home (T-03-05).
chmod 600 "$KEY"
chmod 644 "$KEY.pub" /keys/authorized_keys

# This is what keeps the presenter's on-stage command clean: no -i flag and no
# -p flag, just `docker compose exec client ssh demo@app.demo.test`.
#
# Deliberately NO host-key-checking option here. The client's default host-key
# behaviour is Phase 4's raw material; only the scripted assertion paths relax
# it, per invocation, each with an inline comment saying it is demo-only.
mkdir -p /root/.ssh
chmod 700 /root/.ssh
printf 'Host *\n    IdentityFile %s\n' "$KEY" > /root/.ssh/config
chmod 600 /root/.ssh/config

exec "$@"

# backend/Dockerfile — D-16: ONE image, instantiated twice. Identity is a
# runtime parameter (BACKEND_ID), never a baked-in constant.
FROM nginx:1.30-alpine

# `demo:demo` is a deliberately obvious throwaway credential. Container port 22
# is never published to the host in Phase 1, so it is reachable only from
# inside the compose network (threat T-01-02).
RUN apk add --no-cache openssh supervisor curl \
 && adduser -D -s /bin/sh demo \
 && echo 'demo:demo' | chpasswd

# Deliberately /templates/, NOT /etc/nginx/templates/ — nothing here uses the
# base image's templating machinery (RESEARCH Pitfall 1).
COPY templates/       /templates/
COPY supervisord.conf /etc/supervisord.conf
COPY entrypoint.sh    /entrypoint.sh

# The stock default.conf is a default_server on :80 and would shadow the
# rendered config.
RUN chmod +x /entrypoint.sh && rm -f /etc/nginx/conf.d/default.conf

# NOTE: no `ssh-keygen -A` here, and there must never be one. Host keys are
# generated per container start in entrypoint.sh — see RESEARCH Pitfall 2.

# A DROP-IN, not an append, and the distinction is load-bearing. Alpine's stock
# /etc/ssh/sshd_config carries an ACTIVE `AuthorizedKeysFile .ssh/authorized_keys`
# at line 45, while its `Include /etc/ssh/sshd_config.d/*.conf` sits at line 15 —
# and sshd uses the FIRST value it obtains for a keyword. Appending an override
# to the end of that file is accepted in SILENCE and never takes effect,
# producing a generic permission-denied that reads like a key problem. The
# Include comes first, so a drop-in wins.
#
# Every sshd setting this phase adds goes through this one file, uniformly.
# `Banner` happens to work as a plain append (there is no active Banner line),
# but mixing two mechanisms invites the bug above the next time someone adds a
# directive.
#
# The check is `sshd -T` — the EFFECTIVE value — never a grep of the config.
#
# No PasswordAuthentication directive here, deliberately: Alpine's default is
# enabled and D-41 keeps `demo:demo` as the documented fallback.
RUN mkdir -p /etc/ssh/sshd_config.d \
 && printf 'AuthorizedKeysFile /keys/authorized_keys\nBanner /etc/ssh/banner\n' \
      > /etc/ssh/sshd_config.d/10-demo.conf

ENV BACKEND_ID=OLD BACKEND_COLOR="#b45309"
EXPOSE 80 22
ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/bin/supervisord","-c","/etc/supervisord.conf"]

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

ENV BACKEND_ID=OLD BACKEND_COLOR="#b45309"
EXPOSE 80 22
ENTRYPOINT ["/entrypoint.sh"]
CMD ["/usr/bin/supervisord","-c","/etc/supervisord.conf"]

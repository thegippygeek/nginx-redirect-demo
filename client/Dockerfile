# client/Dockerfile — D-02: the presenter's command source.
# openssh-client is installed now rather than in Phase 3 on D-18's reasoning:
# build once, avoid a mid-project rebuild. It costs one word.
FROM alpine:3.22
RUN apk add --no-cache curl openssh-client

# No package is added in Phase 3. ssh, ssh-keygen, ssh-keyscan and timeout were
# all verified present in the running image — D-18's foresight held.
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]

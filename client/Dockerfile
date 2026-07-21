# client/Dockerfile — D-02: the presenter's command source.
# openssh-client is installed now rather than in Phase 3 on D-18's reasoning:
# build once, avoid a mid-project rebuild. It costs one word.
FROM alpine:3.22
RUN apk add --no-cache curl openssh-client

# syntax=docker/dockerfile:1

FROM golang:1.25 AS build

WORKDIR /src
COPY go.mod go.sum ./
COPY *.go ./
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/yoloit-hub .

FROM debian:bookworm-slim AS runtime

RUN apt-get update \
  && apt-get install -y --no-install-recommends ca-certificates curl \
  && rm -rf /var/lib/apt/lists/*

COPY --from=build /out/yoloit-hub /usr/local/bin/yoloit-hub
RUN printf '#!/bin/sh\nif [ -n "$YOLOIT_HUB_TOKEN" ]; then\n  curl -fsS -H "Authorization: Bearer $YOLOIT_HUB_TOKEN" "$1" >/dev/null\nelse\n  curl -fsS "$1" >/dev/null\nfi\n' > /usr/local/bin/yoloit-hub_healthcheck \
  && chmod +x /usr/local/bin/yoloit-hub_healthcheck

ENV YOLOIT_HUB_HOST=0.0.0.0
ENV YOLOIT_HUB_PORT=43111
ENV YOLOIT_HUB_DATA_DIR=/data

EXPOSE 43111
VOLUME ["/data"]

CMD ["/usr/local/bin/yoloit-hub"]

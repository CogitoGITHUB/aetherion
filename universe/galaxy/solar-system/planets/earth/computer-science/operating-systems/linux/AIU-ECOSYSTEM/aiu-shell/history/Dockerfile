FROM lukemathwalker/cargo-chef:latest-rust-1.97.0-slim-bookworm AS chef
WORKDIR app

FROM chef AS planner
COPY . .
RUN cargo chef prepare --recipe-path recipe.json

FROM chef AS builder

# Ensure working C compile setup (not installed by default in arm64 images)
RUN apt update && apt install build-essential -y

COPY --from=planner /app/recipe.json recipe.json
RUN cargo chef cook --release --recipe-path recipe.json

COPY . .
RUN cargo build --release --bin aiu-shell-history-server

FROM debian:bookworm-20260623-slim AS runtime
LABEL org.opencontainers.image.source="https://github.com/atuinsh/atuin" \
  org.opencontainers.image.url="https://atuin.sh" \
  org.opencontainers.image.licenses="MIT"

RUN useradd -c 'aiu-shell-history user' aiu-shell-history && mkdir /config && chown aiu-shell-history:aiu-shell-history /config
# Install ca-certificates for webhooks to work
RUN apt update && apt install ca-certificates -y && rm -rf /var/lib/apt/lists/*
WORKDIR app

USER aiu-shell-history

ENV TZ=Etc/UTC
ENV RUST_LOG=aiu_shell_history_server=info
ENV AIU_SHELL_HISTORY_CONFIG_DIR=/config

COPY --from=builder /app/target/release/aiu-shell-history-server /usr/local/bin
ENTRYPOINT ["/usr/local/bin/aiu-shell-history-server"]

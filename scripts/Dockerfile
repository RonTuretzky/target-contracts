# Bridge Script Docker Image
# Contains all dependencies to run bridge-to-l2.sh

FROM ghcr.io/foundry-rs/foundry:latest

# Install additional dependencies as root
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    jq \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy contract sources and scripts
COPY contracts/foundry.toml contracts/foundry.toml
COPY contracts/src contracts/src
COPY contracts/script contracts/script
COPY contracts/lib contracts/lib
COPY scripts scripts

# Contracts will be compiled on first run
WORKDIR /app

# Make scripts executable
RUN chmod +x scripts/*.sh

# Default entrypoint
ENTRYPOINT ["/app/scripts/bridge-to-l2.sh"]

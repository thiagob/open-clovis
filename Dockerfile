FROM node:22-bookworm-slim

# Bun is required for the Telegram plugin MCP server
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl ca-certificates git jq tini unzip \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Install Bun system-wide
RUN curl -fsSL https://bun.sh/install | BUN_INSTALL=/usr/local bash \
    && ln -sf /usr/local/bin/bun /usr/bin/bun

RUN npm install -g @anthropic-ai/claude-code

# Install code-server standalone so it shares the same container as claude
RUN curl -fsSL https://code-server.dev/install.sh \
    | sh -s -- --method standalone --prefix /usr/local

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /home/clovis/workspace

EXPOSE 8080

# tini reaps zombies; Bun spawns subprocesses for the Telegram plugin MCP server
ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["/entrypoint.sh"]
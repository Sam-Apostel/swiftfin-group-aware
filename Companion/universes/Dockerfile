# Couchfin Universes. Built by .github/workflows/companion-universes.yml for amd64 and arm64.
FROM node:22.23.4-alpine@sha256:0e1754758c2df4cfa3e68d59e2e1b7374bb7fd9ea6328eaaacf15cc934af8202

ENV NODE_ENV=production DATA_DIR=/data PORT=7457
WORKDIR /app

COPY package.json package-lock.json ./
RUN npm ci --omit=dev --no-audit --no-fund && npm cache clean --force

COPY src ./src
COPY universes ./universes

# Same uid as umbrelOS app data folders.
USER node
EXPOSE 7457
VOLUME /data
HEALTHCHECK --interval=60s --timeout=5s --start-period=20s CMD wget -qO- http://127.0.0.1:7457/api/v1/ping || exit 1
CMD ["node", "src/main.mjs"]

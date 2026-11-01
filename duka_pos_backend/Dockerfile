# Combined Dockerfile: Keycloak + Backend API in one container
# Stage 1: Build backend
FROM node:26-bookworm-slim AS builder
RUN apt-get update \
  && apt-get install -y --no-install-recommends libssl3 ca-certificates \
  && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --include=dev
COPY . .
RUN npx prisma generate
RUN npm run build

# Stage 2: Download and build Keycloak
FROM node:26-bookworm-slim AS keycloak-builder
RUN apt-get update \
  && apt-get install -y --no-install-recommends wget ca-certificates openjdk-17-jre-headless \
  && rm -rf /var/lib/apt/lists/*
RUN wget -q https://github.com/keycloak/keycloak/releases/download/24.0.1/keycloak-24.0.1.tar.gz \
  && tar -xzf keycloak-24.0.1.tar.gz -C /opt/ \
  && mv /opt/keycloak-24.0.1 /opt/keycloak \
  && rm keycloak-24.0.1.tar.gz
RUN /opt/keycloak/bin/kc.sh build

# Stage 3: Runtime - combined Keycloak + Backend
FROM node:26-bookworm-slim AS runner
# Install OpenJDK for Keycloak
RUN apt-get update \
  && apt-get install -y --no-install-recommends openjdk-17-jre-headless ca-certificates \
  && rm -rf /var/lib/apt/lists/*
# Copy Keycloak from builder
COPY --from=keycloak-builder /opt/keycloak /opt/keycloak
WORKDIR /app
ENV NODE_ENV=production
RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nodejs
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/scripts ./scripts
COPY --from=builder /app/keycloak-init.mjs ./keycloak-init.mjs
COPY --from=builder /app/prisma ./prisma
COPY start-combined.sh ./start-combined.sh
RUN chmod +x ./start-combined.sh
USER root
EXPOSE 3000 8080
HEALTHCHECK --interval=15s --timeout=5s --start-period=60s --retries=10 \
  CMD node -e "fetch('http://localhost:3000/health').then((r) => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"
CMD ["./start-combined.sh"]

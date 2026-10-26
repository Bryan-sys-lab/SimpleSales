# Multi-stage Dockerfile for Duka POS Backend
# Stage 1: Build
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

# Stage 2: Runtime
# Debian (glibc, OpenSSL 3), not Alpine: the Prisma query engine this
# version ships is a glibc build, and the musl one wants libssl1.1, which no
# modern base carries. A `/health` passing while every QUERY 500s is the
# exact failure an alpine runner produced — see the stack start probes.
# OpenSSL, explicitly: the slim image ships neither libssl nor the CA store,
# and Prisma's runtime detects "no OpenSSL, therefore the 1.1 engine" — which
# is how a query engine goes missing on a machine by architecture alone.
FROM node:26-bookworm-slim AS runner
RUN apt-get update && apt-get install -y --no-install-recommends libssl3 ca-certificates && rm -rf /var/lib/apt/lists/*
WORKDIR /app
ENV NODE_ENV=production
RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nodejs
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/scripts ./scripts
COPY --from=builder /app/keycloak-init.mjs ./keycloak-init.mjs
COPY --from=builder /app/prisma ./prisma
USER nodejs
EXPOSE 3000
HEALTHCHECK --interval=15s --timeout=5s --start-period=40s --retries=10 \
  CMD node -e "fetch('http://localhost:3000/health').then((r) => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))"
CMD ["node", "dist/index.js"]

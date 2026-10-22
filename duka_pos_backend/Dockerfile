# Multi-stage Dockerfile for Duka POS Backend
#
# ## WHY NOT ALPINE
#
# It was `node:20-alpine`, and the Prisma CLI would not run in it: the image
# has no OpenSSL for Prisma to detect, so it falls back to an engine built
# against OpenSSL 1.1 — which is not there either — and the migration step
# died with "Can't write to node_modules/@prisma/engines" and a warning about
# libssl. The stack therefore could not start, and the reason was buried in
# a line of a package manager's output.
#
# `node:20-slim` is Debian, with OpenSSL 3, which is what Prisma supports and
# what its engines are built against. The image is larger and the service
# works.
#
# ## WHY THE RUNTIME FILES BELONG TO THE USER
#
# The Prisma CLI writes into node_modules/@prisma/engines when it is asked to
# fetch an engine it does not have. The runtime stage copies node_modules as
# root and runs as `nodejs`, so that write fails. The files are handed to the
# user the service runs as, so a CLI invocation can do its job.
#
# Stage 1: Build
FROM node:20-slim AS builder
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --include=dev
COPY . .
RUN npx prisma generate
RUN npm run build

# Stage 2: Runtime
FROM node:20-slim AS runner
WORKDIR /app
ENV NODE_ENV=production
RUN apt-get update \
    && apt-get install -y --no-install-recommends openssl ca-certificates \
    && rm -rf /var/lib/apt/lists/*
RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nodejs
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/prisma ./prisma
RUN chown -R nodejs:nodejs /app
USER nodejs
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget --quiet --tries=1 --spider http://localhost:3000/health || exit 1
CMD ["node", "dist/index.js"]

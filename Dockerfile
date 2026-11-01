# Root build entry for container platforms (e.g. Back4app).
# The application lives in duka_pos_backend/.
FROM node:20-alpine AS builder
WORKDIR /app
COPY duka_pos_backend/package*.json ./
RUN npm ci
COPY duka_pos_backend/ ./
RUN npx prisma generate
RUN npm run build

FROM node:20-alpine
WORKDIR /app
COPY --from=builder /app/package*.json ./
RUN npm ci --only=production
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/node_modules/.prisma ./node_modules/.prisma

ENV NODE_ENV=production
ENV NODE_OPTIONS="--max-old-space-size=180"

EXPOSE 3000
CMD ["node", "dist/index.js"]

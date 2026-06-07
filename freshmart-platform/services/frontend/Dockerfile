# ─── Stage 1: Install dependencies ────────────────────────────────────────────
FROM node:20-alpine AS deps
RUN apk add --no-cache libc6-compat
WORKDIR /app

COPY package.json package-lock.json* ./
RUN npm ci

# ─── Stage 2: Build ────────────────────────────────────────────────────────────
FROM node:20-alpine AS builder
WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Pass build-time env vars (override at runtime via K8s ConfigMap/Secret)
ARG NEXT_PUBLIC_PRODUCT_SERVICE_URL=""
ARG NEXT_PUBLIC_CART_SERVICE_URL=""
ARG NEXT_PUBLIC_ORDER_SERVICE_URL=""

ENV NEXT_PUBLIC_PRODUCT_SERVICE_URL=$NEXT_PUBLIC_PRODUCT_SERVICE_URL
ENV NEXT_PUBLIC_CART_SERVICE_URL=$NEXT_PUBLIC_CART_SERVICE_URL
ENV NEXT_PUBLIC_ORDER_SERVICE_URL=$NEXT_PUBLIC_ORDER_SERVICE_URL
ENV NEXT_TELEMETRY_DISABLED=1

RUN npm run build

# ─── Stage 3: Production (distroless — no shell, no OS tools) ─────────────────
# CKS Supply Chain: zero attack surface runtime image
FROM gcr.io/distroless/nodejs20-debian12 AS runner

WORKDIR /app

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV PORT=3000
ENV HOSTNAME="0.0.0.0"

# Non-root user (distroless ships with uid 65532 = nonroot)
USER nonroot

# Copy only the standalone output (Next.js standalone mode)
COPY --from=builder --chown=nonroot:nonroot /app/.next/standalone ./
COPY --from=builder --chown=nonroot:nonroot /app/.next/static    ./.next/static
COPY --from=builder --chown=nonroot:nonroot /app/public          ./public

EXPOSE 3000

# No shell means CMD must be exec form with the binary directly
CMD ["server.js"]

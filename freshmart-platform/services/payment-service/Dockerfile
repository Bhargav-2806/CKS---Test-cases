# ─── Stage 1: Build static Go binary ─────────────────────────────────────────
FROM golang:1.23-alpine AS builder

WORKDIR /app

# -mod=mod: allows Go to generate/update go.sum if it doesn't exist yet.
# Once go.sum is committed to the repo, remove this flag for stricter builds.
ENV GOFLAGS="-mod=mod"

# Copy module definition first for layer caching
COPY go.mod ./
# go.sum is optional here — generated automatically by -mod=mod if absent
COPY go.sum* ./

RUN go mod download

# Copy source and build a static, stripped binary
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build \
    -a \
    -installsuffix cgo \
    -ldflags="-w -s -extldflags '-static'" \
    -o payment-service \
    ./main.go


# ─── Stage 2: Distroless runtime (CKS showpiece) ─────────────────────────────
# Zero OS: no shell, no package manager, no libc — only the binary.
# Attack surface: the application binary itself. Nothing else.
FROM gcr.io/distroless/static-debian12 AS runner

# CKS: non-root (distroless ships uid 65532 = nonroot)
USER nonroot:nonroot

COPY --from=builder --chown=nonroot:nonroot /app/payment-service /payment-service

EXPOSE 8004

ENTRYPOINT ["/payment-service"]

# ─────────────────────────────────────────────────────────────────────────────
# FreshMart — Local Development Makefile
# Usage: make <target>
# ─────────────────────────────────────────────────────────────────────────────

.PHONY: help up down build logs ps clean db test-apis \
        dev-product dev-cart dev-order dev-payment dev-frontend

COMPOSE = docker-compose

# ─── Docker Compose (full stack) ─────────────────────────────────────────────

help:
	@echo ""
	@echo "  FreshMart Local Dev Commands"
	@echo "  ────────────────────────────────────────"
	@echo "  make up            Start entire stack (build if needed)"
	@echo "  make down          Stop all containers"
	@echo "  make build         Rebuild all images"
	@echo "  make logs          Tail logs from all services"
	@echo "  make ps            Show running containers"
	@echo "  make clean         Stop + delete volumes (fresh start)"
	@echo ""
	@echo "  make db            Start PostgreSQL only"
	@echo "  make test-apis     Curl all health endpoints"
	@echo ""
	@echo "  make dev-product   Run product-service locally (needs venv)"
	@echo "  make dev-cart      Run cart-service locally"
	@echo "  make dev-order     Run order-service locally"
	@echo "  make dev-payment   Run payment-service locally (needs Go)"
	@echo "  make dev-frontend  Run Next.js dev server"
	@echo ""

up:
	$(COMPOSE) up -d --build

down:
	$(COMPOSE) down

build:
	$(COMPOSE) build

logs:
	$(COMPOSE) logs -f

ps:
	$(COMPOSE) ps

clean:
	$(COMPOSE) down -v --remove-orphans
	docker image prune -f

# Start just the database (useful when running services locally)
db:
	$(COMPOSE) up -d postgres
	@echo "PostgreSQL ready at localhost:5432 (user: freshmart / pass: freshmart / db: freshmart)"

# ─── Health checks (run after 'make up') ────────────────────────────────────

test-apis:
	@echo "\n── Health checks ──────────────────────────────────"
	@curl -sf http://localhost:8001/health | python3 -m json.tool && echo "✓ product-service" || echo "✗ product-service (not ready)"
	@curl -sf http://localhost:8002/health | python3 -m json.tool && echo "✓ cart-service"    || echo "✗ cart-service (not ready)"
	@curl -sf http://localhost:8003/health | python3 -m json.tool && echo "✓ order-service"   || echo "✗ order-service (not ready)"
	@curl -sf http://localhost:8004/health | python3 -m json.tool && echo "✓ payment-service" || echo "✗ payment-service (not ready)"
	@echo "\n── Product list ───────────────────────────────────"
	@curl -sf http://localhost:8001/api/products | python3 -m json.tool | head -40

# ─── Run services locally without Docker (needs 'make db' first) ────────────

dev-product:
	cd services/product-service && \
	python3 -m venv .venv && \
	.venv/bin/pip install -q -r requirements.txt && \
	DATABASE_URL=postgresql://freshmart:freshmart@localhost:5432/freshmart \
	.venv/bin/uvicorn app.main:app --reload --port 8001

dev-cart:
	cd services/cart-service && \
	python3 -m venv .venv && \
	.venv/bin/pip install -q -r requirements.txt && \
	DATABASE_URL=postgresql://freshmart:freshmart@localhost:5432/freshmart \
	PRODUCT_SERVICE_URL=http://localhost:8001 \
	.venv/bin/uvicorn app.main:app --reload --port 8002

dev-order:
	cd services/order-service && \
	python3 -m venv .venv && \
	.venv/bin/pip install -q -r requirements.txt && \
	DATABASE_URL=postgresql://freshmart:freshmart@localhost:5432/freshmart \
	CART_SERVICE_URL=http://localhost:8002 \
	PAYMENT_SERVICE_URL=http://localhost:8004 \
	KAFKA_ENABLED=false \
	.venv/bin/uvicorn app.main:app --reload --port 8003

dev-payment:
	cd services/payment-service && \
	DATABASE_URL=postgresql://freshmart:freshmart@localhost:5432/freshmart \
	KAFKA_ENABLED=false \
	PORT=8004 \
	go run main.go

dev-frontend:
	cd services/frontend && \
	NEXT_PUBLIC_PRODUCT_SERVICE_URL=http://localhost:8001 \
	NEXT_PUBLIC_CART_SERVICE_URL=http://localhost:8002 \
	NEXT_PUBLIC_ORDER_SERVICE_URL=http://localhost:8003 \
	npm run dev

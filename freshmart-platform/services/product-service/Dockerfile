# ─── Stage 1: Install dependencies into a venv ────────────────────────────────
FROM python:3.12-slim AS builder

WORKDIR /app

RUN python -m venv /venv
ENV PATH="/venv/bin:$PATH"

COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r requirements.txt


# ─── Stage 2: Minimal runtime image (CKS supply chain) ────────────────────────
FROM python:3.12-slim AS runner

# CKS: non-root user, explicit UID/GID
RUN groupadd --gid 10001 appgroup && \
    useradd --uid 10001 --gid 10001 --no-create-home --shell /sbin/nologin appuser

WORKDIR /app

ENV PATH="/venv/bin:$PATH"
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1

# Copy only the venv and app code — no dev tools
COPY --from=builder /venv /venv
COPY app/ ./app/

# CKS: run as non-root
USER 10001:10001

EXPOSE 8001

# Explicit exec form — no shell wrapper
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8001", "--workers", "2"]

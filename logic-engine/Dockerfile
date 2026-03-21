# ── Stage 1: Dependencias ────────────────────────────────────────────────────
FROM python:3.12-slim AS deps
WORKDIR /app

# Instalamos dependencias del sistema necesarias para compilar algunas libs
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip \
    && pip install --no-cache-dir -r requirements.txt

# ── Stage 2: Runtime ──────────────────────────────────────────────────────────
FROM python:3.12-slim
WORKDIR /app

# Usuario no-root por seguridad
RUN addgroup --system appgroup && adduser --system --ingroup appgroup appuser

# Copiamos solo las dependencias compiladas del stage anterior
COPY --from=deps /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=deps /usr/local/bin /usr/local/bin

COPY --chown=appuser:appgroup . .

USER appuser

EXPOSE 8000

# Healthcheck interno del contenedor
HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", \
     "--workers", "2", "--log-level", "info"]

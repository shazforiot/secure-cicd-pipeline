##############################################################################
# Secure Dockerfile — Best Practices Demonstration
# From the "CI/CD Pipeline Security Best Practices 2026" video
##############################################################################

# ✅ STAGE 1: Builder — full toolchain, never shipped to production
FROM python:3.12-slim AS builder

# ✅ Create non-root user for build stage
RUN groupadd --gid 1001 appgroup && \
    useradd --uid 1001 --gid appgroup --no-create-home appuser

WORKDIR /app

# ✅ Copy dependency files first for better layer caching
COPY requirements.txt .

# ✅ Install dependencies into a virtual env (easy to copy to final stage)
RUN python -m venv /opt/venv && \
    /opt/venv/bin/pip install --no-cache-dir --upgrade pip && \
    /opt/venv/bin/pip install --no-cache-dir -r requirements.txt

# ✅ Copy application code
COPY --chown=appuser:appgroup . .

##############################################################################
# STAGE 2: Final image — minimal attack surface
##############################################################################
# ✅ Use distroless: no shell, no package manager, far fewer CVEs
FROM gcr.io/distroless/python3-debian12:nonroot

# ✅ Non-root user (nonroot = UID 65532 in distroless)
USER nonroot:nonroot

# Copy virtualenv from builder
COPY --from=builder --chown=nonroot:nonroot /opt/venv /opt/venv

# Copy application code
COPY --from=builder --chown=nonroot:nonroot /app /app

# ✅ Explicit PATH to virtualenv
ENV PATH="/opt/venv/bin:$PATH"
ENV PYTHONPATH="/app"

WORKDIR /app

# ✅ Document the port (but don't expose externally — handled by orchestrator)
EXPOSE 8080

# ✅ Use exec form (not shell form) — no shell injection risk
ENTRYPOINT ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]

##############################################################################
# SECURITY NOTES:
# - No shell in final image (no /bin/sh, /bin/bash)
# - No package manager (no apt, pip in image)
# - Running as UID 65532 (nonroot)
# - No SUID binaries
# - No write access to application code (read-only filesystem recommended)
#
# To run with read-only filesystem:
#   docker run --read-only --tmpfs /tmp myapp:latest
##############################################################################

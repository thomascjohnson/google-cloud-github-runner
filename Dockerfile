# Use the official Python image as a base image
# Using a specific version makes the build deterministic
ARG PYTHON_VERSION=3.14-alpine

# --- Build Stage ---
# This stage builds the Python dependencies
FROM docker.io/library/python:${PYTHON_VERSION} AS builder

# Pinned tag, not an ARG: some builders cannot expand args in `COPY --from`
COPY --from=ghcr.io/astral-sh/uv:0.12.17 /uv /usr/local/bin/uv

# PYTHONUNBUFFERED: Log messages immediately without buffering
# UV_LINK_MODE=copy: Hardlinking fails across Docker filesystem layers
# UV_PYTHON_DOWNLOADS=never: Fail instead of fetching an unpinned interpreter
ENV PYTHONUNBUFFERED=True
ENV UV_LINK_MODE=copy
ENV UV_COMPILE_BYTECODE=1
ENV UV_PYTHON_DOWNLOADS=never

# Both stages use /app so the venv's interpreter shebangs stay valid
WORKDIR /app

# Cached until pyproject.toml or uv.lock changes
COPY pyproject.toml uv.lock .python-version ./
RUN uv sync --frozen --no-dev --no-install-project

# --- Production Stage ---
# This stage creates the final production image
FROM docker.io/library/python:${PYTHON_VERSION}

ENV PYTHONUNBUFFERED=True

# Set the port the application will run on
ENV PORT=8080
ENV PATH="/app/.venv/bin:${PATH}"
# Configure Gunicorn server arguments for production
# --bind: Bind to all network interfaces on the specified port
# --workers: Number of worker processes
# --threads: Number of threads per worker
# --timeout: Timeout for worker processes
# Source: https://cloud.google.com/run/docs/tips/python#optimize_gunicorn
ENV GUNICORN_CMD_ARGS="--bind 0.0.0.0:$PORT --workers 1 --threads 8 --timeout 0"

# Do not re-add FLASK_ENV: Flask 3.x ignores it, and DEBUG is set in create_app()

# Expose the port the application runs on
EXPOSE $PORT

# Set the working directory in the container
WORKDIR /app

# Create a non-root user and group for security
RUN addgroup -S appuser && adduser -S -G appuser appuser

COPY --chown=appuser:appuser . .

# Copied last so it always wins, and left root-owned: appuser may read the
# dependencies but cannot modify them
COPY --from=builder /app/.venv /app/.venv

# The app writes .env and github-private-key.pem to its working directory,
# so /app itself must stay writable by appuser
RUN chown appuser:appuser /app

# Switch to the non-root user for security
USER appuser

# Set the command to run the application using Gunicorn
# This command starts the Gunicorn server and runs the Flask app
CMD ["gunicorn", "run:app"]

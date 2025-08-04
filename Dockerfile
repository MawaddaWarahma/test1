# Microsoft Extraction Platform - Multi-Service Dockerfile
# This Dockerfile can be used to build individual services or the entire platform

# =============================================================================
# BASE IMAGE - Common dependencies for all services
# =============================================================================
FROM python:3.11-slim as base

# Set environment variables
ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV DEBIAN_FRONTEND=noninteractive

# Install system dependencies
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        postgresql-client \
        build-essential \
        libpq-dev \
        curl \
        gcc \
        g++ \
        git \
        wget \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Create app user for security
RUN groupadd -r appuser && useradd -r -g appuser appuser

# =============================================================================
# CORE SERVICE (Django) - Main orchestration service
# =============================================================================
FROM base as core-service

ENV DJANGO_SETTINGS_MODULE=core.settings
ENV SERVICE_NAME=core

WORKDIR /app

# Copy and install Core service requirements
COPY Core/requirements.txt /app/
RUN pip install --no-cache-dir -r requirements.txt

# Copy Core service code
COPY Core/ /app/

# Create necessary directories
RUN mkdir -p /app/static /app/media /app/logs \
    && chown -R appuser:appuser /app

# Collect static files
RUN python manage.py collectstatic --noinput || true

# Switch to non-root user
USER appuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8000/health/ || exit 1

CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "4", "--timeout", "120", "core.wsgi:application"]

# =============================================================================
# FLASK SERVICES - User, Calendar, OneDrive, Outlook, Teams
# =============================================================================
FROM base as flask-service

ENV FLASK_ENV=production
ENV FLASK_APP=app.py

WORKDIR /app

# This stage will be customized per service
# Copy requirements and install dependencies
COPY requirements.txt /app/
RUN pip install --no-cache-dir -r requirements.txt

# Copy service code
COPY . /app/

# Create necessary directories
RUN mkdir -p /app/logs /app/data \
    && chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

# Default Flask service configuration
EXPOSE 4000

HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:${PORT:-4000}/health || exit 1

CMD ["gunicorn", "--bind", "0.0.0.0:${PORT:-4000}", "--workers", "2", "--timeout", "300", "app:app"]

# =============================================================================
# USER SERVICE - Microsoft user data extraction
# =============================================================================
FROM flask-service as user-service

ENV SERVICE_NAME=user
ENV PORT=4001

WORKDIR /app

# Copy User service specific files
COPY User/requirements.txt /app/
RUN pip install --no-cache-dir -r requirements.txt

COPY User/ /app/

RUN mkdir -p /app/logs \
    && chown -R appuser:appuser /app

USER appuser

EXPOSE 4001

HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD curl -f http://localhost:4001/health || exit 1

CMD ["gunicorn", "--bind", "0.0.0.0:4001", "--workers", "2", "--timeout", "300", "app:app"]

# =============================================================================
# CALENDAR SERVICE - Microsoft calendar extraction
# =============================================================================
FROM flask-service as calendar-service

ENV SERVICE_NAME=calendar
ENV PORT=4002

WORKDIR /app

# Copy Calendar service specific files
COPY CalendarActivity/requirements.txt /app/
RUN pip install --no-cache-dir -r requirements.txt

COPY CalendarActivity/ /app/

RUN mkdir -p /app/logs \
    && chown -R appuser:appuser /app

USER appuser

EXPOSE 4002

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:4002/health || exit 1

CMD ["gunicorn", "--bind", "0.0.0.0:4002", "--workers", "2", "--timeout", "300", "app:app"]

# =============================================================================
# ONEDRIVE SERVICE - Microsoft OneDrive extraction
# =============================================================================
FROM flask-service as onedrive-service

ENV SERVICE_NAME=onedrive
ENV PORT=4003

WORKDIR /app

# Copy OneDrive service specific files
COPY OneDriveActivity/requirements.txt /app/
RUN pip install --no-cache-dir -r requirements.txt

COPY OneDriveActivity/ /app/

RUN mkdir -p /app/logs \
    && chown -R appuser:appuser /app

USER appuser

EXPOSE 4003

HEALTHCHECK --interval=60s --timeout=30s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:4003/health || exit 1

CMD ["gunicorn", "--bind", "0.0.0.0:4003", "--workers", "2", "--timeout", "300", "app:app"]

# =============================================================================
# OUTLOOK SERVICE - Microsoft Outlook email extraction
# =============================================================================
FROM flask-service as outlook-service

ENV SERVICE_NAME=outlook
ENV PORT=4004

WORKDIR /app

# Copy Outlook service specific files
COPY Outlook/requirements.txt /app/
RUN pip install --no-cache-dir -r requirements.txt

COPY Outlook/ /app/

RUN mkdir -p /app/logs /app/data \
    && chown -R appuser:appuser /app

USER appuser

EXPOSE 4004

HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD curl -f http://localhost:4004/health || exit 1

CMD ["gunicorn", "--bind", "0.0.0.0:4004", "--workers", "2", "--timeout", "300", "app:app"]

# =============================================================================
# TEAMS SERVICE - Microsoft Teams chat extraction
# =============================================================================
FROM flask-service as teams-service

ENV SERVICE_NAME=teams
ENV PORT=4005

WORKDIR /app

# Copy Teams service specific files
COPY TeamChats/requirements.txt /app/
RUN pip install --no-cache-dir -r requirements.txt

COPY TeamChats/ /app/

RUN mkdir -p /app/logs \
    && chown -R appuser:appuser /app

USER appuser

EXPOSE 4005

HEALTHCHECK --interval=60s --timeout=30s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:4005/health || exit 1

CMD ["gunicorn", "--bind", "0.0.0.0:4005", "--workers", "2", "--timeout", "300", "app:app"]

# =============================================================================
# DEVELOPMENT BUILD - All services in one container (for development only)
# =============================================================================
FROM base as development

WORKDIR /app

# Install all requirements
COPY Core/requirements.txt /app/core-requirements.txt
COPY User/requirements.txt /app/user-requirements.txt
COPY CalendarActivity/requirements.txt /app/calendar-requirements.txt
COPY OneDriveActivity/requirements.txt /app/onedrive-requirements.txt
COPY Outlook/requirements.txt /app/outlook-requirements.txt
COPY TeamChats/requirements.txt /app/teams-requirements.txt

# Install all Python dependencies
RUN pip install --no-cache-dir \
    -r core-requirements.txt \
    -r user-requirements.txt \
    -r calendar-requirements.txt \
    -r onedrive-requirements.txt \
    -r outlook-requirements.txt \
    -r teams-requirements.txt

# Copy all service code
COPY . /app/

# Create necessary directories
RUN mkdir -p /app/logs /app/data /app/static /app/media \
    && chown -R appuser:appuser /app

# Install supervisor for process management
RUN apt-get update && apt-get install -y supervisor \
    && rm -rf /var/lib/apt/lists/*

# Copy supervisor configuration
COPY <<EOF /etc/supervisor/conf.d/microsoft-platform.conf
[supervisord]
nodaemon=true
user=root

[program:core-service]
command=python Core/manage.py runserver 0.0.0.0:8000
directory=/app
user=appuser
autostart=true
autorestart=true
stdout_logfile=/app/logs/core.log
stderr_logfile=/app/logs/core.error.log

[program:user-service]
command=python User/app.py
directory=/app
user=appuser
autostart=true
autorestart=true
environment=PORT=4001
stdout_logfile=/app/logs/user.log
stderr_logfile=/app/logs/user.error.log

[program:calendar-service]
command=python CalendarActivity/app.py
directory=/app
user=appuser
autostart=true
autorestart=true
environment=PORT=4002
stdout_logfile=/app/logs/calendar.log
stderr_logfile=/app/logs/calendar.error.log

[program:onedrive-service]
command=python OneDriveActivity/app.py
directory=/app
user=appuser
autostart=true
autorestart=true
environment=PORT=4003
stdout_logfile=/app/logs/onedrive.log
stderr_logfile=/app/logs/onedrive.error.log

[program:outlook-service]
command=python Outlook/app.py
directory=/app
user=appuser
autostart=true
autorestart=true
environment=PORT=4004
stdout_logfile=/app/logs/outlook.log
stderr_logfile=/app/logs/outlook.error.log

[program:teams-service]
command=python TeamChats/app.py
directory=/app
user=appuser
autostart=true
autorestart=true
environment=PORT=4005
stdout_logfile=/app/logs/teams.log
stderr_logfile=/app/logs/teams.error.log
EOF

EXPOSE 8000 4001 4002 4003 4004 4005

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/microsoft-platform.conf"]


# BUILD_FROM is injected by HA Supervisor via build.yaml; the default below is
# used only for local `docker build` testing outside of Supervisor.
ARG BUILD_FROM=ghcr.io/home-assistant/amd64-base-python:3.12-alpine3.20
FROM ${BUILD_FROM}

# Install runtime tools (jq for run.sh; bash for bashio)
RUN apk add --no-cache jq bash

WORKDIR /app

# Install Python package requirements
COPY requirements.txt .
RUN pip3 install --no-cache-dir --break-system-packages -r requirements.txt

# Copy bridge source
COPY miraie_bridge.py .

# Copy and permission the entrypoint
COPY run.sh /run.sh
RUN chmod a+x /run.sh



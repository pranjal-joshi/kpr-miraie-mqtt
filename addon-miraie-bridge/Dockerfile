# Use the same base as the standalone bridge — plain Python slim on Debian.
# This avoids s6-overlay / bashio entirely. The Supervisor still manages
# the container lifecycle (start/stop/restart/watchdog); we just run our
# process as PID 1 directly via ENTRYPOINT.
ARG BUILD_FROM=python:3.12-slim
FROM ${BUILD_FROM}

# Install jq (parse /data/options.json) and curl (query Supervisor MQTT API)
RUN apt-get update && apt-get install -y --no-install-recommends jq curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Install Python package requirements
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy bridge source
COPY miraie_bridge.py .

# Copy and permission the entrypoint
COPY run.sh /run.sh
RUN chmod +x /run.sh

ENTRYPOINT ["/run.sh"]

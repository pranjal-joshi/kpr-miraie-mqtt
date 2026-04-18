# HA add-on base image is Alpine-based and provided by Supervisor at build time
ARG BUILD_FROM
FROM ${BUILD_FROM}

# Install Python 3 and runtime dependencies
RUN apk add --no-cache \
    python3 \
    py3-pip \
    py3-yaml \
    jq \
    bash

WORKDIR /app

# Install Python package requirements
COPY requirements.txt .
RUN pip3 install --no-cache-dir --break-system-packages -r requirements.txt

# Copy bridge source
COPY miraie_bridge.py .

# Copy and permission the entrypoint
COPY run.sh /run.sh
RUN chmod a+x /run.sh

CMD ["/run.sh"]

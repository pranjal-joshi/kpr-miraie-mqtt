#!/usr/bin/env bash
# MirAIe MQTT Bridge — HA Add-on entrypoint
# Reads /data/options.json, writes credentials.json + devices.yaml, then
# launches miraie_bridge.py as PID 1. Runs on plain python:3.12-slim —
# no s6-overlay or bashio required.

set -e

CONFIG_PATH=/data/options.json
CREDS_FILE=/data/credentials.json
DEVICES_FILE=/data/devices.yaml

log() { echo "[addon] $*"; }
die() { echo "[addon] FATAL: $*" >&2; exit 1; }

# ── Read add-on options ─────────────────────────────────────────────

LOGIN_TYPE=$(jq -r '.login_type // "email"'         "$CONFIG_PATH")
USERNAME=$(jq -r '.username   // ""'                "$CONFIG_PATH")
PASSWORD=$(jq -r '.password   // ""'                "$CONFIG_PATH")
CLOUD_BROKER=$(jq -r '.cloud_broker // "mqtt.miraie.in"' "$CONFIG_PATH")
CLOUD_PORT=$(jq -r '.cloud_port    // 8883'         "$CONFIG_PATH")
HA_DISC_PREFIX=$(jq -r '.ha_discovery_prefix // "homeassistant"' "$CONFIG_PATH")

OPT_MQTT_HOST=$(jq -r '.mqtt_host     // ""' "$CONFIG_PATH")
OPT_MQTT_PORT=$(jq -r '.mqtt_port     // ""' "$CONFIG_PATH")
OPT_MQTT_USER=$(jq -r '.mqtt_username // ""' "$CONFIG_PATH")
OPT_MQTT_PASS=$(jq -r '.mqtt_password // ""' "$CONFIG_PATH")

# ── Resolve MQTT broker ─────────────────────────────────────────────
# Priority 1: explicit user options
# Priority 2: HA Supervisor MQTT service API (Mosquitto add-on)
# Priority 3: fatal — nothing configured

if [ -n "$OPT_MQTT_HOST" ]; then
    log "Using user-configured MQTT broker: ${OPT_MQTT_HOST}:${OPT_MQTT_PORT:-1883}"
    MQTT_HOST_FINAL="$OPT_MQTT_HOST"
    MQTT_PORT_FINAL="${OPT_MQTT_PORT:-1883}"
    MQTT_USER_FINAL="$OPT_MQTT_USER"
    MQTT_PASS_FINAL="$OPT_MQTT_PASS"
elif [ -n "${SUPERVISOR_TOKEN:-}" ]; then
    log "Querying HA Supervisor for MQTT service credentials..."
    MQTT_SVC=$(curl -s -f \
        -H "Authorization: Bearer ${SUPERVISOR_TOKEN}" \
        http://supervisor/services/mqtt 2>/dev/null || true)

    if [ -n "$MQTT_SVC" ] && echo "$MQTT_SVC" | jq -e '.data.host' >/dev/null 2>&1; then
        MQTT_HOST_FINAL=$(echo "$MQTT_SVC" | jq -r '.data.host')
        MQTT_PORT_FINAL=$(echo "$MQTT_SVC" | jq -r '.data.port // 1883')
        MQTT_USER_FINAL=$(echo "$MQTT_SVC" | jq -r '.data.username // ""')
        MQTT_PASS_FINAL=$(echo "$MQTT_SVC" | jq -r '.data.password // ""')
        log "Using HA Mosquitto add-on: ${MQTT_HOST_FINAL}:${MQTT_PORT_FINAL}"
    else
        die "Mosquitto add-on not found via Supervisor API. Install it or set mqtt_host manually."
    fi
else
    die "No MQTT broker configured and SUPERVISOR_TOKEN not available. Set mqtt_host in add-on options."
fi

# ── Write credentials.json ──────────────────────────────────────────

log "Writing credentials to ${CREDS_FILE}"
if [ "$LOGIN_TYPE" = "mobile" ]; then
    jq -n --arg m "$USERNAME" --arg p "$PASSWORD" \
        '{"mobile": $m, "password": $p}' > "$CREDS_FILE"
else
    jq -n --arg e "$USERNAME" --arg p "$PASSWORD" \
        '{"email": $e, "password": $p}' > "$CREDS_FILE"
fi

# ── Write / update devices.yaml ─────────────────────────────────────
# First run  : create from scratch.
# Later runs : update MQTT/cloud/prefix only — preserve discovered devices.

DEVICE_COUNT=$(jq '.devices | length' "$CONFIG_PATH")

if [ ! -f "$DEVICES_FILE" ]; then
    log "First run — creating ${DEVICES_FILE}"
    DEVICES_JSON=$(jq '.devices // []' "$CONFIG_PATH")

    python3 - <<PYEOF
import yaml, json

mqtt = {
    'host': '${MQTT_HOST_FINAL}',
    'port': int('${MQTT_PORT_FINAL}'),
    'username': '${MQTT_USER_FINAL}',
    'password': '${MQTT_PASS_FINAL}',
}
cloud   = {'broker': '${CLOUD_BROKER}', 'port': int('${CLOUD_PORT}')}
devices = json.loads(r"""${DEVICES_JSON}""")

cfg = {
    'mqtt': mqtt,
    'ha_discovery_prefix': '${HA_DISC_PREFIX}',
    'cloud': cloud,
    'devices': devices,
}
with open('${DEVICES_FILE}', 'w') as f:
    yaml.dump(cfg, f, default_flow_style=False, sort_keys=False)
print('[addon] ${DEVICES_FILE} created')
PYEOF

else
    log "Updating MQTT/cloud settings in ${DEVICES_FILE} (preserving discovered devices)"

    if [ "$DEVICE_COUNT" -gt "0" ]; then
        DEVICES_JSON=$(jq '.devices' "$CONFIG_PATH")
        USE_ADDON_DEVICES="True"
    else
        DEVICES_JSON="[]"
        USE_ADDON_DEVICES="False"
    fi

    python3 - <<PYEOF
import yaml, json

with open('${DEVICES_FILE}') as f:
    cfg = yaml.safe_load(f) or {}

cfg['mqtt'] = {
    'host': '${MQTT_HOST_FINAL}',
    'port': int('${MQTT_PORT_FINAL}'),
    'username': '${MQTT_USER_FINAL}',
    'password': '${MQTT_PASS_FINAL}',
}
cfg['cloud']               = {'broker': '${CLOUD_BROKER}', 'port': int('${CLOUD_PORT}')}
cfg['ha_discovery_prefix'] = '${HA_DISC_PREFIX}'

if ${USE_ADDON_DEVICES}:
    devices = json.loads(r"""${DEVICES_JSON}""")
    cfg['devices'] = devices
    print(f'[addon] Using {len(devices)} device(s) from add-on options')
else:
    existing = cfg.get('devices') or []
    print(f'[addon] Preserving {len(existing)} previously discovered device(s)')

with open('${DEVICES_FILE}', 'w') as f:
    yaml.dump(cfg, f, default_flow_style=False, sort_keys=False)
PYEOF

fi

# ── Start bridge ────────────────────────────────────────────────────

log "Launching MirAIe MQTT Bridge..."
log "  credentials : ${CREDS_FILE}"
log "  devices     : ${DEVICES_FILE}"
log "  cloud       : ${CLOUD_BROKER}:${CLOUD_PORT}"
log "  local mqtt  : ${MQTT_HOST_FINAL}:${MQTT_PORT_FINAL}"

exec python3 -u /app/miraie_bridge.py \
    --config    "$DEVICES_FILE" \
    --credentials "$CREDS_FILE"

#!/usr/bin/env bashio
# MirAIe MQTT Bridge — HA Add-on entrypoint
# Reads /data/options.json, writes credentials.json + devices.yaml, then
# launches miraie_bridge.py. On subsequent runs the MQTT/cloud settings are
# refreshed while discovered devices in /data/devices.yaml are preserved.

set -e

CONFIG_PATH=/data/options.json
CREDS_FILE=/data/credentials.json
DEVICES_FILE=/data/devices.yaml

# ── Read add-on options ─────────────────────────────────────────────

LOGIN_TYPE=$(bashio::config 'login_type')
USERNAME=$(bashio::config 'username')
PASSWORD=$(bashio::config 'password')
CLOUD_BROKER=$(bashio::config 'cloud_broker')
CLOUD_PORT=$(bashio::config 'cloud_port')
HA_DISC_PREFIX=$(bashio::config 'ha_discovery_prefix')

OPT_MQTT_HOST=$(bashio::config 'mqtt_host')
OPT_MQTT_PORT=$(bashio::config 'mqtt_port')
OPT_MQTT_USER=$(bashio::config 'mqtt_username')
OPT_MQTT_PASS=$(bashio::config 'mqtt_password')

# ── Resolve MQTT broker ─────────────────────────────────────────────
# Priority: explicit user options > HA Supervisor-injected Mosquitto credentials

if bashio::config.has_value 'mqtt_host'; then
    bashio::log.info "Using user-configured MQTT broker: ${OPT_MQTT_HOST}:${OPT_MQTT_PORT}"
    MQTT_HOST_FINAL="${OPT_MQTT_HOST}"
    MQTT_PORT_FINAL="${OPT_MQTT_PORT:-1883}"
    MQTT_USER_FINAL="${OPT_MQTT_USER}"
    MQTT_PASS_FINAL="${OPT_MQTT_PASS}"
elif bashio::services.available "mqtt"; then
    bashio::log.info "Using HA Supervisor MQTT service (Mosquitto add-on)"
    MQTT_HOST_FINAL=$(bashio::services mqtt "host")
    MQTT_PORT_FINAL=$(bashio::services mqtt "port")
    MQTT_USER_FINAL=$(bashio::services mqtt "username")
    MQTT_PASS_FINAL=$(bashio::services mqtt "password")
else
    bashio::log.fatal "No MQTT broker available. Install the Mosquitto add-on or set mqtt_host in add-on options."
    exit 1
fi

bashio::log.info "MQTT broker: ${MQTT_HOST_FINAL}:${MQTT_PORT_FINAL} (user: ${MQTT_USER_FINAL})"

# ── Write credentials.json ──────────────────────────────────────────

bashio::log.info "Writing credentials to ${CREDS_FILE}"
if [ "${LOGIN_TYPE}" = "mobile" ]; then
    jq -n \
        --arg m "${USERNAME}" \
        --arg p "${PASSWORD}" \
        '{"mobile": $m, "password": $p}' > "${CREDS_FILE}"
else
    jq -n \
        --arg e "${USERNAME}" \
        --arg p "${PASSWORD}" \
        '{"email": $e, "password": $p}' > "${CREDS_FILE}"
fi

# ── Write / update devices.yaml ─────────────────────────────────────
# First run: create from scratch.
# Subsequent runs: update MQTT/cloud/prefix settings only, PRESERVE the
# [devices] list that was auto-discovered and written back by the bridge.

# Check if user has manually specified devices in add-on options
DEVICE_COUNT=$(jq '.devices | length' "${CONFIG_PATH}")

if [ ! -f "${DEVICES_FILE}" ]; then
    bashio::log.info "First run — creating ${DEVICES_FILE}"

    # Build optional devices block from add-on options (may be empty list)
    DEVICES_JSON=$(jq '.devices' "${CONFIG_PATH}")

    python3 - <<PYEOF
import yaml, json

mqtt = {
    'host': '${MQTT_HOST_FINAL}',
    'port': int('${MQTT_PORT_FINAL}'),
    'username': '${MQTT_USER_FINAL}',
    'password': '${MQTT_PASS_FINAL}',
}
cloud = {'broker': '${CLOUD_BROKER}', 'port': int('${CLOUD_PORT}')}
devices_json = json.loads('''${DEVICES_JSON}''')

cfg = {
    'mqtt': mqtt,
    'ha_discovery_prefix': '${HA_DISC_PREFIX}',
    'cloud': cloud,
    'devices': devices_json,
}
with open('${DEVICES_FILE}', 'w') as f:
    yaml.dump(cfg, f, default_flow_style=False, sort_keys=False)
print('[addon] ${DEVICES_FILE} created')
PYEOF

else
    bashio::log.info "Updating MQTT/cloud settings in ${DEVICES_FILE} (preserving discovered devices)"

    # If user has explicitly listed devices in add-on options, use those.
    # Otherwise keep whatever the bridge auto-discovered previously.
    if [ "${DEVICE_COUNT}" -gt "0" ]; then
        DEVICES_JSON=$(jq '.devices' "${CONFIG_PATH}")
        USE_ADDON_DEVICES="True"
    else
        DEVICES_JSON="null"
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
cfg['cloud'] = {'broker': '${CLOUD_BROKER}', 'port': int('${CLOUD_PORT}')}
cfg['ha_discovery_prefix'] = '${HA_DISC_PREFIX}'

use_addon_devices = ${USE_ADDON_DEVICES}
if use_addon_devices:
    devices_json = json.loads('''${DEVICES_JSON}''')
    cfg['devices'] = devices_json
    print(f'[addon] Using {len(devices_json)} device(s) from add-on options')
else:
    existing = cfg.get('devices') or []
    print(f'[addon] Preserving {len(existing)} previously discovered device(s)')

with open('${DEVICES_FILE}', 'w') as f:
    yaml.dump(cfg, f, default_flow_style=False, sort_keys=False)
PYEOF

fi

# ── Start bridge ────────────────────────────────────────────────────

bashio::log.info "Launching MirAIe MQTT Bridge..."
bashio::log.info "  credentials : ${CREDS_FILE}"
bashio::log.info "  devices     : ${DEVICES_FILE}"
bashio::log.info "  cloud       : ${CLOUD_BROKER}:${CLOUD_PORT}"
bashio::log.info "  local mqtt  : ${MQTT_HOST_FINAL}:${MQTT_PORT_FINAL}"

exec python3 -u /app/miraie_bridge.py \
    --config "${DEVICES_FILE}" \
    --credentials "${CREDS_FILE}"

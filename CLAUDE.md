# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Home Assistant custom integration + standalone MQTT bridge for Panasonic MirAIe smart ACs. Two components work together:
- **HA component** (`custom_components/kpr_miraie_mqtt/`) — config flow, device discovery, MQTT Discovery publishing
- **Bridge** (`bridge/`) — Docker container relaying cloud MQTT ↔ local MQTT broker

The HA component does NOT connect to cloud MQTT itself. It only publishes MQTT Discovery configs so HA auto-creates entities. The bridge handles all cloud relay.

## Architecture

```
MirAIe Cloud MQTT ←→ bridge (paho-mqtt) ←→ Local MQTT Broker ←→ HA (MQTT Discovery entities)
```

- Bridge subscribes to `{userId}/{homeId}/#` on cloud, republishes to `miraie/{deviceId}/{type}` locally (retained)
- Bridge subscribes to `miraie/{deviceId}/control` locally, forwards to cloud
- HA component publishes discovery configs to `homeassistant/{component}/{slug}/config`
- Cloud echoes control messages back — bridge filters `/control` from cloud→local to prevent loops

## Key Domain Knowledge

- MirAIe API login requires `scope: "an_14214235325"` (not empty string)
- Login supports both email and mobile (`+91...`) — field name changes (`email` vs `mobile`)
- Cloud MQTT: `mqtt.miraie.in:8883`, username=`homeId`, password=`accessToken`
- Token expires in ~84 days (`expiresIn: 7257599s`)
- Device cert-pins TLS on all endpoints — DNS override / MITM is not possible
- `achs` (horizontal swing) is positional 0-5, not just on/off
- Converti mode (`cnv`) uses int values 0/50/100, not the "Auto" mapping used by swing

## Commands

```bash
# Lint
ruff check custom_components/kpr_miraie_mqtt/ bridge/miraie_bridge.py

# Syntax check all Python
python3 -m py_compile custom_components/kpr_miraie_mqtt/coordinator.py

# Test bridge locally
cd bridge
cp credentials-email.json.example credentials.json  # fill in
cp devices.yaml.example devices.yaml                # fill in
pip install -r requirements.txt
python3 miraie_bridge.py

# Deploy bridge as Docker
cd bridge
docker compose up -d
docker logs miraie-bridge

# Deploy HA component
scp -r custom_components/kpr_miraie_mqtt root@<HA_IP>:/config/custom_components/
```

## Consistency Rules

- Domain is `kpr_miraie_mqtt` — must match in `const.py DOMAIN`, `manifest.json domain`, and folder name
- All entity unique_ids use prefix `kpr_miraie_{device_id}_`
- Device identifiers use `kpr_miraie_{device_id}`
- MQTT topics use prefix `miraie/` (not `kpr_miraie/`) — this is the local broker topic namespace
- Display name is "KPR MirAIe Local MQTT" — consistent across manifest, hacs.json, strings.json, translations
- Bridge must NOT auto-publish MQTT Discovery (HA component handles it) — use `--discover-only` flag for manual

## MirAIe Control Payload Format

All commands to `miraie/{deviceId}/control`:
```json
{"<field>": "<value>", "ki": 0, "cnt": "an", "sid": "0"}
```

Status fields: `ps`, `actmp`, `rmtmp`, `acmd`, `acfs`, `acvs`, `achs`, `acec`, `acpm`, `acng`, `acdc`, `bzr`, `cnv`, `rssi`

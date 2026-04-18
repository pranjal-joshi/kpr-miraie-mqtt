# MirAIe MQTT Bridge — Add-on Documentation

## Overview

This add-on runs the MirAIe MQTT bridge inside Home Assistant OS, eliminating
the need for a separate Docker container or LXC. It logs into the Panasonic
MirAIe cloud, discovers your AC units, and relays their status and control
messages to your local MQTT broker so Home Assistant can manage them entirely
locally at runtime.

```
MirAIe Cloud MQTT <-> [this add-on] <-> Local MQTT Broker <-> HA entities
```

---

## Prerequisites

- Home Assistant OS or Supervised installation
- **Mosquitto broker** add-on installed (recommended) **or** an external MQTT broker
- The **KPR MirAIe Local MQTT** custom component installed via HACS
- A Panasonic MirAIe account (email or mobile)

---

## Installation

1. Add this repository to HA:
   **Settings → Add-ons → Add-on Store → ⋮ → Repositories**
   Paste: `https://github.com/hareeshmu/kpr-miraie-mqtt`

2. Find **MirAIe MQTT Bridge** in the store and click **Install**.

3. Configure the add-on (see below).

4. Click **Start**. Watch the **Log** tab — on the first run the bridge will
   discover your devices, print them, and save them automatically.

5. Restart the add-on once. From now on it will relay messages continuously.

---

## Configuration

### Minimal setup (Mosquitto add-on)

Leave all `mqtt_*` fields empty. The Supervisor injects Mosquitto credentials
automatically when the Mosquitto add-on is present.

```yaml
login_type: email
username: your@email.com
password: your_miraie_password
cloud_broker: mqtt.miraie.in
cloud_port: 8883
ha_discovery_prefix: homeassistant
mqtt_host: ""
mqtt_port: 1883
mqtt_username: ""
mqtt_password: ""
devices: []
```

### Mobile login

```yaml
login_type: mobile
username: "+91XXXXXXXXXX"
password: your_miraie_password
```

### External MQTT broker

```yaml
mqtt_host: 192.168.1.50
mqtt_port: 1883
mqtt_username: mqttuser
mqtt_password: mqttpass
```

### Manual device overrides

Leave `devices` empty on first run. The bridge auto-discovers devices and saves
them. To override names or slugs, restart the add-on and fill in:

```yaml
devices:
  - device_id: "XXXXXXXXXXXX"
    name: Living Room AC
    slug: kpr_XXXXXXXXXXXX
    space: Living Room
    manufacturer: KPR
    model: Panasonic MirAIe Smart AC
```

---

## How auto-discovery works

On the first run (or whenever `devices` is empty and no `/data/devices.yaml`
exists), the bridge calls the MirAIe API after login to enumerate all ACs
registered to your account and writes their IDs and names into
`/data/devices.yaml` inside the add-on's persistent storage. This file
survives restarts and add-on updates.

On subsequent runs the add-on updates only the MQTT/cloud settings in that
file and preserves the discovered `devices` list.

---

## MQTT Topics

| Topic | Direction | Description |
|---|---|---|
| `miraie/{deviceId}/status` | Cloud → local | Full AC state JSON (retained) |
| `miraie/{deviceId}/connection` | Cloud → local | Online status JSON (retained) |
| `miraie/{deviceId}/control` | local → Cloud | Command JSON from HA |

---

## Entities created (via MQTT Discovery)

Each AC creates:

| Entity | Type | Description |
|---|---|---|
| `climate.kpr_{id}` | Climate | Main thermostat card |
| `sensor.kpr_{id}_room_temp` | Sensor | Room temperature |
| `sensor.kpr_{id}_rssi` | Sensor | WiFi signal strength (dBm) |
| `binary_sensor.kpr_{id}_online` | Binary sensor | Cloud connectivity |
| `switch.kpr_{id}_eco` | Switch | Clean mode (`acec`) |
| `switch.kpr_{id}_eco_mode` | Switch | Eco mode (`acem`) |
| `switch.kpr_{id}_powerful` | Switch | Powerful mode |
| `switch.kpr_{id}_nanoe` | Switch | Nanoe purification |
| `switch.kpr_{id}_display` | Switch | Panel display |
| `switch.kpr_{id}_buzzer` | Switch | Beep on command |
| `select.kpr_{id}_v_swing` | Select | Vertical louver position |
| `select.kpr_{id}_h_swing` | Select | Horizontal louver position |
| `select.kpr_{id}_converti` | Select | Converti capacity (0–110%) |

---

## Troubleshooting

**Add-on fails to start — MQTT error**
Ensure the Mosquitto add-on is running, or fill in the `mqtt_host` option.

**No devices discovered**
Check the Log tab. Verify your MirAIe credentials and that your ACs appear
in the MirAIe mobile app.

**Entities appear but show "Unavailable"**
The AC may be offline or the cloud status message hasn't arrived yet.
Wait a few seconds or toggle the AC in the MirAIe app.

**Token expiry**
MirAIe tokens expire after ~84 days. The bridge automatically refreshes
the token 1 hour before expiry and reconnects. No manual intervention needed.

---

## Support

- Issues: https://github.com/pranjal-joshi/kpr-miraie-mqtt/issues
- Custom card: https://github.com/hareeshmu/kpr-miraie-card

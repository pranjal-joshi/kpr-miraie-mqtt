"""MirAIe MQTT coordinator — publishes HA MQTT Discovery configs.

Cloud MQTT bridging is handled by the standalone miraie-bridge container.
This component discovers devices, publishes MQTT Discovery, and manages auth tokens.
"""
from __future__ import annotations

import json
import logging

from homeassistant.components.mqtt import async_publish
from homeassistant.config_entries import ConfigEntry
from homeassistant.const import CONF_PASSWORD, CONF_USERNAME
from homeassistant.core import HomeAssistant
from homeassistant.helpers.event import async_track_time_interval

from .api import MirAIeApi
from .const import (
    CONF_ACCESS_TOKEN,
    CONF_EXPIRES_AT,
    CONF_HOME_ID,
    CONF_USER_ID,
    TOPIC_PREFIX,
)

from datetime import timedelta

_LOGGER = logging.getLogger(__name__)

HA_DISCOVERY_PREFIX = "homeassistant"


class MirAIeCoordinator:
    """Discovers devices and publishes HA MQTT Discovery configs."""

    def __init__(self, hass: HomeAssistant, entry: ConfigEntry) -> None:
        self.hass = hass
        self.entry = entry
        self.api = MirAIeApi()
        self.api.user_id = entry.data[CONF_USER_ID]
        self.api.access_token = entry.data[CONF_ACCESS_TOKEN]
        self.api.home_id = entry.data[CONF_HOME_ID]
        self.api.expires_at = entry.data[CONF_EXPIRES_AT]
        self.api._username = entry.data[CONF_USERNAME]
        self.api._password = entry.data[CONF_PASSWORD]

        self.devices: dict[str, dict] = {}
        self._unsub_timer = None

    async def async_setup(self) -> None:
        """Discover devices and publish HA MQTT Discovery configs."""
        if self.api.needs_refresh():
            await self.api.async_refresh_token(self.hass)
            self._update_entry_token()

        # Discover devices
        homes = await self.api.async_get_homes(self.hass)
        raw_devices = self.api.get_devices_from_homes(homes)

        for dev in raw_devices:
            device_id = dev["deviceId"]
            name = dev.get("deviceName", device_id)
            space = dev.get("_space_name", "")
            slug = f"kpr_{device_id}"
            self.devices[device_id] = {"name": name, "space": space, "slug": slug}
            _LOGGER.info("Discovered device: %s (%s) in %s", name, device_id, space)

        # Get firmware version from device status
        for device_id, dev in self.devices.items():
            try:
                status = await self.api.async_get_device_status(self.hass, device_id)
                dev["fw_version"] = status.get("V", "")
                dev["model_code"] = status.get("mo", "")
            except Exception:
                pass

        # Publish HA MQTT Discovery configs
        await self._publish_discovery()

        # Token refresh timer (bridge container also refreshes, but keep in sync)
        self._unsub_timer = async_track_time_interval(
            self.hass, self._async_check_token, timedelta(hours=1)
        )

    async def async_unload(self) -> None:
        """Cleanup: unpublish discovery."""
        if self._unsub_timer:
            self._unsub_timer()
        await self._unpublish_discovery()

    # ── HA MQTT Discovery ──────────────────────────────────────────

    async def _publish_discovery(self) -> None:
        """Publish MQTT Discovery configs for all devices."""
        for device_id, dev in self.devices.items():
            entities = self._build_discovery(device_id, dev)
            for component, object_id, config in entities:
                topic = f"{HA_DISCOVERY_PREFIX}/{component}/{object_id}/config"
                await async_publish(self.hass, topic, json.dumps(config), retain=True, qos=1)
            _LOGGER.info("Published %d entities for %s", len(entities), dev["name"])

    async def _unpublish_discovery(self) -> None:
        """Remove all discovery configs."""
        for device_id, dev in self.devices.items():
            entities = self._build_discovery(device_id, dev)
            for component, object_id, _ in entities:
                topic = f"{HA_DISCOVERY_PREFIX}/{component}/{object_id}/config"
                await async_publish(self.hass, topic, "", retain=True)

    def _build_discovery(self, device_id: str, dev: dict) -> list[tuple]:
        """Build HA MQTT Discovery configs for one device."""
        slug = dev["slug"]
        status_topic = f"{TOPIC_PREFIX}/{device_id}/status"
        control_topic = f"{TOPIC_PREFIX}/{device_id}/control"
        connection_topic = f"{TOPIC_PREFIX}/{device_id}/connectionStatus"

        device_block = {
            "identifiers": [f"kpr_miraie_{device_id}"],
            "name": dev["name"],
            "manufacturer": "KPR",
            "model": "Panasonic MirAIe Smart AC",
            "sw_version": dev.get("fw_version", ""),
            "hw_version": dev.get("model_code", ""),
            "configuration_url": "https://github.com/hareeshmu/kpr-miraie-mqtt",
        }

        entities = []

        # Climate
        entities.append(("climate", slug, {
            "name": None,
            "unique_id": f"kpr_miraie_{device_id}_climate",
            "object_id": slug,
            "device": device_block,
            "current_temperature_topic": status_topic,
            "current_temperature_template": "{{ value_json.rmtmp | float }}",
            "temperature_state_topic": status_topic,
            "temperature_state_template": "{{ value_json.actmp | float }}",
            "mode_state_topic": status_topic,
            "mode_state_template": (
                "{% if value_json.ps == 'off' %}off"
                "{% elif value_json.acmd == 'fan' %}fan_only"
                "{% else %}{{ value_json.acmd }}{% endif %}"
            ),
            "fan_mode_state_topic": status_topic,
            "fan_mode_state_template": "{{ value_json.acfs }}",
            "swing_mode_state_topic": status_topic,
            "swing_mode_state_template": (
                "{% if value_json.acvs == 0 %}auto{% else %}{{ value_json.acvs }}{% endif %}"
            ),
            "temperature_command_topic": control_topic,
            "temperature_command_template": '{"actmp":"{{ value }}","ki":0,"cnt":"an","sid":"0"}',
            "mode_command_topic": control_topic,
            "mode_command_template": (
                '{% if value == "off" %}'
                '{"ps":"off","ki":0,"cnt":"an","sid":"0"}'
                '{% elif value == "fan_only" %}'
                '{"ps":"on","acmd":"fan","ki":0,"cnt":"an","sid":"0"}'
                '{% else %}'
                '{"ps":"on","acmd":"{{ value }}","ki":0,"cnt":"an","sid":"0"}'
                '{% endif %}'
            ),
            "fan_mode_command_topic": control_topic,
            "fan_mode_command_template": '{"acfs":"{{ value }}","ki":0,"cnt":"an","sid":"0"}',
            "swing_mode_command_topic": control_topic,
            "swing_mode_command_template": (
                '{% if value == "auto" %}'
                '{"acvs":0,"ki":0,"cnt":"an","sid":"0"}'
                '{% else %}'
                '{"acvs":{{ value }},"ki":0,"cnt":"an","sid":"0"}'
                '{% endif %}'
            ),
            "modes": ["off", "cool", "heat", "auto", "dry", "fan_only"],
            "fan_modes": ["auto", "quiet", "low", "medium", "high"],
            "swing_modes": ["auto", "1", "2", "3", "4", "5"],
            "min_temp": 16,
            "max_temp": 30,
            "temp_step": 0.5,
            "temperature_unit": "C",
            "availability_topic": connection_topic,
            "availability_template": (
                "{% if value_json.onlineStatus == 'true' %}online{% else %}offline{% endif %}"
            ),
        }))

        # Room temperature sensor
        entities.append(("sensor", f"{slug}_room_temp", {
            "name": "Room Temperature",
            "unique_id": f"kpr_miraie_{device_id}_room_temp",
            "object_id": f"{slug}_room_temp",
            "device": device_block,
            "state_topic": status_topic,
            "value_template": "{{ value_json.rmtmp }}",
            "unit_of_measurement": "\u00b0C",
            "device_class": "temperature",
            "state_class": "measurement",
        }))

        # RSSI sensor
        entities.append(("sensor", f"{slug}_rssi", {
            "name": "WiFi Signal",
            "unique_id": f"kpr_miraie_{device_id}_rssi",
            "object_id": f"{slug}_rssi",
            "device": device_block,
            "state_topic": status_topic,
            "value_template": "{{ value_json.rssi }}",
            "unit_of_measurement": "dBm",
            "device_class": "signal_strength",
            "state_class": "measurement",
            "entity_category": "diagnostic",
        }))

        # Online binary sensor
        entities.append(("binary_sensor", f"{slug}_online", {
            "name": "Online",
            "unique_id": f"kpr_miraie_{device_id}_online",
            "object_id": f"{slug}_online",
            "device": device_block,
            "state_topic": connection_topic,
            "value_template": "{{ value_json.onlineStatus }}",
            "payload_on": "true",
            "payload_off": "false",
            "device_class": "connectivity",
            "entity_category": "diagnostic",
        }))

        # Switches: eco, powerful, nanoe, display, buzzer
        for key, name, icon in [
            ("acec", "Eco Mode", "mdi:leaf"),
            ("acpm", "Powerful Mode", "mdi:flash"),
            ("acng", "Nanoe", "mdi:air-purifier"),
            ("acdc", "Display", "mdi:monitor"),
            ("bzr", "Buzzer", "mdi:volume-high"),
        ]:
            entities.append(("switch", f"{slug}_{key}", {
                "name": name,
                "unique_id": f"kpr_miraie_{device_id}_{key}",
                "object_id": f"{slug}_{key}",
                "device": device_block,
                "state_topic": status_topic,
                "value_template": f"{{{{ value_json.{key} }}}}",
                "state_on": "on",
                "state_off": "off",
                "command_topic": control_topic,
                "payload_on": json.dumps({key: "on", "ki": 0, "cnt": "an", "sid": "0"}),
                "payload_off": json.dumps({key: "off", "ki": 0, "cnt": "an", "sid": "0"}),
                "icon": icon,
            }))

        # Vertical swing select
        entities.append(("select", f"{slug}_v_swing", {
            "name": "Vertical Swing",
            "unique_id": f"kpr_miraie_{device_id}_v_swing",
            "object_id": f"{slug}_v_swing",
            "device": device_block,
            "state_topic": status_topic,
            "value_template": "{% if value_json.acvs == 0 %}Auto{% else %}{{ value_json.acvs }}{% endif %}",
            "command_topic": control_topic,
            "command_template": (
                '{% if value == "Auto" %}'
                '{"acvs":0,"ki":0,"cnt":"an","sid":"0"}'
                '{% else %}'
                '{"acvs":{{ value }},"ki":0,"cnt":"an","sid":"0"}'
                '{% endif %}'
            ),
            "options": ["Auto", "1", "2", "3", "4", "5"],
            "icon": "mdi:arrow-up-down",
        }))

        # Horizontal swing select
        entities.append(("select", f"{slug}_h_swing", {
            "name": "Horizontal Swing",
            "unique_id": f"kpr_miraie_{device_id}_h_swing",
            "object_id": f"{slug}_h_swing",
            "device": device_block,
            "state_topic": status_topic,
            "value_template": "{% if value_json.achs == 0 %}Auto{% else %}{{ value_json.achs }}{% endif %}",
            "command_topic": control_topic,
            "command_template": (
                '{% if value == "Auto" %}'
                '{"achs":0,"ki":0,"cnt":"an","sid":"0"}'
                '{% else %}'
                '{"achs":{{ value }},"ki":0,"cnt":"an","sid":"0"}'
                '{% endif %}'
            ),
            "options": ["Auto", "1", "2", "3", "4", "5"],
            "icon": "mdi:arrow-left-right",
        }))

        # Converti mode select
        entities.append(("select", f"{slug}_converti", {
            "name": "Converti Mode",
            "unique_id": f"kpr_miraie_{device_id}_converti",
            "object_id": f"{slug}_converti",
            "device": device_block,
            "state_topic": status_topic,
            "value_template": "{{ value_json.cnv }}",
            "command_topic": control_topic,
            "command_template": '{"cnv":{{ value }},"ki":0,"cnt":"an","sid":"0"}',
            "options": ["0", "50", "100"],
            "icon": "mdi:percent",
        }))

        return entities

    # ── Token refresh ──────────────────────────────────────────────

    async def _async_check_token(self, now=None) -> None:
        """Periodically check and refresh token."""
        if self.api.needs_refresh():
            _LOGGER.info("Refreshing MirAIe token")
            await self.api.async_refresh_token(self.hass)
            self._update_entry_token()

    def _update_entry_token(self) -> None:
        """Update config entry with refreshed token."""
        self.hass.config_entries.async_update_entry(
            self.entry,
            data={
                **self.entry.data,
                CONF_ACCESS_TOKEN: self.api.access_token,
                CONF_EXPIRES_AT: self.api.expires_at,
            },
        )

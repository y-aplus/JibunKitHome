# nRF Connect Android peripheral fixture

This directory contains only the notification macro. Nordic documents XML import/export for both macros and GATT server configurations, but its public repository does not document the GATT server configuration XML schema. Create that configuration in the app UI; do not invent an XML file from an unofficial schema.

Use these values:

- local name: `JibunKit-P2S-5276`
- primary service: `ad539a02-1289-44dc-bd27-f991c68a1fb9`
- READ + WRITE characteristic: `9e0f4195-64b6-4c4a-8ffa-e8dd8f4036d5`
- READ + NOTIFY characteristic: `0b1ec4d4-1383-4460-b1e2-9ae98653cc1b`
- all read and write permissions: open; no bonding required

nRF Connect automatically adds the Client Characteristic Configuration descriptor when NOTIFY is enabled. Import `JibunKit-P2S-notify.xml` as a macro after creating and selecting the server configuration.

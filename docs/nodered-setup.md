# Node-RED Setup Guide

Node-RED is a flow-based programming tool for wiring together hardware devices, APIs, and online services.

## Quick Start

```bash
docker compose --profile automation up -d nodered
```

## Access

- **Local:** http://192.168.2.50:1880
- **External:** https://nodered.weekendcodeproject.dev

## Environment Variables

```env
NODERED_PORT=1880
NODERED_DOMAIN=nodered.${BASE_DOMAIN}
```

## Features

- Visual flow-based programming
- 5000+ community nodes available
- Built-in dashboard UI nodes
- JavaScript function nodes
- API integrations
- MQTT support
- Home automation integrations
- Database connectors

## First-Time Setup

1. Access the web interface
2. Create your first flow
3. Deploy using the button in top-right

## Installing Additional Nodes

1. Click hamburger menu (☰) → Manage palette
2. Go to "Install" tab
3. Search for nodes (e.g., "home-assistant")
4. Click Install

### Popular Nodes

- `node-red-contrib-home-assistant-websocket` - Home Assistant integration
- `node-red-dashboard` - Create dashboards
- `node-red-contrib-influxdb` - InfluxDB connector
- `node-red-node-sqlite` - SQLite database
- `node-red-contrib-telegrambot` - Telegram bots

## Integration with Home Assistant

Install the Home Assistant nodes:
1. Manage palette → Install
2. Search "node-red-contrib-home-assistant-websocket"
3. Install and configure with your HA URL and access token

## Data Storage

Flows and settings stored in Docker volume: `nodered-data`

Key files:
- `flows.json` - Your flow definitions
- `settings.js` - Node-RED configuration
- `package.json` - Installed nodes

## Security

By default, Node-RED has no authentication. To enable:

1. Generate password hash:
```bash
docker exec -it nodered npx node-red admin hash-pw
```

2. Edit settings.js in the container to add adminAuth section

## Backup

Export flows from menu → Export → Download

Or backup the entire data volume:
```bash
docker cp nodered:/data ./nodered-backup
```

## Example Flows

### HTTP Endpoint
```json
[{"type":"http in","url":"/api/test","method":"get"},
 {"type":"http response"},
 {"wires":[["http response"]]}]
```

### Scheduled Task
Use the "inject" node with repeat interval to trigger flows on schedule.

## Troubleshooting

### Flow Not Running

- Check that flow is deployed (Deploy button)
- Check debug sidebar for errors
- Verify node configurations

### Memory Issues

Set memory limit in compose file or restart container:
```bash
docker restart nodered
```

### Lost Flows

Flows are auto-saved. Check `flows_backup.json` in data directory.

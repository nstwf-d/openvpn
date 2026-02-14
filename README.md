# OpenVPN Server with Web UI

Fast and reliable Docker container with OpenVPN Server and a Web UI for easy client management.

## Quick Start

You don't need to clone this repository to run the server. Just create a `docker-compose.yml` file with the following content:

```yaml
services:
  openvpn:
    container_name: openvpn
    image: nstwf/openvpn:latest
    devices:
      - /dev/net/tun:/dev/net/tun
    ports:
      - "1194:1194/udp"
      - "8080:8080/tcp"
    environment:
      OPENVPN_ADMIN_USERNAME: "admin"
      OPENVPN_ADMIN_PASSWORD: "admin"
      OVPN_REMOTE_HOST: "your.public.ip"
    volumes:
      - ./data:/etc/openvpn
      - ./log:/var/log/openvpn
      - ./db:/opt/openvpn-ui/db
    cap_add:
      - NET_ADMIN
      - MKNOD
    sysctls:
      - net.ipv4.ip_forward=1
    restart: always
```

Then start it with:
```bash
docker-compose up -d
```

Access the Web UI at `http://localhost:8080`.

## Client Setup

1. **Log in** to the Web UI.
2. **Important Configuration:** Before generating clients, go to **Configuration > OpenVPN Client** and change the `Remote Host` from `127.0.0.1` to your server's public IP address. This ensures that generated `.ovpn` files point to the correct server.
3. **Create a Client:** Go to the "Certificates" section and generate a new certificate for your device.
4. **Download Config:** Download the generated `.ovpn` file.
5. **Connect:** Import this file into your OpenVPN client.

## Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `OPENVPN_ADMIN_USERNAME` | Web UI admin username | `admin` |
| `OPENVPN_ADMIN_PASSWORD` | Web UI admin password | `admin` |
| `OVPN_REMOTE_HOST` | Public IP or domain for client connections | `127.0.0.1` |
| `OVPN_NETWORK` | VPN subnet for trusted clients | `10.0.70.0/24` |
| `OVPN_GUEST_NETWORK` | VPN subnet for guest clients | `10.0.71.0/24` |
| `OVPN_HOME_NETWORK` | Your home/local network to route | `192.168.88.0/24` |
| `OVPN_DNS_1` | Primary DNS server | `8.8.8.8` |
| `OVPN_DNS_2` | Secondary DNS server | `1.0.0.1` |
| `EASYRSA_REQ_COUNTRY` | EasyRSA CA Country | `KZ` |
| `EASYRSA_REQ_PROVINCE`| EasyRSA CA Province | `AST` |
| `EASYRSA_REQ_CITY`    | EasyRSA CA City | `Astana` |
| `EASYRSA_REQ_ORG`     | EasyRSA CA Organization | `AstanaHome` |
| `EASYRSA_REQ_EMAIL`   | EasyRSA CA Email | `vpn@astana.kz` |

## Volumes

- `./data:/etc/openvpn`: Stores server configuration and PKI (certificates).
- `./log:/var/log/openvpn`: Stores OpenVPN execution logs.
- `./db:/opt/openvpn-ui/db`: Stores the Web UI database (users and settings).

## Features

- **Web UI:** Easy management of certificates and clients.
- **Auto-Config:** Automatically generates CA, server certificates, and CRL on the first run.
- **Traffic Routing:** Pre-configured iptables for NAT and internet access.
- **Dual Subnets:** Support for trusted and guest networks with isolation rules.
- **MFA/2FA Support:** Includes `oath-toolkit` for Two-Factor Authentication.

## Useful Information

### Troubleshooting
If the server doesn't start or clients can't connect, check the logs:
```bash
docker logs -f openvpn
```

#### "ERROR:name does not match" during Revocation
If you see an error like `ERROR:name does not match /C=UA/...` when trying to revoke a certificate, it means your existing PKI (in the `data/` volume) was created with different location settings (e.g., Ukraine) than the current container defaults (Kazakhstan).
- **To use new defaults:** Delete the `data/` and `db/` volumes and restart the container (this will delete all existing certificates!).
- **To keep existing certificates:** Set the `EASYRSA_REQ_*` environment variables in your `docker-compose.yml` to match your original settings (e.g., `EASYRSA_REQ_COUNTRY=UA`).

### Port Forwarding
Ensure your router/firewall forwards the following ports to your host:
- `1194/UDP` (VPN traffic)
- `8080/TCP` (Web UI - optional, should be protected)

### Host Requirements
The container handles IP forwarding internally, but your host kernel must support it. Most Linux distributions have it enabled by default, but you can verify:
```bash
sysctl net.ipv4.ip_forward
```

### How to Update
To update to the latest version:
```bash
docker-compose pull
docker-compose up -d
```

### Security Tip
Change the default admin password (`OPENVPN_ADMIN_PASSWORD`) immediately after the first run. 

**Note on changing credentials:** The admin username and password are saved in the database during the first initialization. If you change `OPENVPN_ADMIN_USERNAME` or `OPENVPN_ADMIN_PASSWORD` in your `docker-compose.yml` later, you **must** delete the `./db/` directory and restart the container for the changes to take effect:
```bash
docker-compose down
rm -rf ./db/*
docker-compose up -d
```
*Warning: This will reset all Web UI settings, but won't delete your certificates.*

For production use, it is highly recommended to put the Web UI behind a reverse proxy (like Nginx with SSL) or only expose it to your local/VPN network.

---
Based on [d3vilh/openvpn-server](https://github.com/d3vilh/openvpn-server).

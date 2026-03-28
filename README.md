# Operation Lighthouse 

**Sovereign Remote Access for LaunchCloud Labs & FLEH (FirstLight | EventHorizon)**

Operation Lighthouse is a custom Ruby-orchestrated mesh network designed to provide secure, direct SSH access to internal HomeBase servers without relying on third-party VPNs like Tailscale.

## The Architecture

1. **The Lighthouse (VPS):** A public-facing relay server that acts as a secure bridge.
2. **The HomeBase (Server):** Your home/internal server that maintains a persistent reverse SSH tunnel to the Lighthouse.
3. **The Employee (Shelly SSH):** Employees connect directly to the Lighthouse on a specific port, which transparently tunnels them into the HomeBase.

## The CLI (`fleh-mesh`)

This repository provides a Ruby CLI to automate the entire deployment.

### 1. Provision the Lighthouse
Run this from your workstation to configure a new public VPS.
```bash
./bin/fleh-mesh init_lighthouse [VPS_IP]
```
*Configures GatewayPorts, creates a service user, and sets up the firewall.*

### 2. Connect the HomeBase
Run this on the machine you want to make accessible (the "Black Box").
```bash
./bin/fleh-mesh connect_home [LIGHTHOUSE_IP]
```
*Installs a persistent systemd service that maintains the tunnel 24/7.*

### 3. Add an Employee
Generate access for a new team member.
```bash
./bin/fleh-mesh add_user [NAME]
```
*Creates an SSH keypair, authorizes it on the HomeBase, and provides simple instructions for the **Shelly SSH** app.*

## Security
- **Zero Open Ports:** Your HomeBase remains invisible to the public internet.
- **Key-Based Auth Only:** No passwords. Only authorized SSH keys can traverse the tunnel.
- **Sovereign Control:** You own the Lighthouse VPS and the orchestration code.

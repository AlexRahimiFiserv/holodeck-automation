# HoloRouter Reverse Proxy Automation

This script automates NGINX reverse proxy configuration on the HoloRouter for VMware Holodeck VCF environments. It generates SSL certificates, rebuilds NGINX configurations, enables SSH forwarding, and provides access to internal VCF components and ESXi hosts through a single external IP address.

## Prerequisites

SSH to your HoloRouter and ensure the following files are located in the same directory:

```text
holodeck-vars.conf
setup-holorouter-proxy.sh
```

## Configuration

Edit the configuration file if your environment differs from the default deployment:

```bash
vi holodeck-vars.conf
```

Update hostnames, domains, or IP addresses as needed.

## Installation

Make the script executable and run it as root:

```bash
chmod +x setup-holorouter-proxy.sh
sudo ./setup-holorouter-proxy.sh
```

## Post-Installation

After the script completes:

1. Copy the hosts file entries displayed on the screen.
2. Add them to your Windows hosts file:

```text
C:\Windows\System32\drivers\etc\hosts
```

3. Flush your DNS cache:

```powershell
ipconfig /flushdns
```

## Validation

Test connectivity to your environment using a browser:

```text
https://vc-mgmt-a.site-a.vcf.lab
https://esx-01a.site-a.vcf.lab
```

If configured correctly, traffic will be routed through the HoloRouter reverse proxy to the appropriate internal VCF service.

## Disclaimer

This project is intended for VMware Holodeck lab environments. Review all configuration changes and validate functionality in a non-production environment before deployment.

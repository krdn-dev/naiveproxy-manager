# 🚀 NaiveProxy Installer

**Automated NaiveProxy setup for Linux server**

## ✨ Features

- 🚀 Auto-installation of the latest Go version
- 🔧 Building Caddy with the forwardproxy plugin from source
- 🔐 Real Let's Encrypt SSL certificates
- 📱 Client config generation (JSON, URL, QR-code)
- 🖥️ Support for all major Linux distributions
- ⚡ Auto-enable BBR for better speed
- 🛡️ DNS, port availability, and system requirements checks

## 📋 Supported Systems

| System | Versions |
|--------|----------|
| Debian | 11+ |
| Ubuntu | 20.04+ |
| CentOS | 8+ |
| Fedora | 37+ |
| AlmaLinux / Rocky Linux | 8+ |

## 🚀 Quick Installation

```bash
wget https://raw.githubusercontent.com/krdn-dev/naiveproxy-installer/main/naiveproxy.sh
chmod +x naiveproxy.sh
sudo ./naiveproxy.sh

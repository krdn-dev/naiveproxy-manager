# NaiveProxy Installer

**Automated NaiveProxy setup for Linux server**

**🧪 Status:** The script is in testing phase. Tested by me on Debian 13. Please test on other OS and report via [Issues](https://github.com/krdn-dev/naiveproxy-installer/issues)

**⚠️ Disclaimer:** This script is provided "as is". The author is not responsible for any data loss or damage arising from its use.

## ✨ Features

| Feature | Description |
|---------|-------------|
| 🚀 **Latest Go** | Auto‑installs the newest stable Go version |
| 🔧 **Custom Caddy** | Builds Caddy + forwardproxy from source |
| 🔐 **Let's Encrypt** | Real SSL certificates for your domain |
| 📱 **Client configs** | JSON, URL, and QR‑code for easy import |
| 🖥️ **Cross‑platform** | Works on Debian, Ubuntu, CentOS, Fedora, AlmaLinux, Rocky |
| ⚡ **BBR** | Enables TCP BBR for better performance |
| 🛡️ **Pre‑flight checks** | DNS, port, and system requirements validation |
| 🛡️ **fail2ban** | Automatic SSH brute‑force protection |
| 🎨 **Corporate site simulation** | Full multi-page website (About, Blog, Contact, sitemap, robots.txt) |
| 🔄 **Auto‑updates** | Security updates (unattended‑upgrades / dnf‑automatic) |

## 📋 Supported Systems

| System | Versions |
|--------|----------|
| **Debian** | 11+ |
| **Ubuntu** | 20.04+ |
| **CentOS / Rocky / Alma / Oracle** | 9+ |
| **Fedora** | 37+ |

## 🚀 Quick Installation

```bash
wget -O naiveproxy.sh https://raw.githubusercontent.com/krdn-dev/naiveproxy-installer/main/naiveproxy.sh && bash naiveproxy.sh
```
## 🛠️ Menu & Management  
### After launching the script, you'll see a simple menu:

| Option | Action |
|-------|----------|
| **1** | Install NaiveProxy |
| **2** | Uninstall NaiveProxy |
| **3** | Start NaiveProxy |
| **4** | Stop NaiveProxy |
| **5** | Restart NaiveProxy |
| **6** | Show client config |
| **0** | Exit |

## 📲 Clients

| Platform | Recommended Clients |
|-----------|----------------------|
| **Windows** | [NekoRay](https://github.com/MatsuriDayo/nekoray), [Hiddify](https://github.com/hiddify/hiddify-app) |
| **Android** | [NekoBox](https://github.com/MatsuriDayo/NekoBoxForAndroid), [Matsuri](https://github.com/MatsuriDayo/Matsuri) |
| **iOS** | [Shadowrocket](https://apps.apple.com/ru/app/shadowrocket/id932747118), [Karing](https://apps.apple.com/us/app/karing/id6472431552) |
| **macOS / Linux** | [NekoRay](https://github.com/MatsuriDayo/nekoray), [sing-box](https://github.com/SagerNet/sing-box) | 

**Connection string format:** ```naive+https://LOGIN:PASSWORD@YOUR_DOMAIN:443```

Example: ```naive+https://john:myPass123@example.com:443```

## ❓ FAQ
### Why do I need a domain?  
NaiveProxy mimics regular HTTPS traffic. It requires a real domain and an SSL certificate for proper masking.

### What if installation fails?  
Re-run the script, choose option 2 ("Uninstall"), then install again.

### How to update NaiveProxy?  
The script always builds the latest versions. To update, uninstall (option 2) and then install again (option 1).

### Can I connect from multiple devices?  
Yes, just use the same connection details on all devices.

## 📄 License
This project is licensed under the  [![MIT License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)  

You are free to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the software.  

## 🙏 Acknowledgements
This script is based on the work of these projects and developers:  

- [NaiveProxy](https://github.com/klzgrad/naiveproxy) от [klzgrad](https://github.com/klzgrad) — for the proxy protocol itself 
- [Caddy](https://github.com/caddyserver/caddy) — for the excellent web server  
- [forwardproxy](https://github.com/klzgrad/forwardproxy) — for the Caddy plugin 
- [xcaddy](https://github.com/caddyserver/xcaddy) — for the convenient build tool  

**Many thanks to them for their hard work!**

## 💰 Support the Project  
If this script saved you time and you'd like to support its development, you can send a small donation   [![Bitcoin](https://img.shields.io/badge/Bitcoin-F7931A?style=flat&logo=bitcoin&logoColor=white)](https://www.blockchain.com/explorer/addresses/btc/bc1p4ttkpfrgzpm7nyymyzdgyd2y6z04s62nxpygk38yylcp3t47m98qwnuhen)
```bc1p4ttkpfrgzpm7nyymyzdgyd2y6z04s62nxpygk38yylcp3t47m98qwnuhen```

❤️ Thank you for your support!     
⭐ Star this repository if the script helped you!

# NaiveProxy Manager
NaiveProxy Manager is not just a proxy installer. It solves the **main problem** of modern censorship circumvention: it makes your traffic indistinguishable from a real corporate website.

Unlike typical scripts, NaiveProxy Manager includes **WebGhost** — a dedicated Go service that:

- **Generates a full corporate website** (multi‑page, with a blog, news, sitemap)
- **Simulates real visitor behavior** (different browsers, reading pauses, form submissions, search bots)
- **Adds background noise** (scanner requests, SQL‑injection attempts, OPTIONS/PUT probes)
- **Supports mutual imitation** (two servers can generate traffic to each other)
- **Updates with a single command** (no Go toolchain required on the server)

Everything is pre‑compiled, fully automated, and tested on 7 Linux distributions.

## ✨ Features
| Feature | Description |
|---------|-------------|
| 🚀 **One‑command installation** | Full cycle: proxy, site, firewall, BBR, fail2ban, limits |
| 🌐 **Realistic website** | Full corporate portal with blog, contacts, sitemap |
| 🕵️ **Traffic simulation** | Concurrent user sessions with natural behavior |
| 🔊 **Noise generation** | Background requests that imitate scanners and attacks |
| 🔄 **Mutual imitation** | Two servers exchange traffic for bidirectional camouflage |
| 🔐 **Let's Encrypt** | Real SSL certificates for your domain |
| 💾 **Certificate backup & restore** | Automatic backup during installation, manual restore from menu. Allows reinstalling NaiveProxy without wasting the Let's Encrypt rate limit (5 certificates per week) |
| 📱 **Client configs** | JSON, link, QR‑code for import |
| 🔥 **Rate limiting** | DDoS and brute‑force protection in Caddy |
| 🛡️ **fail2ban** | SSH brute‑force protection |
| ⚡ **BBR** | TCP connection acceleration |
| 🧹 **System tuning** | Swap, limits, disabling unnecessary services, firewall |
| 💾 **Smart swap** | Automatic swap file creation on low‑memory servers (OOM Killer protection) |
| 🔧 **System maintenance** | System update and cleanup (apt full‑upgrade / dnf update) |
| 🔄 **Auto‑updates** | Automatic security updates (unattended‑upgrades / dnf‑automatic) |
| 🖥️ **Cross‑platform** | Works on Debian, Ubuntu, CentOS, Fedora, AlmaLinux, Rocky, Oracle |

## 📋 Supported Systems

| System | Versions |
|--------|----------|
| **Debian** | 11+ |
| **Ubuntu** | 20.04+ |
| **CentOS / Rocky / Alma / Oracle** | 9+ |
| **Fedora** | 37+ |

## 🚀 Quick Installation

```bash
wget -O naivemanager.sh https://raw.githubusercontent.com/krdn-dev/naiveproxy-manager/main/naivemanager.sh
chmod +x naivemanager.sh
sudo ./naivemanager.sh
```
or
```bash
wget -O naivemanager.sh https://raw.githubusercontent.com/krdn-dev/naiveproxy-installer/main/naivemanager.sh && bash naivemanager.sh
```

## 🛠️ Menu & Management  
### After launching the script, you'll see a simple menu:

![NaiveProxyManager Menu](https://github.com/krdn-dev/naiveproxy-manager/blob/main/NaiveManager%20Menu.PNG?raw=true)

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
### How is NaiveProxy Manager different from other NaiveProxy installers?
Most scripts only install the proxy and leave an empty placeholder. At most, they generate static HTML. NaiveProxy Manager is the first to combine a full website generator, user behavior simulator, and noise generator into a single package, specifically designed to defeat traffic analysis.

### Why do I need a domain?  
NaiveProxy mimics regular HTTPS traffic. It requires a real domain and an SSL certificate for proper masking.

### What if installation fails?  
Re-run the script, choose option 2 ("Uninstall"), then install again.

### How to update NaiveProxy?  
The script always builds the latest versions. To update, uninstall (option 2) and then install again (option 1).

### How do I set up mutual traffic imitation with another server?
During installation (option 1), after entering your email, the script will ask: "Enter remote server for mutual traffic imitation".
Enter the domain or IP of your second server that has NaiveProxy installed. After that:

your server will send requests to the second server in full mode (1–3 sessions),

and to itself — in light mode (1–2 sessions).

Thus, the traffic ratio between the servers will be approximately 1:3 (light local imitation + active mutual imitation).
This makes network activity patterns more realistic and resistant to analysis.

### Does the remote server have to run NaiveProxy Manager?
Technically, any server that responds to HTTPS requests will work. However, for full imitation realism, it is recommended that both servers have NaiveProxy Manager installed with a generated website. Otherwise, some requests will return 404 and reduce traffic credibility.

### Can I get details about the signatures WebGhost uses for traffic imitation?
This information is intentionally not disclosed. The less detail about internal algorithms and templates reaches the public domain, the harder it is for Deep Packet Inspection (DPI) systems to develop countermeasures. Developers on "the other side" also read documentation, so the most effective settings stay inside the code.

### How can I verify that WebGhost is working and traffic imitation is active?
All activity is logged to `/var/log/webghost-activity.log` 
To view the accumulated records, run the following command in the terminal: ```cat /var/log/webghost-activity.log```

In the log you will see:
page visits (HTTP 200), requests to resources (favicon.ico, style.css, images), User‑Agent rotation and emulation of different browsers, background noise (rare requests to non‑existent pages), and much more.

### Do I need to re‑enter the password and domain when reinstalling?
No. All entered data (domain, port, login, password, email, SSH port, and remote server address) is automatically saved in `/root/naive/runtime.env`
When you run the script again and choose `Install`, it will offer to use the saved settings — just press Enter to confirm.

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
If this script saved you time and you'd like to support its development, you can send a small donation       
[![Bitcoin](https://img.shields.io/badge/Bitcoin-F7931A?style=flat&logo=bitcoin&logoColor=white)](https://www.blockchain.com/explorer/addresses/btc/bc1p4ttkpfrgzpm7nyymyzdgyd2y6z04s62nxpygk38yylcp3t47m98qwnuhen)
```bc1p4ttkpfrgzpm7nyymyzdgyd2y6z04s62nxpygk38yylcp3t47m98qwnuhen```

❤️ Thank you for your support!     
⭐ Star this repository if the script helped you!

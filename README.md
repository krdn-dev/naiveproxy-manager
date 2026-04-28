# NaiveProxy Installer 🚀

[![MIT License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

**Автоматическая установка NaiveProxy на Linux сервер**

## ✨ Особенности

- 🚀 Автоустановка последней версии Go
- 🔧 Сборка Caddy с плагином forwardproxy
- 🔐 Реальные SSL-сертификаты Let's Encrypt
- 📱 Генерация конфигураций (JSON, URL, QR-код)
- 🖥️ Поддержка всех основных дистрибутивов Linux
- ⚡ Автовключение BBR

## 📋 Поддерживаемые системы

| Система | Версии |
|---------|--------|
| Debian | 11+ |
| Ubuntu | 20.04+ |
| CentOS | 8+ |
| Fedora | 37+ |
| AlmaLinux / Rocky Linux | 8+ |

## 🚀 Быстрая установка

```bash
wget https://raw.githubusercontent.com/krdn-dev/naiveproxy-installer/main/naiveproxy.sh
chmod +x naiveproxy.sh
sudo ./naiveproxy.sh
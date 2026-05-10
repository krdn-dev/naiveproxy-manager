# NaiveProxy Manager    
NaiveProxyManager — это не просто установщик прокси. Он решает **главную проблему** современного обхода цензуры: делает ваш трафик неотличимым от настоящего корпоративного сайта.

В отличие от типичных скриптов, NaiveProxy Manager включает **WebGhost** — выделенный Go-сервис, который:

- **Генерирует полноценный корпоративный сайт** (многостраничный, с блогом, новостями, картой сайта)
- **Имитирует поведение реальных посетителей** (разные браузеры, паузы чтения, отправка форм, поисковые боты)
- **Добавляет фоновый шум** (запросы сканеров, попытки SQL-инъекций, OPTIONS/PUT пробы)
- **Поддерживает взаимную имитацию** (два сервера могут генерировать трафик друг для друга)
- **Обновляется одной командой** (не требует установленного Go на сервере)

Всё предварительно скомпилировано, полностью автоматизировано и протестировано на 7 дистрибутивах Linux.

## ✨ Особенности
| Функция | Описание |
|---------|----------|
| 🚀 **Установка одной командой** | Полный цикл: прокси, сайт, фаервол, BBR, fail2ban, лимиты |
| 🌐 **Реалистичный сайт** | Полноценный корпоративный портал с блогом, контактами, sitemap |
| 🕵️ **Имитация трафика** | Одновременные сессии пользователей с естественным поведением |
| 🔊 **Генерация шума** | Фоновые запросы, имитирующие сканеры и атаки |
| 🔄 **Взаимная имитация** | Два сервера обмениваются трафиком для двусторонней маскировки |
| 🔐 **Let's Encrypt** | Настоящие SSL-сертификаты для вашего домена |
| 📱 **Клиентские конфиги** | JSON, ссылка, QR-код для импорта |
| 🔥 **Ограничение лимитов** | Защита от DDoS-атак и атак методом перебора паролей в Caddy |
| 🛡️ **fail2ban** | Защита SSH от подбора паролей |
| ⚡ **BBR** | Ускорение TCP-соединений |
| 🧹 **Системные настройки** | Swap, лимиты, отключение лишних служб, фаервол |
| 💾 **Умный swap** | Автоматическое создание swap-файла на серверах с малым объёмом RAM (защита от OOM Killer) |
| 🔧 **Обслуживание системы** | Обновление и очистка системы (apt full-upgrade / dnf update) |
| 🔄 **Автообновления** | Автоматические обновления безопасности (unattended-upgrades / dnf-automatic) |
| 🖥️ **Кроссплатформенность** | Работает на Debian, Ubuntu, CentOS, Fedora, AlmaLinux, Rocky, Oracle |

## 📋 Поддерживаемые системы
| Система | Версии |
|---------|--------|
| **Debian** | 11+ |
| **Ubuntu** | 20.04+ |
| **CentOS / Rocky / Alma / Oracle** | 9+ |
| **Fedora** | 37+ |

## 🚀 Быстрая установка

```bash
wget -O naivemanager.sh https://raw.githubusercontent.com/krdn-dev/naiveproxy-manager/main/naivemanager.sh
chmod +x naivemanager.sh
sudo ./naivemanager.sh
```
or
```bash
wget -O naivemanager.sh https://raw.githubusercontent.com/krdn-dev/naiveproxy-installer/main/naivemanager.sh && bash naivemanager.sh
```

## 🛠️ Меню и управление  
### После запуска скрипта вам будет доступно простое меню:

![NaiveProxyManager Menu](https://github.com/krdn-dev/naiveproxy-manager/blob/main/NaiveManager%20Menu.PNG?raw=true)

## 📲 Клиенты для подключения

| Платформа | Рекомендуемые клиенты |
|-----------|----------------------|
| **Windows** | [NekoRay](https://github.com/MatsuriDayo/nekoray), [Hiddify](https://github.com/hiddify/hiddify-app) |
| **Android** | [NekoBox](https://github.com/MatsuriDayo/NekoBoxForAndroid), [Matsuri](https://github.com/MatsuriDayo/Matsuri) |
| **iOS** | [Shadowrocket](https://apps.apple.com/ru/app/shadowrocket/id932747118), [Karing](https://apps.apple.com/us/app/karing/id6472431552) |
| **macOS / Linux** | [NekoRay](https://github.com/MatsuriDayo/nekoray), [sing-box](https://github.com/SagerNet/sing-box) |

Формат подключения: ```naive+https://ЛОГИН:ПАРОЛЬ@ВАШ_ДОМЕН:443```

Пример: ```naive+https://john:myPass123@example.com:443```

## ❓ Часто задаваемые вопросы
### Чем NaiveProxy Manager отличается от других установщиков NaiveProxy?
Большинство скриптов только устанавливают прокси и оставляют пустую заглушку. Максимум — генерируют статический HTML. NaiveManager — первый, кто объединяет **полноценный генератор сайта**, **имитатор поведения пользователей** и **генератор шума** в единый пакет, специально созданный для противодействия анализу трафика.

### Почему нужен домен?  
NaiveProxy маскируется под обычный HTTPS-трафик. Без реального домена и SSL-сертификата маскировка не работает.

### Что делать, если установка прервалась с ошибкой?  
Запустите скрипт снова, выберите пункт 2 («Удалить»), затем повторите установку.

### Как обновить NaiveProxy Manager?  
Скрипт всегда собирает последнюю версию. Чтобы получить актуальную версию, удалите прокси (пункт 2) и установите заново (пункт 1).

### Можно ли подключаться с нескольких устройств?  
Да, используйте одни и те же данные для подключения на всех устройствах.

## 📄 Лицензия
Проект распространяется под лицензией  [![MIT License](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)  

Кратко: можно использовать, копировать, модифицировать, распространять с указанием авторства.  

## 🙏 Благодарности
Этот скрипт основан на работе следующих проектов и разработчиков:  

- [NaiveProxy](https://github.com/klzgrad/naiveproxy) от [klzgrad](https://github.com/klzgrad) — за сам прокси-протокол  
- [Caddy](https://github.com/caddyserver/caddy) — за отличный веб-сервер  
- [forwardproxy](https://github.com/klzgrad/forwardproxy) — за плагин для Caddy  
- [xcaddy](https://github.com/caddyserver/xcaddy) — за удобную сборку  

**Большое спасибо им за их труд!**

## 💰 Поддержать проект  
Если хотите поддержать развитие проекта, можете отправить небольшое пожертвование    
[![Bitcoin](https://img.shields.io/badge/Bitcoin-F7931A?style=flat&logo=bitcoin&logoColor=white)](https://www.blockchain.com/explorer/addresses/btc/bc1p4ttkpfrgzpm7nyymyzdgyd2y6z04s62nxpygk38yylcp3t47m98qwnuhen)
```bc1p4ttkpfrgzpm7nyymyzdgyd2y6z04s62nxpygk38yylcp3t47m98qwnuhen```

❤️ Спасибо за поддержку!     
⭐ Поставьте звезду репозиторию, если скрипт вам помог!

# NaiveProxy Installer 

**Автоматическая установка NaiveProxy на Linux сервер**

**🧪 Статус:** Скрипт находится в стадии тестирования. Мной опробован на Debian 13. Прошу протестировать на других ОС и сообщить через [Issues](https://github.com/krdn-dev/naiveproxy-installer/issues)

**⚠️ Отказ от ответственности:** Скрипт распространяется как есть. Автор не несёт ответственности за возможные потери данных или убытки.

## ✨ Особенности
- 🚀 Автоустановка последней версии Go
- 🔧 Сборка Caddy с плагином forwardproxy
- 🔐 Реальные SSL-сертификаты Let's Encrypt
- 📱 Генерация конфигураций (JSON, URL, QR-код)
- 🖥️ Поддержка всех основных дистрибутивов Linux
- ⚡ Автовключение BBR
- 🛡️ Проверка DNS, доступности портов и системных требований

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
wget -O naiveproxy.sh https://raw.githubusercontent.com/krdn-dev/naiveproxy-installer/main/naiveproxy.sh && sudo bash naiveproxy.sh
```
## 🛠️ Меню и управление  
### После запуска скрипта вам будет доступно простое меню:

| Пункт | Действие |
|-------|----------|
| 1 | Установить NaiveProxy |
| 2 | Удалить NaiveProxy |
| 3 | Запустить NaiveProxy |
| 4 | Остановить NaiveProxy |
| 5 | Перезапустить NaiveProxy |
| 6 | Показать конфигурацию клиента |
| 0 | Выйти |

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
### Почему нужен домен?  
NaiveProxy маскируется под обычный HTTPS-трафик. Без реального домена и SSL-сертификата маскировка не работает.

### Что делать, если установка прервалась с ошибкой?  
Запустите скрипт снова, выберите пункт 2 («Удалить»), затем повторите установку.

### Как обновить NaiveProxy?  
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
Спасибо, что пользуетесь скриптом! Если хотите поддержать развитие проекта, можете отправить небольшое пожертвование.  

**Bitcoin (BTC):**
`bc1p4ttkpfrgzpm7nyymyzdgyd2y6z04s62nxpygk38yylcp3t47m98qwnuhen`

❤️ Спасибо за поддержку!     
⭐ Поставьте звезду репозиторию, если скрипт вам помог!

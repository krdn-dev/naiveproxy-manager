# NaiveProxy Manager 

**Автоматическая установка NaiveProxy на Linux сервер**

**🧪 Статус:** Скрипт находится в стадии тестирования. Мной опробован на Debian 13. Прошу протестировать на других ОС и сообщить через [Issues](https://github.com/krdn-dev/naiveproxy-installer/issues)

**⚠️ Отказ от ответственности:** Скрипт распространяется как есть. Автор не несёт ответственности за возможные потери данных или убытки.

## ✨ Особенности
| Функция | Описание |
|---------|----------|
| 🚀 **Последняя версия Go** | Автоматическая установка актуальной стабильной версии Go |
| 🔧 **Кастомный Caddy** | Сборка Caddy из исходников с плагином forwardproxy |
| 🔐 **Let's Encrypt** | Настоящие SSL/TLS-сертификаты для вашего домена |
| 📱 **Клиентские конфиги** | Генерация JSON, ссылки для импорта и QR-кода |
| 🖥️ **Кроссплатформенность** | Работает на Debian, Ubuntu, CentOS, Fedora, AlmaLinux, Rocky, Oracle |
| ⚡ **BBR** | Включение алгоритма TCP BBR для ускорения соединений |
| 🛡️ **Предварительные проверки** | Проверка DNS, доступности портов и системных требований |
| 🛡️ **fail2ban** | Автоматическая защита SSH от подбора паролей (брутфорса) |
| 🎨 **Корпоративный сайт** | Имитация полноценного портала с несколькими страницами, блогом, robots.txt и sitemap.xml |
| 🔄 **Автообновления** | Настройка автоматических обновлений безопасности (unattended-upgrades / dnf-automatic) |
| 💾 **Умный swap** | Автоматическое создание swap-файла на серверах с малым объёмом RAM (защита от OOM Killer) |
| 🔥 **Ограничение лимитов** | Защита от DDoS-атак и атак методом перебора паролей в Caddy |
| 🔧 **Обслуживание системы** | Полное обновление и очистка системы (apt full-upgrade / dnf update) |
| 📊 **Информация о системе** | Подробный отчет о состоянии системы (ОЗУ, диск, службы, открытые порты) |
| 🔒 **Пользовательский SSH-порт** | Изменение порта SSH с автоматической перенастройкой брандмауэра и fail2ban |
| ⚙️ **Поддержка брандмауэра** | UFW для Debian/Ubuntu, firewalld для RHEL |
| 📈 **Системные ограничения** | Увеличено ограничение на количество открытых файлов до 2 097 152 |
| 🧹 **Уборка** | Отключены ненужные службы (avahi, bluetooth, cups и т. д.) |

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

| Пункт | Действие |
|-------|----------|
| **1** | Установить |
| **2** | Удалить |
| **3** | Запустить |
| **4** | Остановить |
| **5** | Перезапустить |
| **6** | Конфигурация клиента |
| **7** | Системная информация |
| **8** | Обслуживание системы |
| **0** | Выйти |

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
Если хотите поддержать развитие проекта, можете отправить небольшое пожертвование   [![Bitcoin](https://img.shields.io/badge/Bitcoin-F7931A?style=flat&logo=bitcoin&logoColor=white)](https://www.blockchain.com/explorer/addresses/btc/bc1p4ttkpfrgzpm7nyymyzdgyd2y6z04s62nxpygk38yylcp3t47m98qwnuhen)
```bc1p4ttkpfrgzpm7nyymyzdgyd2y6z04s62nxpygk38yylcp3t47m98qwnuhen```

❤️ Спасибо за поддержку!     
⭐ Поставьте звезду репозиторию, если скрипт вам помог!

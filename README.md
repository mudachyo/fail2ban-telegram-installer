# fail2ban-telegram-installer

Автоматическая установка и настройка **Fail2Ban** с **Telegram-уведомлениями** на серверах Ubuntu.

Скрипт автоматически:
- устанавливает Fail2Ban
- настраивает SSH-защиту (3 попытки → блокировка на 3 часа)
- настраивает защиту от рецидивов (recidive — повторные блокировки навсегда)
- создаёт Telegram-бота для уведомлений о блокировках и разблокировках

---

## Требования

- **Ubuntu**
- `sudo`-доступ
- Telegram Bot Token (как создать — см. ниже)

---

## Быстрый старт

Запустите скрипт одной командой:

```bash
bash <(wget -qO- https://github.com/mudachyo/fail2ban-telegram-installer/raw/refs/heads/main/fail2ban-setup.sh)
```

Скрипт выполнит установку в интерактивном режиме.

---

## Как получить Telegram Bot Token и Chat ID

### 1. Создайте бота

1. Откройте чат с [@BotFather](https://t.me/BotFather) в Telegram.
2. Отправьте команду `/newbot`.
3. Следуйте инструкциям — введите имя бота (например, `Fail2Ban Alert`) и username (например, `fail2ban_alert_bot`).
4. После создания BotFather пришлёт **Token**. Скопируйте его.

### 2. Узнайте Chat ID

1. Найдите своего бота в Telegram и отправьте ему любое сообщение (например, `/start`).
2. Откройте в браузере: `https://api.telegram.org/bot<TOKEN>/getUpdates`
3. В ответе найдите `"chat":{"id":<CHAT_ID>}` — это ваш Chat ID (обычно отрицательное число).

---

## Проверка после установки

```bash
# Статус Fail2Ban
sudo fail2ban-client status

# Статус SSH jail
sudo fail2ban-client status sshd

# Статус recidive jail
sudo fail2ban-client status recidive

# Логи Fail2Ban
sudo tail -f /var/log/fail2ban.log
```

---

## Пример уведомления в Telegram

```
🚫 Fail2Ban
Статус: Заблокирован IP

🖥 Сервер: my-server
📦 Jail: sshd
🌐 IP: 192.168.1.100
🕒 Время: 15.03.2026 14:30:00
```

---

## Удаление

```bash
# Остановить и отключить Fail2Ban
sudo systemctl stop fail2ban
sudo systemctl disable fail2ban

# Удалить Fail2Ban
sudo apt remove --purge fail2ban

# Удалить скрипты (опционально)
sudo rm /usr/local/bin/fail2ban-telegram.sh
sudo rm /etc/fail2ban/action.d/telegram.conf
```

---

## Лицензия

MIT

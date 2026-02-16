
# WhiteLogs

Clean and accurate shot logs.

## Description

**WhiteLogs** — это Lua-скрипт для чистых и понятных логов выстрелов.
Без лишних сообщений, без спама, без перегруженной информации.

Скрипт выводит только важные данные о каждом shot — аккуратно и читаемо.

---

## Features

* Чистые miss / hit logs
* Отображение reason
* Hitgroup
* Damage
* Backtrack (bt)
* Флаги состояния (dt / lc / tp / fl)
* Без лишних уведомлений

---

## Log Format

### Miss:

```
Missed shot due to resolver at enemy's head for 80 (bt=2)
```

### Hit:

```
Registered shot at enemy's chest for 72 (bt=1)
```

Если фактический damage отличается от ожидаемого:

```
Registered shot at enemy's chest for 72 aimed=head(80) (bt=1)
```

---

## What makes it different

* Минималистичный стиль
* Читаемые и аккуратные строки
* Только полезная информация
* Никакого визуального мусора

---

## Installation

1. Поместите `.lua` файл в папку со скриптами
2. Загрузите через Lua Tab
3. Готово

---

Simple. Clean. Accurate.

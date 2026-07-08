# 🚀 Remnawave Node Auto-Installer v3.0

<div align="center">
  
![Version](https://img.shields.io/badge/version-3.0-blue.svg)
![Bash](https://img.shields.io/badge/bash-5.0+-green.svg)
![License](https://img.shields.io/badge/license-MIT-yellow.svg)
![Docker](https://img.shields.io/badge/docker-required-blue.svg)
![OS](https://img.shields.io/badge/OS-Ubuntu/Debian-orange.svg)

</div>

## 📖 О проекте

**Remnawave Node Auto-Installer** — это многофункциональный bash-скрипт для автоматической установки и настройки Remnawave Node на серверах под управлением Ubuntu/Debian. Скрипт включает в себя полный набор инструментов для развертывания, оптимизации и управления узлом.

## ✨ Возможности

### 🎯 Основные функции
- **Автоматическая установка** Remnawave Node с использованием Docker
- **Настройка с доменом** — установка с SSL-сертификатом Let's Encrypt и сайтом-заглушкой
- **Сетевая оптимизация** — настройка BBR, TCP FastOpen, буферов и других параметров
- **Управление брандмауэром** — автоматическая настройка UFW
- **Мониторинг и управление** — просмотр логов, перезапуск, обновление ноды
- **Системная диагностика** — проверка ядра, DNS, портов
- **Бэкап конфигураций** — сохранение всех настроек

### 📋 Детальный функционал

| Функция | Описание |
|---------|----------|
| Установка ноды | Быстрая установка с минимальными настройками |
| Установка с доменом | Полная настройка с Nginx, SSL и сайтом-заглушкой |
| Сетевая оптимизация | Автоматическая настройка параметров ядра Linux |
| Firewall | Настройка UFW с открытием необходимых портов |
| Проверка системы | Диагностика ядра, DNS, доступности портов |
| Управление нодой | Логи, перезапуск, остановка, обновление |
| Статус | Просмотр состояния всех компонентов |
| Бэкап | Сохранение конфигураций с возможностью архивации |

## 🚀 Быстрый старт

### 📋 Требования
- **ОС:** Ubuntu 20.04+ / Debian 11+
- **Права:** Root доступ
- **Интернет:** Доступ к репозиториям Docker и GitHub

### 📦 Установка

```bash
# Скачивание скрипта
wget -O remnawave-installer.sh https://raw.githubusercontent.com/yourusername/remnawave-installer/main/installer.sh

# Делаем исполняемым
chmod +x remnawave-installer.sh

# Запуск
sudo ./remnawave-installer.sh

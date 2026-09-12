<div align="center">

<img src="assets/images/icon_windows.png" alt="Protogenix" width="160" />

# Protogenix

**Музыкальный плеер с караоке-текстами, импортом музыки по ссылкам и живым интерфейсом.**

*A Flutter music player with synced karaoke lyrics.*

[![Платформы](https://img.shields.io/badge/платформы-Android%20%7C%20Windows-8A7FD6?style=flat-square)](#-установка)
[![Flutter](https://img.shields.io/badge/Flutter-3.44-02569B?style=flat-square&logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.12-0175C2?style=flat-square&logo=dart&logoColor=white)](https://dart.dev)
[![Z43 Studios](https://img.shields.io/badge/by-Z43%20Studios-1A1726?style=flat-square)](https://z43-studios.vercel.app/)

</div>

---

## ✨ Возможности

**Музыка**
- Поиск по YouTube и добавление треков в медиатеку в один тап
- Импорт по ссылкам YouTube, Spotify, Яндекс Музыки и прямым ссылкам на аудио, а также из файлов на устройстве
- Медиатека, избранное и плейлисты с перетаскиванием треков
- Очередь, «играть следующим», перемешивание и повтор
- Таймер сна с плавным затуханием и режимом «остановить после трека»
- Редактирование названия и исполнителя
- На Android — фоновое воспроизведение и управление из шторки и с экрана блокировки

**Тексты песен**
- Синхронизированные тексты подбираются автоматически из LRCLIB и NetEase
- Караоке по слогам (YRC), по словам (Enhanced LRC) и по строкам
- Ручной выбор текста, если автоподбор промахнулся

**Интерфейс**
- Цвета интерфейса подстраиваются под обложку трека
- Отдельные раскладки для телефона, планшета и складного телефона, десктопа
- На Windows — своя строка заголовка и боковая панель с текстом и очередью

## 📦 Установка

Готовые сборки публикуются на странице [Releases](https://github.com/OrionZ43/protogenix/releases).

| Платформа | Требования | Что скачать |
|---|---|---|
| Android | Android 7.0 и новее | `.apk` |
| Windows | Windows 10 / 11, x64 | установщик `.exe` |
| Linux | собирается, но пока не тестировался | — |

<details>
<summary><b>Android: разрешение на установку</b></summary>

<br>

Приложение ставится не из магазина, поэтому Android попросит разрешить установку для браузера или файлового менеджера, через который вы открыли APK. Это обычный шаг, разрешение можно выключить обратно после установки.

</details>

<details>
<summary><b>Windows: предупреждение SmartScreen</b></summary>

<br>

Установщик пока не подписан сертификатом, поэтому при первом запуске Windows может показать окно «Система Windows защитила ваш компьютер». Нажмите «Подробнее» → «Выполнить в любом случае». Установка идёт в профиль пользователя и не требует прав администратора.

</details>

## 🛠 Сборка из исходников

Понадобится [Flutter](https://docs.flutter.dev/get-started/install) (stable, проект собирается на 3.44). Для Android — Android SDK, для Windows — Visual Studio 2022 с компонентом «Разработка классических приложений на C++».

```bash
git clone https://github.com/OrionZ43/protogenix.git
cd protogenix
flutter pub get
flutter run -d windows        # или: flutter run -d android
```

Релизные сборки:

```bash
flutter build apk --release
flutter build windows --release
```

## 🧩 Технологии

[Flutter](https://flutter.dev) · [Riverpod](https://riverpod.dev) · [just_audio](https://pub.dev/packages/just_audio) + [audio_service](https://pub.dev/packages/audio_service) · [media_kit](https://github.com/media-kit/media-kit) (звук на Windows) · [sqflite](https://pub.dev/packages/sqflite) · [youtube_explode_dart](https://pub.dev/packages/youtube_explode_dart)

## 🙏 Благодарности

- [LRCLIB](https://lrclib.net) — открытая база синхронизированных текстов
- NetEase Cloud Music — тексты с разметкой по слогам
- Авторам открытых библиотек, на которых держится проект

## ⚖️ Дисклеймер

Protogenix — независимый проект, не связанный с YouTube, Google, Spotify, Яндексом, SoundCloud или NetEase. Приложение предназначено для личного использования: соблюдайте авторские права и условия сервисов, из которых вы получаете музыку.

---

<div align="center">

Сделано с ❤ в **[Z43 Studios](https://z43-studios.vercel.app/)** · [Telegram](https://t.me/Orion_Z43)

</div>

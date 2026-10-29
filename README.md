<div align="center">

```
 _  _  ____                      
| \| |/ ___|_ __ ___  _   _ ___ 
| .` | |   | '_ ` _ \| | | / __|
| |\ | |___| | | | | | |_| \__ \
|_| \_|\____|_| |_| |_|\__,_|___/
  CYBERPUNK CROSS-PLATFORM AUDIO ENGINE
```

# NCmus // Cyberpunk Cross-Platform Audio Engine

> Next-generation low-latency audio core, deep hardware isolation, floating overlays, and neural-buffered cyber acoustics.

[![Flutter](https://img.shields.io/badge/Flutter-3.x%2B-%2302569B?style=for-the-badge&logo=flutter&logoColor=white)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.0%2B-%230175C2?style=for-the-badge&logo=dart&logoColor=white)](https://dart.dev)
[![Windows](https://img.shields.io/badge/Windows-10%20%2F%2011%20x64-%230078D6?style=for-the-badge&logo=windows&logoColor=white)](#supported-os)
[![Android](https://img.shields.io/badge/Android-API%2026%2B-%233DDC84?style=for-the-badge&logo=android&logoColor=black)](#supported-os)
[![iOS](https://img.shields.io/badge/iOS-14%2B%20Sideload-%23000000?style=for-the-badge&logo=apple&logoColor=white)](#supported-os)
[![CI/CD Release](https://img.shields.io/badge/CI%2FCD-GitHub%20Actions-%2300F0FF?style=for-the-badge&logo=githubactions&logoColor=black)](#cicd-matrix)
[![License](https://img.shields.io/badge/License-MIT-%23FF0055?style=for-the-badge)](LICENSE)

</div>

---

## ⚡ Архитектурные особенности (Core Architecture)

NCmus спроектирован с упором на бескомпромиссную производительность, глубокую изоляцию нативных платформ и киберпанк-эстетику интерфейса:

- 🧬 **Hybrid Core Architecture**
  Абсолютная платформенная изоляция:
  - **Windows**: низкоуровневые вызовы через `Win32 FFI`, аппаратные прозрачные GDI-оверлеи и интеграция с системным микшером.
  - **Mobile (Android & iOS)**: чистый нативный playback без оверхеда, поддержка фонового сервиса (`AudioService` / `AudioSession`), перехват медиа-нотификаций и аппаратных кнопок гарнитуры.

- 🌊 **NC-Wave Engine**
  Интеллектуальный аудиоплеер с динамическим предсказанием следующего трека: упреждающая буферизация, адаптивный оффлайн-кэш и бесшовный Gapless-переход между треками.

- 🔮 **Cyber Orb**
  Режим парящей неоновой сферы Windows поверх всех окон (`Always on Top`). Интерактивное управление жестами, HUD-эквалайзер и мгновенный доступ к трек-контролю прямо во время гейминга или кодинга.

- 💾 **Local-First SQLite**
  Ультрабыстрая локальная индексация вашей медиатеки. Высокопроизводительные транзакции, моментальный полнотекстовый поиск по трекам, альбомам и метаданным без задержек и сетевых лагов.

- 🎙️ **LRCLIB Sync**
  Синхронные караоке-субтитры в реальном времени. Автоматический парсинг таймингов миллисекундной точности и динамическая неоновая подсветка текущих строк.

- 🎮 **Discord Rich Presence**
  Прямая интеграция с Discord IPC. Отображение активного трека, исполнителя, таймкодов прогресса и кастомных обложек в вашем профиле Discord.

---

## 🖥️ Поддерживаемые ОС

| Платформа | Архитектура / Версия | Метод распространения | Статус |
|:---|:---|:---|:---:|
| **Windows** | Windows 10/11 (x64) | Standalone Portable ZIP / Installer | ![Ready](https://img.shields.io/badge/READY-00FF66?style=flat-square) |
| **Android** | API 26+ (Android 8.0 - 16) | Universal APK (ARM64 / x86_64) | ![Ready](https://img.shields.io/badge/READY-00FF66?style=flat-square) |
| **iOS** | iOS 14+ | Unsigned IPA (AltStore, SideStore, TrollStore) | ![Sideload](https://img.shields.io/badge/SIDELOAD-00F0FF?style=flat-square) |

---

## 🛠️ Инструкция разработчика (Developer Guide)

### Требования к окружению (Prerequisites)
- [Flutter SDK](https://flutter.dev/docs/get-started/install) (`>= 3.0.0`, channel `stable`)
- [Dart SDK](https://dart.dev/get-dart) (`>= 3.0.0 < 4.0.0`)
- **Windows Build**: Visual Studio 2022 с компонентом *"Разработка классических приложений на C++"*
- **Android Build**: Android Studio / Android SDK (Platform-tools, Build-tools 34+), JDK 17

---

### Сборка под Windows (x64)

1. Клонируйте репозиторий:
   ```powershell
   git clone https://github.com/Alexbog141/NCmus.git
   cd NCmus
   ```

2. Установите зависимости:
   ```powershell
   flutter pub get
   ```

3. Запустите в режиме разработки:
   ```powershell
   flutter run -d windows
   ```

4. Сборка релизного бинарника:
   ```powershell
   flutter build windows --release
   ```
   *Собранный исполняемый файл и зависимости будут доступны в директории:*  
   `build\windows\x64\runner\Release\`

---

### Сборка под Android

1. Проверьте готовность Android Toolchain:
   ```bash
   flutter doctor --android-licenses
   ```

2. Соберите релизный APK:
   ```bash
   flutter build apk --release
   ```
   *Готовый универсальный APK располагается по пути:*  
   `build/app/outputs/flutter-apk/app-release.apk`

---

### Сборка под iOS (Unsigned IPA для Sideload)

```bash
flutter build ios --no-codesign --release
mkdir -p Payload
cp -r build/ios/iphoneos/Runner.app Payload/
zip -r NCmus-iOS-unsigned.ipa Payload
```

---

## 🚀 CI/CD Matrix & Automated Builds

Каждый тег версии вида `v*.*.*` автоматически триггерит мультиплатформенный конвейер в **GitHub Actions**:
- 🪟 **Windows x64 Release ZIP** компилируется на `windows-latest`
- 🤖 **Android Release APK** собирается на `ubuntu-latest` с JDK 17
- 🍏 **iOS Unsigned IPA** пакуется на `macos-latest` для установки через AltStore/SideStore
- 📦 **GitHub Release** автоматически агрегирует все артефакты и генерирует Release Notes

---

## 📜 Лицензия

Распространяется под лицензией **MIT**. Подробности в файле [LICENSE](LICENSE).

<div align="center">
<b>CYBERNETIC SOUND EXPERIENCE // NCMUS</b>
</div>

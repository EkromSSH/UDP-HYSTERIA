# UDP HYSTERIA — Android App

**Hysteria + SSH WebSocket VPN Client** — built with Flutter & Kotlin

[![License: MIT](https://img.shields.io/badge/License-MIT-purple.svg)](LICENSE)
![Platform: Android](https://img.shields.io/badge/Platform-Android-brightgreen)

---

## 🔥 Features

### 🌐 Protocol Support
| Protocol | Description | Status |
|----------|-------------|--------|
| **Hysteria** | UDP-based fast proxy (QUIC) using Hysteria 2 | ✅ Core ready |
| **SSH WebSocket** | SSH tunneling over WebSocket (ws-ssh.py) | ✅ Core ready |

### 📱 App Features
- **Branded UI** — Purple theme, EkromSSH identity
- **Server Management** — Add/edit/delete multiple server configs
- **Connection Control** — One-tap connect/disconnect
- **Live Traffic Stats** — Upload/download speed & total
- **Connection Timer** — Elapsed time display
- **Auto Connect** — Resume last server on app start
- **Start on Boot** — Auto-connect after device reboot
- **Config Export/Import** — JSON file & clipboard sharing
- **Persistent Notification** — VPN status with quick disconnect
- **Dark Theme** — Full dark mode interface

### 🛡️ Security
- Android VpnService integration
- Foreground service with persistent notification
- No logs stored on device
- Config data encrypted at rest (SharedPreferences)

---

## 📱 Screenshots

| Home | Server List | Add Server | Settings |
|------|------------|------------|----------|
| Connection status & control | Saved servers | Add Hysteria/SSH WS | App settings |

---

## 🏗️ Architecture

```
ekromssh-app/
├── lib/                          # Flutter UI (Dart)
│   ├── main.dart                 # App entry + navigation
│   ├── theme/
│   │   └── app_theme.dart        # Purple EkromSSH theme
│   ├── models/
│   │   ├── server_config.dart    # Server model + JSON
│   │   └── connection_info.dart  # Connection state model
│   ├── providers/
│   │   └── connection_provider.dart # State management
│   ├── screens/
│   │   ├── home_screen.dart      # Main connection screen
│   │   ├── server_list_screen.dart # Server list
│   │   ├── add_server_screen.dart  # Add/edit form
│   │   └── settings_screen.dart    # Settings
│   ├── services/
│   │   ├── vpn_engine.dart       # Platform channel to native
│   │   ├── storage_service.dart  # Local storage
│   │   └── config_export_import.dart # Config file ops
│   └── widgets/
│       └── app_widgets.dart      # Reusable UI components
├── android/
│   └── app/src/main/kotlin/com/ekromssh/app/
│       ├── MainActivity.kt       # Flutter plugin channel
│       ├── EkromVpnService.kt    # VpnService implementation
│       └── BootReceiver.kt       # Auto-start on boot
└── android/app/src/main/
    ├── AndroidManifest.xml       # Permissions + service
    └── res/                      # Resources (colors, themes)
```

---

## 🔧 Build Instructions

### Prerequisites
- **Flutter SDK** `>=3.0.0` ([install guide](https://flutter.dev/docs/get-started/install))
- **Android Studio** (or IntelliJ IDEA with Android plugin)
- **Android SDK** (API 34+)
- Java 17+

### Clone & Build

```bash
# Clone the project
git clone <your-repo>/ekromssh-app.git
cd ekromssh-app

# Get Flutter dependencies
flutter pub get

# Check setup
flutter doctor

# Build APK
flutter build apk --release

# Or build App Bundle (for Play Store)
flutter build appbundle --release
```

The APK will be at: `build/app/outputs/flutter-apk/app-release.apk`

### Build from Source (no Flutter)
If you have Android Studio:
1. Open the `android/` folder as a project
2. Wait for Gradle sync
3. Build → Build APK(s)

---

## 🚀 Getting Started (after install)

1. **Open the app** — Tap the EkromSSH icon
2. **Add a server** — Go to Servers tab → tap ➕
3. **Choose protocol:**
   - **Hysteria** — Enter host, port (default 36712), password, ALPN
   - **SSH WS** — Enter host, SSH port, username, password, WS port
4. **Connect** — Tap server name or go to Home → tap center button
5. **Enjoy secure tunnel!**

---

## 📝 Configuration Reference

### Hysteria Config
| Field | Default | Description |
|-------|---------|-------------|
| Host | — | Server IP or domain |
| Port | 36712 | Hysteria UDP port |
| Password | — | Authentication password |
| Obfs Password | — | Salamander obfuscation |
| ALPN | h3 | Protocol negotiation |
| Upload Mbps | 100 | Bandwidth limit |
| Download Mbps | 100 | Bandwidth limit |

### SSH WS Config
| Field | Default | Description |
|-------|---------|-------------|
| Host | — | Server IP or domain |
| SSH Port | 22 | SSH server port |
| Username | root | SSH login username |
| Password | — | SSH login password |
| WS Port | 8080 | WebSocket proxy port |
| WS Path | / | WebSocket endpoint |

---

## 🧪 Testing

```bash
# Run Flutter tests
flutter test

# Run Android unit tests
cd android
./gradlew test
```

---

## 🛣️ Roadmap

- [x] Core UI & navigation
- [x] Hysteria configuration & proxy tunnel
- [x] SSH WebSocket configuration & proxy tunnel
- [x] Server management (CRUD)
- [x] Config export/import
- [ ] QR Code scanner for config
- [ ] Real Hysteria Go bindings (gomobile)
- [ ] Real SSH WS via JSch + OkHttp
- [ ] Traffic speed graph
- [ ] VPN split tunneling (by-app)
- [ ] iOS version (Flutter cross-platform)
- [ ] Auto-update check
- [ ] Material You dynamic theming

---

## 📄 License

MIT License — see [LICENSE](LICENSE) for details.

---

## 🙏 Credits

- [Hysteria](https://github.com/apernet/hysteria) — Powerful UDP proxy
- [JSch](http://www.jcraft.com/jsch/) — SSH Java library
- [OkHttp](https://square.github.io/okhttp/) — HTTP/WebSocket client
- [Flutter](https://flutter.dev) — UI framework
- **EkromSSH** — Thai VPN provider 🇹🇭

---

<div align="center">
  <sub>Built with ❤️ for EkromSSH users</sub>
</div>

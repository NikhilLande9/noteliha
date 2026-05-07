# NoteLiha: Notes you actually own

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Platform](https://img.shields.io/badge/platform-Android%20%7C%20Web-brightgreen)](https://noteliha.navkon.com)
[![Play Store](https://img.shields.io/badge/Get_it_on-Google_Play-414141?logo=googleplay)](https://play.google.com/store/apps/details?id=com.navkon.noteliha)

**Privacy-first note-taking without subscription fees or cloud lock-in.**

Most note-taking apps are built around one idea: collect user data on central servers. NoteLiha is built differently.

- ✅ **No backend storing your notes** — your content never touches our servers
- ✅ **Your storage, your control** — sync via your own Google Drive (optional)
- ✅ **Zero subscription fees** — no ads, no premium tiers, no data monetization
- ✅ **Open source** — GPL v3. Audit it yourself

---

## 🚀 Try it now

| Platform | Availability |
|----------|-------------|
| **Android** | [Google Play](https://play.google.com/store/apps/details?id=com.navkon.noteliha) — install and go |
| **Web** | [noteliha.navkon.com](https://noteliha.navkon.com) — no install required |
| **Windows** | Coming soon (CI builds via GitHub Actions) |
| **iOS** | Web app works; native pending Apple ecosystem costs |

---

## ✨ Features

| Feature | How it works |
|---------|--------------|
| **Offline-first** | Notes live on your device. Sync only when you choose. |
| **End-to-end encryption** | Local encryption using your Master Password. We never see your key. |
| **Structured note types** | Checklists, meal plans, recipes, itineraries — not just plain text |
| **Google Drive sync (optional)** | Your data, your cloud account. No hidden server. |
| **No account required** | No sign-up, no password reset (by design), no tracking |
| **Minimal metadata only** | Device info & version for support. [Full privacy policy](https://noteliha.navkon.com/PRIVACY_POLICY.html) |

---

## 🔒 Privacy promise

> "If our systems are compromised, there is no centrally stored readable note content to hand over."

- Your password is **never stored or transmitted**
- We **cannot** reset your password — that's a feature, not a bug
- Your notes stay on **your device or your Google Drive**
- Support metadata (email, device, version) is stored in Google Firestore — **never note content**

[Read the complete privacy policy →](https://noteliha.navkon.com/PRIVACY_POLICY.html)

---

## 🛠️ For developers

### Build from source

NoteLiha is built with [Flutter](https://flutter.dev). The same codebase targets Android, Web, and (soon) Windows.

```bash
# Clone the repository
git clone https://github.com/NikhilLande9/noteliha.git
cd noteliha

# Get dependencies
flutter pub get

# Run on Android
flutter run

# Run as web app
flutter run -d chrome

# Build for Android
flutter build apk

# Build for web
flutter build web

# Build for Windows (requires Visual Studio 2022 with C++ workload)
flutter build windows
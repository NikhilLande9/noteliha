# noteliha – Documentation Package

**Application Version:** 1.0.0
**Developer:** Nikhil Lande
**Organization:** Navkon Labs
**Location:** Kharghar, Maharashtra, India
**Last Updated:** March 2026

---

## Overview

This repository contains the documentation and resources required to publish **noteliha**, a privacy-focused Flutter note-taking application.

The documentation package includes:

• Legal documents required for app stores
• App store listing descriptions
• Publishing checklist and submission guide

These documents support publishing the application on **Google Play Store** and **Apple App Store**.

---

## Package Contents

### Core Application Files

**main.dart**
Main Flutter application file containing note models, UI implementation, local storage logic, Google Drive backup integration, and search functionality.

**pubspec.yaml**
Flutter dependency configuration including app metadata, package dependencies, and version information.

---

### Legal Documentation

**PRIVACY_POLICY.html**
Privacy policy describing what information the app accesses, where user data is stored, how optional Google Drive backup works, how users can delete their data, and contact information for privacy requests.

**TERMS_OF_SERVICE.html**
Terms governing use of the application including usage license, intellectual property rights, limitations of liability, acceptable use, and dispute resolution.

---

### App Store Listing Documents

**GOOGLE_PLAY_STORE_LISTING.md**
All text required for Google Play Store submission including app description, feature highlights, permissions explanation, keywords, reviewer testing instructions, and release notes.

**APPLE_APP_STORE_LISTING.md**
Listing text formatted for Apple App Store including description, keyword fields, screenshot descriptions, and reviewer instructions.

---

### Publishing Guide

**PUBLISHING_CHECKLIST.md**
Step-by-step checklist covering pre-submission verification, asset preparation, Play Store submission steps, App Store submission steps, and post-launch monitoring.

---

## Quick Start Guide

### Step 1 – Review Legal Documents

Before publishing:

• Review **PRIVACY_POLICY.html**
• Review **TERMS_OF_SERVICE.html**
• Verify developer contact information is correct

---

### Step 2 – Prepare App Store Metadata

Use **GOOGLE_PLAY_STORE_LISTING.md** and **APPLE_APP_STORE_LISTING.md** to fill out store listing fields.

You will also need to prepare:

• App icon (512×512 for Play Store)
• Screenshots for all required screen sizes
• Feature graphic (Google Play, 1024×500)

---

### Step 3 – Build the Application

#### Android

```
flutter build appbundle --release
```

Output: `build/app/outputs/bundle/release/app-release.aab`

---

#### iOS

```
flutter build ios --release
```

Requires an Apple Developer account and a macOS build environment.

---

### Step 4 – Submit to App Stores

#### Google Play

1. Create Play Console account
2. Create new application
3. Upload App Bundle
4. Complete store listing
5. Submit for review (typical review time: 1–3 days)

#### Apple App Store

1. Create Apple Developer account
2. Configure App Store Connect entry
3. Upload build through Xcode
4. Complete listing details
5. Submit for review (typical review time: 1–2 days)

---

## Technology Stack

• Flutter / Dart
• Hive (local database)
• Google Sign-In
• Google Drive API (optional backup only)

---

## Data Storage Model

**Local Device Storage**
All notes, images, categories, and preferences are stored locally on the device.

**Optional Google Drive Backup**
When the user manually triggers backup, individual JSON files and image files are stored in a `.liha_notes_app` folder in the user's personal Google Drive account, accessible only through their Google account.

---

## Support

Email: navkon9@gmail.com
Developer: Nikhil Lande, Navkon Labs, Kharghar, Maharashtra, India

---

## License

All code and documentation in this repository are provided for the development and distribution of the **noteliha** application.

© Nikhil Lande – Navkon Labs
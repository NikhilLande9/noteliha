# noteliha – Publish Documentation Package

**Application Version:** 1.0.0
**Developer:** Nikhil Lande
**Organization:** Navkon Labs
**Location:** Kharghar, Maharashtra, India
**Last Updated:** March 2026

---

# Overview

This repository contains the documentation and resources required to publish **noteliha**, a privacy-focused Flutter note-taking application.

The documentation package provides:

• Legal documents required for app stores
• App store listing descriptions
• Submission guides
• Technical documentation for the application
• Publishing checklists

These documents help streamline the process of publishing the application on **Google Play Store** and **Apple App Store**.

---

# Package Contents

## Core Application Files

**main_refactored_complete.dart**

Main Flutter application file containing:

• note models
• UI implementation
• local storage logic
• Google Drive backup integration
• search functionality

**pubspec.yaml**

Flutter dependency configuration including:

• app metadata
• package dependencies
• version information

---

# Legal Documentation

## PRIVACY_POLICY.md

Privacy policy describing:

• what information the app accesses
• where user data is stored
• how optional Google Drive backup works
• how users can delete their data
• contact information for privacy requests

---

## TERMS_OF_SERVICE.md

Terms governing the use of the application including:

• usage license
• intellectual property rights
• limitations of liability
• acceptable use conditions
• dispute resolution terms

---

# App Store Listing Documents

## GOOGLE_PLAY_STORE_LISTING.md

Contains all text required for Google Play Store submission:

• app description
• feature highlights
• permissions explanation
• keywords
• reviewer testing instructions
• release notes

---

## APPLE_APP_STORE_LISTING.md

Contains listing text formatted for Apple App Store:

• description optimized for iOS listing format
• keyword fields
• screenshot descriptions
• reviewer instructions

---

# Implementation Documentation

## MAIN_IMPLEMENTATION_GUIDE.md

Technical documentation describing:

• application architecture
• data storage structure
• Google Drive backup logic
• search implementation
• performance considerations

---

## PUBLISHING_CHECKLIST.md

Step-by-step checklist covering:

• pre-submission verification
• asset preparation
• Play Store submission steps
• App Store submission steps
• post-launch monitoring

---

# Reference Documents

## FINAL_SUMMARY.txt

High-level overview of the application including:

• features
• architecture summary
• technology stack
• development notes

---

## APP_NAME_UPDATE.txt

Documentation of locations where the application name **noteliha** is referenced in:

• code
• metadata
• build configuration

---

# Quick Start Guide

## Step 1 – Review Legal Documents

Before publishing:

• Review **PRIVACY_POLICY.md**
• Review **TERMS_OF_SERVICE.md**
• Verify that developer contact information is correct

---

## Step 2 – Prepare App Store Metadata

Use:

• GOOGLE_PLAY_STORE_LISTING.md
• APPLE_APP_STORE_LISTING.md

to fill out store listing fields.

You will also need to prepare:

• app icon (512×512)
• screenshots
• feature graphic (Google Play)

---

## Step 3 – Build the Application

### Android

```
flutter build appbundle --release
```

Output location:

```
build/app/outputs/bundle/release/app-release.aab
```

---

### iOS

```
flutter build ios --release
```

Requires an Apple Developer account and a macOS build environment.

---

## Step 4 – Submit to App Stores

### Google Play

1. Create Play Console account
2. Create new application
3. Upload App Bundle
4. Complete store listing
5. Submit for review

Typical review time: **1–3 days**

---

### Apple App Store

1. Create Apple Developer account
2. Configure App Store Connect entry
3. Upload build through Xcode
4. Complete listing details
5. Submit for review

Typical review time: **1–2 days**

---

# Recommended Submission Workflow

1. Finalize code
2. Verify legal documents
3. Prepare store listing metadata
4. Generate release build
5. Submit to Google Play
6. Submit to Apple App Store
7. Monitor review feedback
8. Address issues if necessary

---

# Technology Stack

The application uses:

• Flutter
• Dart
• Hive local database
• Google Sign-In
• Google Drive API (optional backup)

---

# Data Storage Model

User data is stored in two locations:

**Local Device Storage**

• notes
• images
• categories
• user preferences

**Optional Google Drive Backup**

• individual JSON files stored in a `.noteliha` folder
• accessible only through the user's Google account

---

# Post-Launch Monitoring

After release it is recommended to monitor:

• crash reports
• user feedback
• ratings and reviews
• feature requests

Bug fixes and improvements should be released through version updates.

---

# Support

For support or bug reports:

Email
[navkon9@gmail.com](mailto:navkon9@gmail.com)

Developer
Nikhil Lande

Organization
Navkon Labs

Location
Kharghar, Maharashtra, India

---

# Document Checklist

Repository documentation includes:

• Source code
• Privacy policy
• Terms of service
• Google Play listing document
• Apple App Store listing document
• Publishing checklist
• Technical documentation
• Summary files

---

# Version History

Version 1.0.0
Initial release documentation package.

---

# License

All code and documentation in this repository are provided for the development and distribution of the **noteliha** application.

© Nikhil Lande – Navkon Labs

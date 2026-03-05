# noteliha – Publishing Checklist & Submission Guide

**Status:** Ready for Review
**Version:** 1.0.0
**Date:** March 2026

---

## Pre-Submission Checklist

### 1. Legal Documents
- [ ] Privacy Policy reviewed and accurate
- [ ] Terms of Service reviewed and accurate
- [ ] Developer contact information verified
- [ ] Folder name `.liha_notes_app` consistent across all documents
- [ ] Privacy policy URL live and accessible

### 2. Code Quality
- [ ] All features tested on device
- [ ] No crashes during testing
- [ ] Offline functionality verified
- [ ] Backup and restore functionality verified
- [ ] Search functionality verified
- [ ] No hardcoded API keys
- [ ] No debug logging in production build
- [ ] Error handling in place for Drive operations

### 3. Security
- [ ] OAuth properly implemented
- [ ] No plaintext passwords or tokens stored
- [ ] HTTPS enforced for all API calls
- [ ] Exponential backoff implemented for Drive retries

### 4. Privacy
- [ ] Minimal data collection confirmed
- [ ] No unnecessary permissions requested
- [ ] No tracking or analytics SDKs included
- [ ] No third-party SDKs beyond Google
- [ ] Data deletion mechanism working (recycle bin + Drive folder)

### 5. Functionality
- [ ] All 5 note types working (normal, checklist, itinerary, mealPlan, recipe)
- [ ] All 6 color themes working (Default, Sunset, Orange, Forest, Lavender, Rose)
- [ ] Create, edit, delete notes
- [ ] Soft delete and restore from recycle bin
- [ ] Hard delete (empty recycle bin)
- [ ] Search across notes
- [ ] Pin notes
- [ ] Category organization
- [ ] Image attachment
- [ ] Google Drive upload (manual)
- [ ] Google Drive restore (manual)
- [ ] Conflict detection and resolution
- [ ] Multi-account support on same device
- [ ] Offline functionality

### 6. User Interface
- [ ] Works on all target screen sizes
- [ ] Portrait and landscape mode
- [ ] Dark mode and light mode
- [ ] Readable text and clear icons
- [ ] No broken layouts

### 7. Testing
- [ ] Tested on Android (latest version)
- [ ] Tested on small screen device
- [ ] Tested on large screen device
- [ ] Tested with no Google account
- [ ] Tested with Google account signed in
- [ ] Tested offline
- [ ] Tested with slow internet
- [ ] Tested sign-in with two different Google accounts on same device

### 8. Documentation
- [ ] Privacy Policy complete
- [ ] Terms of Service complete
- [ ] Release notes prepared
- [ ] Screenshots prepared (all required sizes)
- [ ] App description ready
- [ ] Keywords selected

### 9. App Store Compliance
- [ ] Content rating appropriate (Everyone / 4+)
- [ ] No prohibited content
- [ ] Metadata accurate and matches actual app behaviour
- [ ] Screenshots represent actual app UI
- [ ] Bundle ID unique
- [ ] Version number correct (1.0.0)

### 10. Release Preparation
- [ ] Release build generated
- [ ] Signing certificates current
- [ ] App icons generated (all required sizes)
- [ ] Screenshots captured (all required sizes)
- [ ] Release notes prepared

---

## Google Play Store Submission Steps

### Step 1 – Prepare Build
```bash
# Build App Bundle (recommended for Play Store)
flutter build appbundle --release

# Output: build/app/outputs/bundle/release/app-release.aab
```

### Step 2 – Create Play Console Account
1. Go to Google Play Console
2. Create developer account or sign in
3. Pay one-time $25 registration fee
4. Accept terms and conditions

### Step 3 – Create New App
1. Click "Create app"
2. Enter app name: noteliha
3. Select type: App
4. Default language: English
5. Complete required declarations

### Step 4 – Store Listing
- [ ] Title: noteliha
- [ ] Short description (from GOOGLE_PLAY_STORE_LISTING.md)
- [ ] Full description (from GOOGLE_PLAY_STORE_LISTING.md)
- [ ] Category: Productivity
- [ ] Contact email
- [ ] Privacy policy URL
- [ ] 2–8 screenshots (1080×1920 recommended)
- [ ] Feature graphic (1024×500)
- [ ] App icon (512×512)

### Step 5 – App Content
- [ ] Content rating questionnaire completed
- [ ] Target audience declared (13+)
- [ ] Privacy policy URL entered

### Step 6 – Submit Build
1. Go to Release → Production
2. Create new release
3. Upload app bundle
4. Add release notes
5. Submit for review

---

## Apple App Store Submission Steps

### Step 1 – Prepare Build
```bash
flutter build ios --release
```

### Step 2 – Apple Developer Account
1. Enroll in Apple Developer Program ($99/year)
2. Accept license agreements

### Step 3 – App Identifier
1. Create new identifier in Certificates, Identifiers & Profiles
2. Bundle ID: com.navkonlabs.noteliha (or your chosen ID)
3. App name: noteliha

### Step 4 – Certificates and Profiles
1. Create iOS Distribution Certificate
2. Create App Store distribution profile
3. Update project signing settings in Xcode

### Step 5 – App Store Connect
1. Go to App Store Connect → My Apps → New App
2. Name: noteliha
3. Bundle ID: (your bundle ID)
4. SKU: noteliha-001

### Step 6 – App Information
- [ ] Category: Productivity
- [ ] Privacy policy URL
- [ ] Support URL
- [ ] Description (from APPLE_APP_STORE_LISTING.md)
- [ ] Keywords
- [ ] Screenshots (5.5-inch, 6.5-inch, iPad Pro 12.9-inch)

### Step 7 – App Privacy
- [ ] Complete app privacy questionnaire
- [ ] Data types: Google account info (name, email) when Drive backup enabled
- [ ] Data not linked to identity beyond authentication

### Step 8 – Submit
1. Upload build via Xcode
2. Attach build in App Store Connect
3. Complete all required fields
4. Submit for review

---

## Post-Launch Monitoring

### What to Monitor
- [ ] Crash reports
- [ ] User reviews and ratings
- [ ] User feedback and bug reports
- [ ] Drive sync error reports

### Review Responses
- [ ] Respond to user reviews
- [ ] Address critical issues in next update
- [ ] Track common complaints for roadmap

---

## Regulatory Notes

These items describe the app's design intent. Formal legal compliance verification should be done by a qualified professional before submission if required.

| Regulation | App Design |
|---|---|
| GDPR | Data stored locally or in user's own Drive; user can delete at any time |
| CCPA | No sale of personal information; user controls all data |
| COPPA | App not directed at children under 13; noted in Privacy Policy |
| Google Play Policies | drive.file scope only; no prohibited content |
| Apple App Store Guidelines | Permissions requested only when needed; no misleading claims |

---

## Version History

v1.0.0 – March 2026 – Initial checklist for noteliha launch
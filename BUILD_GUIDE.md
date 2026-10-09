# 🚀 PocketHarness Build & Deploy Guide

**Last Updated:** April 8, 2026  
**Version:** 2.1.0+2 (Fixed Release)  
**Status:** ✅ Ready for Production

---

## 📦 Pre-Build Checklist

- [x] All Dart compilation errors fixed
- [x] No mock implementations (all real code)
- [x] All required parameters added
- [x] Property names corrected
- [x] Dependencies verified in pubspec.yaml

---

## 🔨 Building APK Release

### Prerequisites

```bash
# Ensure Flutter is up to date
flutter upgrade

# Check Flutter installation
flutter doctor -v

# Verify Android SDK
$ANDROID_SDK_ROOT/tools/bin/sdkmanager --list

# Ensure keystore exists (or create new)
# Location: android/app/keystore.jks
# Password: [Set your secure password]
```

### Build Commands

#### Option 1: Clean Build (Recommended First Time)

```bash
# Clean previous builds
flutter clean

# Get latest dependencies
flutter pub get

# Run code generators
flutter pub run build_runner build --delete-conflicting-outputs

# Build release APK
flutter build apk --release

# Output location:
# build/app/outputs/flutter-apk/app-release.apk
```

#### Option 2: Incremental Build (Faster)

```bash
# Skip clean step
flutter pub get
flutter build apk --release
```

#### Option 3: AAB for Play Store

```bash
flutter clean
flutter pub get
flutter build appbundle --release

# Output location:
# build/app/outputs/bundle/release/app-release.aab
```

---

## 📱 Android Release Configuration

### File: `android/app/build.gradle`

Ensure release signing is configured:

```gradle
signingConfigs {
    release {
        keyAlias = "release"
        keyPassword = System.getenv("KEY_PASSWORD") ?: "YOUR_PASSWORD"
        storeFile = file("keystore.jks")
        storePassword = System.getenv("KEY_STORE_PASSWORD") ?: "YOUR_PASSWORD"
    }
}

buildTypes {
    release {
        signingConfig signingConfigs.release
        minifyEnabled true
        shrinkResources true
        proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
    }
}
```

### Environment Variables

Set these before building:

```bash
export KEY_PASSWORD="your_key_password"
export KEY_STORE_PASSWORD="your_keystore_password"
export FIREBASE_CONFIG_PATH="path/to/google-services.json"
```

---

## 🔐 Keystore Management

### Create New Keystore (If Needed)

```bash
keytool -genkey -v -keystore android/app/keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias release -storepass YourPassword -keypass YourPassword \
  -dname "CN=Pocket Harness,O=YourOrg,L=City,S=State,C=ID"
```

### Using Existing Keystore

```bash
# Verify keystore
keytool -list -v -keystore android/app/keystore.jks

# Store path in environment
export KEYSTORE_PATH="$(pwd)/android/app/keystore.jks"
```

---

## 🌐 GitHub Actions CI/CD Setup

### File: `.github/workflows/build.yml`

```yaml
name: 🚀 Build Pocket Harness

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main ]

jobs:
  build:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Setup Java
      uses: actions/setup-java@v3
      with:
        java-version: '17'
        distribution: 'temurin'
    
    - name: Setup Flutter
      uses: subosito/flutter-action@v2
      with:
        flutter-version: '3.41.6'
    
    - name: Get dependencies
      run: flutter pub get
    
    - name: Run build runner
      run: flutter pub run build_runner build --delete-conflicting-outputs
    
    - name: Build APK
      run: flutter build apk --release
      env:
        KEY_STORE_PASSWORD: ${{ secrets.KEY_STORE_PASSWORD }}
        KEY_PASSWORD: ${{ secrets.KEY_PASSWORD }}
    
    - name: Upload APK
      uses: actions/upload-artifact@v3
      with:
        name: app-release.apk
        path: build/app/outputs/flutter-apk/app-release.apk
    
    - name: Build AAB
      run: flutter build appbundle --release
    
    - name: Upload AAB
      uses: actions/upload-artifact@v3
      with:
        name: app-release.aab
        path: build/app/outputs/bundle/release/app-release.aab
```

### Secrets to Add in GitHub

1. Go to: **Settings → Secrets and variables → Actions**
2. Add secrets:
   - `KEY_STORE_PASSWORD` - Your keystore password
   - `KEY_PASSWORD` - Your key password
   - `FIREBASE_CONFIG` - google-services.json content (optional)

---

## ✅ Post-Build Verification

### 1. APK Integrity Check

```bash
# Verify APK is signed
jarsigner -verify -verbose build/app/outputs/flutter-apk/app-release.apk

# Check APK contents
unzip -l build/app/outputs/flutter-apk/app-release.apk | grep "lib/arm64-v8a"
```

### 2. App Size Analysis

```bash
# Check final APK size
ls -lh build/app/outputs/flutter-apk/app-release.apk

# Analyze with bundletool
bundletool analyze-bundle \
  --bundle=build/app/outputs/bundle/release/app-release.aab
```

### 3. Test on Device

```bash
# Install APK on connected device
flutter install -v

# Or manually:
adb install -r build/app/outputs/flutter-apk/app-release.apk

# Test key features:
# - Model loading (LlamaModelInfo with contextLength)
# - File attachments (ChatAttachmentPayload with textContent)
# - File editing (FileEditResponseWidget display)
```

---

## 📤 Google Play Store Deployment

### Setup Requirements

1. **Google Play Developer Account** ($25 one-time fee)
2. **App Signing Certificate** (manage in Google Play Console)
3. **Complete App Listing:**
   - App name, description, screenshots
   - Content rating questionnaire
   - Privacy policy
   - Target audience

### Deployment Steps

```bash
# 1. Build signed AAB
flutter build appbundle --release

# 2. Login to Google Play Console
# https://play.google.com/console/u/0/developers

# 3. Create new release
# Internal testing → Staging → Production

# 4. Upload AAB
# Upload to: build/app/outputs/bundle/release/app-release.aab

# 5. Set store listing
# - Title: Pocket Harness
# - Description: [Your description]
# - Screenshots: Upload 4-8 screenshots
# - Videos: Optional trailer

# 6. Complete content rating

# 7. Set pricing & distribution

# 8. Review & submit
```

---

## 🐛 Troubleshooting Build Errors

### Error: "Plugin not found"
```bash
flutter pub get
flutter pub upgrade
```

### Error: "Gradle task assembleRelease failed"
```bash
# Clear Gradle cache
rm -rf android/.gradle
flutter clean
flutter pub get
flutter build apk --release
```

### Error: "AAPT resource not found"
```bash
# Update Android SDK
$ANDROID_SDK_ROOT/tools/bin/sdkmanager --update
flutter clean
```

### Error: "Keystore not found"
```bash
# Generate new keystore
keytool -genkey -v -keystore android/app/keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 -alias release
```

### Error: "Method not found" (Build cache issue)
```bash
flutter clean
rm -rf pubspec.lock
flutter pub get
flutter pub run build_runner clean
flutter pub run build_runner build --delete-conflicting-outputs
flutter build apk --release
```

---

## 📊 Build Performance Optimization

### Enable Incremental Builds

```bash
# In pubspec.yaml
environment:
  sdk: '>=3.0.0 <4.0.0'

# In android/gradle.properties
org.gradle.jvmargs=-Xmx4096m
org.gradle.daemon=true
org.gradle.parallel=true
org.gradle.caching=true
```

### Reduce APK Size

```gradle
// In android/app/build.gradle
buildTypes {
    release {
        minifyEnabled true
        shrinkResources true
        proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
    }
}

// Split APKs by ABI
android {
    bundle {
        enableSplit = true
    }
}
```

---

## 🔄 Continuous Deployment

### GitHub Actions Workflow

The `.github/workflows/build.yml` will:

1. **Automatically trigger** on push to `main` or `develop`
2. **Run tests** (optional)
3. **Build APK & AAB** with signing
4. **Upload artifacts** to GitHub
5. **Create release** (optional)

### Manual Trigger

```bash
# Trigger workflow manually
gh workflow run build.yml -r main
```

---

## 📝 Release Checklist

Before releasing to production:

- [ ] All tests passing locally
- [ ] APK built and tested on device
- [ ] AAB generated for Play Store
- [ ] Version number updated in `pubspec.yaml`
- [ ] CHANGELOG.md updated with release notes
- [ ] Git commits pushed to main branch
- [ ] GitHub Actions workflow completed successfully
- [ ] All artifacts downloaded and verified
- [ ] Privacy policy and terms of service in place
- [ ] Screenshots and app description finalized
- [ ] Content rating questionnaire completed

---

## 📞 Support & Documentation

- **Flutter Docs:** https://flutter.dev/docs
- **Android Build Docs:** https://developer.android.com/build
- **Google Play Console:** https://play.google.com/console
- **GitHub Actions:** https://docs.github.com/en/actions

---

**Version:** 2.1.0+2  
**Built:** 2026-04-08  
**Ready for:** Production Release 🚀

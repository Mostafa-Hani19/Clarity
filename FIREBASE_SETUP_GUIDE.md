# Firebase API Key Error: Complete Fix Guide

## The Problem

You're seeing the error: "An internal error has occurred. [API key not valid. Please pass a valid API key]" in your Flutter app when trying to use Firebase Authentication.

## Root Causes & Solutions

### 1. Create a New Firebase Project

1. Go to the [Firebase Console](https://console.firebase.google.com/)
2. Click "Add project" and follow the setup instructions
3. Name your project (e.g., "Clarity")

### 2. Register Your Android App Correctly

1. In the Firebase console, click "Add app" and select Android
2. Enter the package name: `com.example.clarity` (IMPORTANT: This must match exactly)
3. For the app nickname, enter "Clarity"
4. Download the `google-services.json` file

### 3. Update Your Android Config Files

1. Place the downloaded `google-services.json` file in the `android/app/` directory, replacing any existing file
2. Make sure your `android/app/build.gradle.kts` has this configuration:
   ```kotlin
   plugins {
       id("com.android.application")
       // START: FlutterFire Configuration
       id("com.google.gms.google-services")
       // END: FlutterFire Configuration
       id("kotlin-android")
       id("dev.flutter.flutter-gradle-plugin")
   }

   android {
       namespace = "com.example.clarity"
       applicationId = "com.example.clarity"
       // Other config...
   }
   ```

### 4. Enable Email/Password Authentication

1. In the Firebase Console, go to Authentication → Sign-in methods
2. Enable "Email/Password" authentication
3. If using Google Sign-in, enable "Google" authentication as well

### 5. Add Your SHA-1 Certificate Fingerprint

The SHA-1 certificate fingerprint is required for Google Sign-in and other Firebase services.

#### For Windows:
```
cd %USERPROFILE%
cd .android
keytool -list -v -keystore debug.keystore -alias androiddebugkey -storepass android -keypass android
```

Copy the SHA-1 fingerprint and add it to your Firebase project:
1. Go to Firebase Console → Project Settings → Your Apps → Android App
2. Click "Add fingerprint" and paste your SHA-1 value

### 6. Fix Storage Bucket URLs

Firebase Storage bucket URLs in `firebase_options.dart` should follow this format:
- Use `projectid.appspot.com` instead of `projectid.firebasestorage.app`

### 7. Completely Clean and Rebuild Your App

```
flutter clean
flutter pub get
flutter run
```

### 8. Verify Configuration via FlutterFire CLI

For a more automated approach:

1. Install the FlutterFire CLI:
   ```
   dart pub global activate flutterfire_cli
   ```

2. Configure your app:
   ```
   flutterfire configure --project=your-project-id
   ```

This will automatically update your Firebase configuration files with the correct values.

## Common Issues

1. **Mismatched Package Names**: Ensure the package name in Firebase and your app match exactly
2. **Missing SHA-1**: Google Sign-in and other features require the SHA-1 fingerprint
3. **Incorrect Storage Bucket Format**: Should be `projectid.appspot.com` not `projectid.firebasestorage.app`
4. **Old Configuration Files**: Replace outdated files with new ones from Firebase
5. **Firebase Rules**: Check Authentication and Storage rules in Firebase Console 
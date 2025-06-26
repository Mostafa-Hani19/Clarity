# Clarity

A Flutter application with Firebase integration for authentication and data storage.



## 📸 صور من التطبيق

### الشاشة الرئيسية

![Home](https://github.com/Mostafa-Hani19/clarity/blob/master/assets/assets/1.jpg?raw=true)


![Settings](https://github.com/Mostafa-Hani19/clarity/blob/master/assets/assets/2.jpg?raw=true)

![Settings](https://github.com/Mostafa-Hani19/clarity/blob/master/assets/assets/3.jpg?raw=true)

![Settings](https://github.com/Mostafa-Hani19/clarity/blob/master/assets/assets/4.jpg?raw=true)
![Settings](https://github.com/Mostafa-Hani19/clarity/blob/master/assets/assets/5.jpg?raw=true)



## Firebase Setup Instructions

The app is currently displaying an "API key not valid" error because Firebase hasn't been properly set up. Follow these steps to fix it:

### 1. Create a Firebase Project

1. Go to the [Firebase Console](https://console.firebase.google.com/)
2. Click "Add project" and follow the setup instructions
3. Name your project (e.g., "Clarity")

### 2. Register Your App

#### For Android:

1. In the Firebase console, click "Add app" and select Android
2. Enter the package name: `com.example.clarity`
3. (Optional) Enter a nickname for your app
4. Register the app
5. Download the `google-services.json` file
6. Place the file in the `android/app/` directory of your Flutter project

#### For iOS (if needed):

1. In the Firebase console, click "Add app" and select iOS
2. Enter the bundle ID: `com.example.clarity`
3. Register the app
4. Download the `GoogleService-Info.plist` file
5. Place the file in the `ios/Runner/` directory of your Flutter project

### 3. Enable Authentication Methods

1. In the Firebase console, go to "Authentication" in the left sidebar
2. Click "Get started" 
3. Enable "Email/Password" authentication
4. Also enable "Google" sign-in if you want to use Google Sign-In

### 4. Update Firebase Options

After setting up Firebase, you need to update the Firebase options in your app:

1. Run the FlutterFire CLI to automatically configure your app:
   ```
   flutter pub global activate flutterfire_cli
   flutterfire configure --project=your-project-id
   ```

2. This will update your `firebase_options.dart` file with the correct values

### 5. Verify SHA-1 Certificate Fingerprint (for Google Sign-In)

For Google Sign-In to work on Android, you need to add your SHA-1 certificate fingerprint:

1. Get your debug SHA-1 by running:
   ```
   cd android
   ./gradlew signingReport
   ```
   
2. Look for the SHA-1 value under "Variant: debug"
3. In the Firebase console, go to Project settings > Your apps > Android app
4. Add the SHA-1 fingerprint under "SHA certificate fingerprints"

## Troubleshooting

If you're still seeing the "API key not valid" error after following these steps:

1. Make sure you've placed the `google-services.json` file in the correct location
2. Verify that the API keys in `firebase_options.dart` match those in your Firebase project
3. Ensure you're using the same package name in both Android and Firebase
4. Completely rebuild the app:
   ```
   flutter clean
   flutter pub get
   flutter run
   ```

For more information on Firebase setup with Flutter, see the [official documentation](https://firebase.google.com/docs/flutter/setup).

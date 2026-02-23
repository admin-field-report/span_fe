# Field Report

A Flutter application for creating and managing field reports. This application supports multiple platforms including Web, Android, iOS, and iPad.

## Platform Support

This application is fully cross-platform and works seamlessly on:
- **Web** (Chrome, Edge, Safari, Firefox)
- **Android** (phones and tablets)
- **iOS** (iPhone and iPad)

All core features, API calls, and UI layouts function correctly across all platforms.

## Getting Started

This project is a Flutter application with cross-platform support.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

# Pre-requestists
- Install Flutter SDK
- In terminal, execute commnad "flutter doctor" (checks your environment and displays missing dependencies (e.g., Android SDK, Visual Studio).)
- Install Android Studio (for Android emulator)

Alternative Setup (without Android Studio)
1) Install Flutter SDK
👉 
2) Install Android SDK manually (if needed)

3) Use VS Code (or other IDEs)
- Install the Flutter and Dart extensions.

4) Connect a real Android device
- Enable Developer Options + USB Debugging.
- Use flutter devices to detect it.

To Setup in macos
- Install Flutter SDK
- Install xcode

# Run Flutter App for web
- Check that web is enabled:
- Execute "flutter devices" in root of your project.
- It will show Chrome (web), Edge (web) etc.
- Now execute "flutter run -d chrome" and your app will be launched in Chrome.
- To make build for web execute "flutter build web", this will create web build inside folder build/web/...

# Run Flutter App for Android
- Make sure Android studio is installed
- Open Project in Android Stuido or VSCode.
- If inside Android Studio, you can choose simulator device to test/debug, so choose one from manager device.
- Then in terminal execute command "flutter run".
- It will launch our App in simulator and now you view and test app.
- You can also connect Physical Android Device with USB or Wirelessly and can test our app in Physical Device.

# Run Flutter App for Ios
- Make sure you are using macos.
- you can open project in xcode using command from terminal as 
    cd path/to/your/project
    open Runner.xcworkspace
- Choose device from xcode on which you want to test.
- Execute "flutter devices", it will show device with ID copy that the device ID and then execute flutter run ID.
- It will launch app on simulator and you can test App.
- You can also connect physical device to test/debug app.

# Command to copy web build to s3 bucket
- aws s3 cp ./build/web s3://dev-field-report-static/ --recursive

# to run the project
flutter run -d chrome

# make sure to add .env file
copy that from .env.example

# to get all dependencies
flutter pub get

## Building for Different Platforms

### Build for Web
```bash
flutter build web
```

### Build for Android
```bash
flutter build apk
# or for app bundle
flutter build appbundle
```

### Build for iOS
```bash
flutter build ios
```

## Platform-Specific Notes

### Android
- File sharing and storage permissions are automatically configured in `AndroidManifest.xml`
- The app uses `share_plus` for file sharing on mobile devices

### iOS/iPad
- File sharing is enabled in `Info.plist`
- The app supports all iPad orientations
- File access permissions are handled automatically by the Flutter plugins

### Web
- URL strategy is configured to use path-based routing (no hash in URLs)
- File downloads work through browser download mechanisms
- All web-specific optimizations are in place

## Dependencies

Key cross-platform packages used:
- `shared_preferences` - Cross-platform local storage
- `file_picker` - Cross-platform file picking
- `share_plus` - Cross-platform file sharing
- `path_provider` - Cross-platform file system access
- `go_router` - Cross-platform routing

## Troubleshooting

If you encounter platform-specific issues:
1. Ensure all dependencies are installed: `flutter pub get`
2. Clean the build: `flutter clean && flutter pub get`
3. For Android: Check that Android SDK is properly configured
4. For iOS: Ensure Xcode and CocoaPods are properly set up
5. For Web: Ensure you're using a modern browser with JavaScript enabled

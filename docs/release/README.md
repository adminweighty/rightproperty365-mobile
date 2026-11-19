# Releasing RightProperty365

This folder prepares a store release. Publishing is the owner's step. Nothing here uploads anything.

- [store-listing.md](store-listing.md): store text and the screenshot list.
- [data-safety-DRAFT.md](data-safety-DRAFT.md): draft answers for Google Play's Data safety form and Apple's App Privacy questions. They are for the owner to check and confirm.

## Version and build numbers

`pubspec.yaml` holds `version: <name>+<number>`, for example `1.0.0+1`.

- **Name** (`1.0.0`): what people see. Use `major.minor.patch`:
  - patch for fixes;
  - minor for new features;
  - major for a big change.
- **Number** (`+1`): a whole number that **must grow with every upload** to either store. Both stores refuse a number they have already seen. Use one counter for both platforms.

Pass the same values on the command line for each release, and keep `pubspec.yaml` in step after it ships:
- `--build-name` and `--build-number`;
- `--dart-define=APP_VERSION=<name>`, which the app reports to the API with its push registration.

## Android (Google Play)

### Once

1. Create an **upload key**. Keep it, and its passwords, outside the repository: for example in a password manager, plus a backup.

   ```bash
   keytool -genkeypair -keystore ~/rightproperty365-upload.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000
   ```

2. Copy `android/key.properties.example` to `android/key.properties` and fill it in.
   - On a build server, set `RP365_UPLOAD_KEYSTORE`, `RP365_UPLOAD_STORE_PASSWORD`, `RP365_UPLOAD_KEY_ALIAS` and `RP365_UPLOAD_KEY_PASSWORD` instead.
   - `key.properties`, `*.jks` and `*.keystore` are git-ignored.
3. Enrol in **Play App Signing** when creating the app in Play Console (`com.rightproperty365.rightproperty365`).
   - Google keeps the app signing key.
   - Put the **app signing key's SHA-256** (Play Console, App integrity) in the website's `/.well-known/assetlinks.json`. See the shared note `for-web-app-links.md`. Without it, App Links ask instead of opening the app.

### Each release

```bash
flutter build appbundle --release --build-name=1.0.0 --build-number=1 --dart-define=APP_VERSION=1.0.0 --dart-define=API_BASE_URL=https://api.rightproperty365.com --dart-define=WEB_BASE_URL=https://rightproperty365.com
```

Then upload `build/app/outputs/bundle/release/app-release.aab` to Play Console (internal testing first). Without an upload key, the build is signed with the debug key and Gradle warns: Play Console refuses such a build.

Check the API and web addresses against production before the first release. `API_BASE_URL` defaults to the Android emulator's development address.

## iOS (App Store)

This needs a Mac with Xcode, and the Apple Developer Program team that owns `com.rightproperty365.rightproperty365`.

1. In the developer account, give the App ID these capabilities:
   - **Push Notifications**;
   - **Associated Domains**. `ios/Runner/Runner.entitlements` already lists `applinks:rightproperty365.com`.
2. Upload an **APNs authentication key** to the Firebase project (push).
3. In Xcode, choose the team for the Runner target; automatic signing is fine.
4. Run `flutter build ipa --release --build-name=1.0.0 --build-number=1 --dart-define=APP_VERSION=1.0.0` with the same API and web defines, and upload with Transporter or Xcode's Organizer.
5. Put the **Team ID** in the website's `/.well-known/apple-app-site-association`.

The GitHub Actions job `.github/workflows/ios.yml` only proves that the app compiles for iOS, unsigned.

## Before submitting (owner)

- Store listing text, screenshots, the privacy policy URL and support contact (see `store-listing.md`).
- Data safety (Play) and App Privacy (Apple): confirm or correct the draft, then fill the forms.
- Content rating questionnaires (Play: IARC; Apple: age rating).
- A sign-in for the reviewers: Apple and Google need an account that can reach the features behind sign-in. It must not be a real customer's account.
- Production: no `AUTH_DEMO_CODE` and no `DEMO_SIGNING_CODE` in a store build.

# Automatic update settings

This build adds an Update settings screen.

Default settings:

- Check for updates automatically: ON
- Download automatically on Wi-Fi: ON

When the app opens it checks the latest GitHub Release. On Wi-Fi, a newer APK is downloaded automatically and the app then asks the user to install it. Android still requires installation confirmation.

For every future release:

1. Increase `version:` in `pubspec.yaml`.
2. Push the source to GitHub.
3. Create and push a matching version tag, for example `v1.3.0`.
4. Ensure the GitHub Release contains an `.apk` asset.
5. Sign every release with the same Android signing key.

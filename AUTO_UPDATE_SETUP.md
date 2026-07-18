# GitHub auto-update setup

The app checks this public repository on startup:

`gokulabuilderssolutions/gokula-inventory`

It reads the latest GitHub Release, downloads its first `.apk` asset, and opens the Android installer.

## One-time signing setup

All future APKs must use the same signing key. Generate one key on your Windows computer:

```cmd
keytool -genkeypair -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias gokula
```

Convert the keystore to Base64 in PowerShell:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("upload-keystore.jks")) | Set-Content keystore-base64.txt
```

In GitHub, open **Repository → Settings → Secrets and variables → Actions** and add:

- `ANDROID_KEYSTORE_BASE64`: contents of `keystore-base64.txt`
- `KEYSTORE_PASSWORD`: password entered during key creation
- `KEY_ALIAS`: `gokula`
- `KEY_PASSWORD`: key password entered during key creation

Never upload `upload-keystore.jks` or the passwords to GitHub.

## Publish an update

1. Increase `version:` in `pubspec.yaml`, for example `1.2.0+3`.
2. Commit and push the code.
3. Create and push a matching version tag:

```cmd
git tag v1.2.0
git push origin v1.2.0
```

GitHub Actions builds a signed APK and attaches it to a new GitHub Release. Installed apps detect the new release the next time they open.

## Important

The first APK using this stable signing key may require uninstalling the old APK if the old one was signed with a different debug key. After installing the stable-signed APK once, future releases update the same app without uninstalling it.

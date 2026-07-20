import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")

if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use {
        keystoreProperties.load(it)
    }
}

val storeFileValue =
    keystoreProperties.getProperty("storeFile")
        ?: System.getenv("ANDROID_KEYSTORE_PATH")

val storePasswordValue =
    keystoreProperties.getProperty("storePassword")
        ?: System.getenv("ANDROID_KEYSTORE_PASSWORD")

val keyAliasValue =
    keystoreProperties.getProperty("keyAlias")
        ?: System.getenv("ANDROID_KEY_ALIAS")

val keyPasswordValue =
    keystoreProperties.getProperty("keyPassword")
        ?: System.getenv("ANDROID_KEY_PASSWORD")

val hasReleaseSigning =
    !storeFileValue.isNullOrBlank() &&
    !storePasswordValue.isNullOrBlank() &&
    !keyAliasValue.isNullOrBlank() &&
    !keyPasswordValue.isNullOrBlank()

val isReleaseBuild = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}

if (isReleaseBuild && !hasReleaseSigning) {
    throw GradleException(
        "Release signing information is missing. Update android/key.properties " +
            "or configure the Android signing environment variables."
    )
}

android {
    namespace = "com.gokula.gokula_inventory"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.gokula.gokula_inventory"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                // This path is resolved relative to android/app.
                storeFile = file(storeFileValue!!)
                storePassword = storePasswordValue
                keyAlias = keyAliasValue
                keyPassword = keyPasswordValue
            }
        }
    }

    buildTypes {
        getByName("debug") {
            // Android's standard debug keystore is used automatically.
        }

        getByName("release") {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing (README, "Releasing"). Read from android/key.properties or,
// on a build server, from environment variables. Neither the file nor the
// keystore is ever committed (.gitignore: key.properties, *.jks, *.keystore).
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) FileInputStream(file).use { load(it) }
}

fun signing(property: String, environment: String): String? =
    (keystoreProperties.getProperty(property) ?: System.getenv(environment))
        ?.takeIf { it.isNotBlank() }

val releaseStoreFile = signing("storeFile", "RP365_UPLOAD_KEYSTORE")

android {
    namespace = "com.rightproperty365.rightproperty365"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Never change: it is the app's identity in Google Play.
        applicationId = "com.rightproperty365.rightproperty365"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // From pubspec.yaml's `version: <name>+<number>`, or --build-name and
        // --build-number. The number must grow with every upload.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseStoreFile != null) {
            create("release") {
                storeFile = file(releaseStoreFile)
                storePassword = signing("storePassword", "RP365_UPLOAD_STORE_PASSWORD")
                keyAlias = signing("keyAlias", "RP365_UPLOAD_KEY_ALIAS")
                keyPassword = signing("keyPassword", "RP365_UPLOAD_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (releaseStoreFile != null) {
                signingConfigs.getByName("release")
            } else {
                // No upload key here: signed with the debug key so that
                // `flutter run --release` works. Such a build cannot be
                // uploaded to Google Play.
                logger.warn(
                    "RightProperty365: no upload key (android/key.properties or " +
                        "RP365_UPLOAD_KEYSTORE); the release build is signed with the debug key.",
                )
                signingConfigs.getByName("debug")
            }
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

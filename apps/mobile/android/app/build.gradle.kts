plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val pzdReleaseKeystore = System.getenv("PZD_ANDROID_KEYSTORE_FILE")
val pzdReleaseAlias = System.getenv("PZD_ANDROID_KEY_ALIAS")
val pzdReleaseStorePassword = System.getenv("PZD_ANDROID_STORE_PASSWORD")
val pzdReleaseKeyPassword = System.getenv("PZD_ANDROID_KEY_PASSWORD")
val pzdCdSigning = System.getenv("PZD_ANDROID_CD_SIGNING") == "true"

android {
    if (pzdCdSigning) {
        require(!pzdReleaseKeystore.isNullOrBlank() && !pzdReleaseAlias.isNullOrBlank() &&
            !pzdReleaseStorePassword.isNullOrBlank() && !pzdReleaseKeyPassword.isNullOrBlank()) {
            "PZD Android CD signing secrets missing"
        }
        signingConfigs {
            create("pzdStaging") {
                storeFile = file(pzdReleaseKeystore!!)
                storePassword = pzdReleaseStorePassword
                keyAlias = pzdReleaseAlias
                keyPassword = pzdReleaseKeyPassword
            }
        }
    }
    namespace = "app.puzzleduel.puzzle_duel_mobile"
    // Flutter 3.50.0 toolchain defaults: compileSdk/targetSdk = 36.
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "app.puzzleduel.puzzle_duel_mobile"
        // ADR-001 / Flutter 3.50 floor: Android API 24.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Debug signing for local bootstrap only. Store release signing is out of scope.
            signingConfig = if (pzdCdSigning) signingConfigs.getByName("pzdStaging") else signingConfigs.getByName("debug")
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

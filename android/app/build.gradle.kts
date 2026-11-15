import java.util.Properties

// Release signing: android/key.properties (storeFile, storePassword, keyAlias,
// keyPassword) — written by CI from secrets. Without it, release uses the debug key.
val keyProps = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) f.inputStream().use { load(it) }
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.mimray.mimray"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.mimray.mimray"
        minSdk = 24 // libbox is built for API 24+
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Compress the sing-box native library inside the APK: ~3x smaller download,
    // unpacked once at install.
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }

    signingConfigs {
        if (keyProps.containsKey("storeFile")) {
            create("release") {
                storeFile = file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // sing-box core, built by tool/build_libbox.sh from the pinned source
    implementation(files("libs/libbox.aar"))
    implementation("androidx.core:core-ktx:1.13.1") // FileProvider for updates
    implementation("com.journeyapps:zxing-android-embedded:4.3.0") // camera QR scan (ZXing, no Play Services)
}

flutter {
    source = "../.."
}

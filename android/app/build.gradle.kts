import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing key, kept out of git. See android/key.properties.example and README.md.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) keystorePropertiesFile.inputStream().use { load(it) }
}
val hasReleaseKey = keystorePropertiesFile.exists()

android {
    namespace = "vn.pavex.field"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Default id until the final one is chosen; changing it later makes a new app on the stores.
        applicationId = "vn.pavex.field"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                fun required(key: String): String = keystoreProperties.getProperty(key)?.takeIf { it.isNotBlank() }
                    ?: throw GradleException("android/key.properties is missing \"$key\". See android/key.properties.example.")
                storeFile = rootProject.file(required("storeFile"))
                storePassword = required("storePassword")
                keyAlias = required("keyAlias")
                keyPassword = required("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Never the debug key: without android/key.properties the release build stops (see below).
            if (hasReleaseKey) signingConfig = signingConfigs.getByName("release")
        }
    }
}

// Debug and profile builds keep the debug key; only a release build needs the real one.
if (!hasReleaseKey) {
    tasks.matching { it.name == "preReleaseBuild" }.configureEach {
        doFirst {
            throw GradleException(
                "Release build needs a signing key: create android/key.properties " +
                    "(copy android/key.properties.example) pointing at your upload keystore. See README.md."
            )
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

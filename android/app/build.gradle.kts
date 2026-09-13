plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val signingValues = mapOf(
    "storeFile" to System.getenv("ANDROID_RELEASE_KEYSTORE_FILE"),
    "storePassword" to System.getenv("ANDROID_RELEASE_KEYSTORE_PASSWORD"),
    "keyAlias" to System.getenv("ANDROID_RELEASE_KEY_ALIAS"),
    "keyPassword" to System.getenv("ANDROID_RELEASE_KEY_PASSWORD"),
)
val missingSigningValues = signingValues.filterValues { it.isNullOrBlank() }.keys
val signingRequired = System.getenv("GURI_RELEASE_SIGNING_REQUIRED") == "true"
if (signingRequired && missingSigningValues.isNotEmpty()) {
    throw GradleException("Release signing requires: ${missingSigningValues.joinToString()}.")
}

android {
    namespace = "io.github.okaisan.gurilauncher"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.github.okaisan.gurilauncher"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (missingSigningValues.isEmpty()) {
            create("release") {
                storeFile = file(requireNotNull(signingValues["storeFile"]))
                storePassword = signingValues["storePassword"]
                keyAlias = signingValues["keyAlias"]
                keyPassword = signingValues["keyPassword"]
                storeType = "PKCS12"
            }
        }
    }
    buildTypes {
        release {
            signingConfig = if (missingSigningValues.isEmpty()) signingConfigs.getByName("release") else null
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter { source = "../.." }

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

val configuredVersionCode = providers.gradleProperty("guriVersionCode").orNull
val appVersionCode = when {
    configuredVersionCode == null -> 1
    configuredVersionCode.toIntOrNull() == null ->
        throw GradleException("guriVersionCode must be an integer from 1 through 2100000000.")
    else -> configuredVersionCode.toInt()
}
if (appVersionCode !in 1..2100000000) {
    throw GradleException("guriVersionCode must be an integer from 1 through 2100000000.")
}
val appVersionName = providers.gradleProperty("guriVersionName").orNull ?: "0.1.0"

val releaseSigningRequired = when (
    val configuredValue = providers.environmentVariable("GURI_RELEASE_SIGNING_REQUIRED").orNull
) {
    null, "false" -> false
    "true" -> true
    else -> throw GradleException("GURI_RELEASE_SIGNING_REQUIRED must be 'true' or 'false'.")
}
val releaseKeystoreFile = providers.environmentVariable("ANDROID_RELEASE_KEYSTORE_FILE").orNull
val releaseKeystorePassword =
    providers.environmentVariable("ANDROID_RELEASE_KEYSTORE_PASSWORD").orNull
val releaseKeyAlias = providers.environmentVariable("ANDROID_RELEASE_KEY_ALIAS").orNull
val releaseKeyPassword = providers.environmentVariable("ANDROID_RELEASE_KEY_PASSWORD").orNull
val missingSigningValues = listOf(
    "ANDROID_RELEASE_KEYSTORE_FILE" to releaseKeystoreFile,
    "ANDROID_RELEASE_KEYSTORE_PASSWORD" to releaseKeystorePassword,
    "ANDROID_RELEASE_KEY_ALIAS" to releaseKeyAlias,
    "ANDROID_RELEASE_KEY_PASSWORD" to releaseKeyPassword,
).filter { (_, value) -> value.isNullOrBlank() }.map { (name, _) -> name }

if (releaseSigningRequired && missingSigningValues.isNotEmpty()) {
    throw GradleException(
        "Release signing requires: ${missingSigningValues.joinToString(", ")}.",
    )
}

android {
    namespace = "io.github.okaisan.gurilauncher"
    compileSdk = 35

    val releaseSigningConfig = if (missingSigningValues.isEmpty()) {
        signingConfigs.create("release") {
            storeFile = file(requireNotNull(releaseKeystoreFile))
            storePassword = requireNotNull(releaseKeystorePassword)
            keyAlias = requireNotNull(releaseKeyAlias)
            keyPassword = requireNotNull(releaseKeyPassword)
            storeType = "PKCS12"
        }
    } else {
        null
    }

    defaultConfig {
        applicationId = "io.github.okaisan.gurilauncher"
        minSdk = 26
        targetSdk = 35
        versionCode = appVersionCode
        versionName = appVersionName
    }
    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = releaseSigningConfig
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    buildFeatures { compose = true }
}

dependencies {
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    debugImplementation(libs.androidx.compose.ui.tooling)
    testImplementation(libs.junit)
}

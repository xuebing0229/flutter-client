import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

fun loadSigningProperties(fileName: String): Properties {
    val properties = Properties()
    val propertiesFile = rootProject.file(fileName)
    if (propertiesFile.exists()) {
        propertiesFile.inputStream().use { properties.load(it) }
    }
    return properties
}

fun signingValue(
    properties: Properties,
    key: String,
    environmentName: String,
): String? = properties.getProperty(key) ?: System.getenv(environmentName)

val betaSigningProperties = loadSigningProperties("beta-key.properties")
val releaseSigningProperties = loadSigningProperties("release-key.properties")

val betaStoreFile = signingValue(betaSigningProperties, "storeFile", "BETA_STORE_FILE")
val betaStorePassword = signingValue(betaSigningProperties, "storePassword", "BETA_STORE_PASSWORD")
val betaKeyAlias = signingValue(betaSigningProperties, "keyAlias", "BETA_KEY_ALIAS")
val betaKeyPassword = signingValue(betaSigningProperties, "keyPassword", "BETA_KEY_PASSWORD")

val releaseStoreFile = signingValue(releaseSigningProperties, "storeFile", "RELEASE_STORE_FILE")
val releaseStorePassword = signingValue(releaseSigningProperties, "storePassword", "RELEASE_STORE_PASSWORD")
val releaseKeyAlias = signingValue(releaseSigningProperties, "keyAlias", "RELEASE_KEY_ALIAS")
val releaseKeyPassword = signingValue(releaseSigningProperties, "keyPassword", "RELEASE_KEY_PASSWORD")

android {
    namespace = "com.workspace.client.k7m4"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.workspace.client.k7m4"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildFeatures {
        buildConfig = true
    }

    signingConfigs {
        if (
            betaStoreFile != null &&
            betaStorePassword != null &&
            betaKeyAlias != null &&
            betaKeyPassword != null
        ) {
            create("betaRelease") {
                storeFile = rootProject.file(betaStoreFile)
                storePassword = betaStorePassword
                keyAlias = betaKeyAlias
                keyPassword = betaKeyPassword
            }
        }

        if (
            releaseStoreFile != null &&
            releaseStorePassword != null &&
            releaseKeyAlias != null &&
            releaseKeyPassword != null
        ) {
            create("stableRelease") {
                storeFile = rootProject.file(releaseStoreFile)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    flavorDimensions += "channel"
    productFlavors {
        create("beta") {
            dimension = "channel"
            applicationIdSuffix = ".beta"
            buildConfigField("int", "SYNCTHING_API_PORT", "8385")
            signingConfig = signingConfigs.findByName("betaRelease")
        }
        create("stable") {
            dimension = "channel"
            buildConfigField("int", "SYNCTHING_API_PORT", "8384")
            signingConfig = signingConfigs.findByName("stableRelease")
        }
    }

    sourceSets {
        getByName("beta").jniLibs.srcDirs("src/sync/jniLibs")
        getByName("stable").jniLibs.srcDirs("src/sync/jniLibs")
    }

    packaging {
        jniLibs {
            // The embedded Syncthing executable must be extracted to
            // applicationInfo.nativeLibraryDir so Android can execute it.
            useLegacyPackaging = true
        }
    }

    buildTypes {
        release {
            // Signing comes from the selected product flavor.
            // Without the corresponding local/CI key configuration, release
            // variants remain unsigned instead of silently using a debug key.
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    implementation("androidx.work:work-runtime:2.11.0")
}

flutter {
    source = "../.."
}

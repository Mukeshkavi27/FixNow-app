import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val localProperties = Properties().apply {
    val file = rootProject.file("local.properties")
    if (file.exists()) {
        file.inputStream().use(::load)
    }
}

val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) {
        file.inputStream().use(::load)
    }
}

fun configValue(name: String, defaultValue: String = ""): String {
    return (project.findProperty(name) as String?)
        ?: localProperties.getProperty(name)
        ?: System.getenv(name)
        ?: defaultValue
}

val hasReleaseSigning = listOf(
    "storeFile",
    "storePassword",
    "keyAlias",
    "keyPassword",
).all { keystoreProperties.getProperty(it)?.isNotBlank() == true }

android {
    namespace = configValue("FIXNOW_APPLICATION_ID", "com.fixnow.app")
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = configValue("FIXNOW_APPLICATION_ID", "com.fixnow.app")
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["GOOGLE_MAPS_API_KEY"] = configValue("GOOGLE_MAPS_API_KEY")
    }

    signingConfigs {
        create("release") {
            if (hasReleaseSigning) {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(
                if (hasReleaseSigning) "release" else "debug"
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

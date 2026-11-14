import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

fun signingValue(envName: String, propertyName: String): String? =
    System.getenv(envName)?.takeIf { it.isNotBlank() }
        ?: keystoreProperties.getProperty(propertyName)?.takeIf { it.isNotBlank() }

val releaseStorePath = signingValue("IRON_KEYSTORE_PATH", "storeFile")
val releaseStorePassword = signingValue("IRON_KEYSTORE_PASSWORD", "storePassword")
val releaseKeyAlias = signingValue("IRON_KEY_ALIAS", "keyAlias")
val releaseKeyPassword = signingValue("IRON_KEY_PASSWORD", "keyPassword")
val releaseStoreFile = releaseStorePath?.let { path ->
    val asWritten = file(path)
    when {
        asWritten.exists() -> asWritten
        else -> rootProject.file(path)
    }
}
val hasReleaseSigning =
    releaseStoreFile != null &&
        releaseStoreFile.exists() &&
        !releaseStorePassword.isNullOrBlank() &&
        !releaseKeyAlias.isNullOrBlank() &&
        !releaseKeyPassword.isNullOrBlank()

android {
    namespace = "com.example.ironmusic420ai"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = releaseStoreFile
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    defaultConfig {
        applicationId = "com.example.ironmusic420ai"
        minSdk = 24
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            abiFilters += "arm64-v8a"
        }
    }

    buildTypes {
        getByName("debug") {
            // Uses the default Android debug keystore.
        }
        getByName("release") {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }

    packaging {
        jniLibs {
            pickFirsts += setOf("**/libc++_shared.so")
            val voiceService = file("src/main/kotlin/com/example/ironmusic420ai/IronVoiceService.kt")
            val voiceEnabled = voiceService.exists() &&
                voiceService.readText().contains("const val SERVICE_ENABLED = true")
            if (!voiceEnabled) {
                // Keep the AAR for compilation, but do not ship sherpa/onnx native libs
                // while the wake-word service is disabled.
                excludes += setOf(
                    "**/libsherpa-onnx*.so",
                    "**/libonnxruntime.so",
                    "**/libonnxruntime*.so",
                )
            }
        }
        resources {
            excludes += setOf(
                "META-INF/DEPENDENCIES",
                "META-INF/LICENSE",
                "META-INF/LICENSE.txt",
                "META-INF/NOTICE",
                "META-INF/NOTICE.txt",
            )
        }
    }
}

dependencies {
    implementation(files("libs/sherpa-onnx-1.13.4.aar"))
    testImplementation("junit:junit:4.13.2")
}

flutter {
    source = "../.."
}

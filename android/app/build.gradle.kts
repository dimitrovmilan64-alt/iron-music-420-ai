plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

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
        create("ironTest") {
            storeFile = file("iron-test-key.jks")
            storePassword = "iron420test"
            keyAlias = "iron-test"
            keyPassword = "iron420test"
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
            signingConfig = signingConfigs.getByName("ironTest")
        }
        getByName("release") {
            signingConfig = signingConfigs.getByName("ironTest")
        }
    }

    packaging {
        jniLibs {
            pickFirsts += setOf("**/libc++_shared.so")
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

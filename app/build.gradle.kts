// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.

plugins {
    alias(libs.plugins.androidApplication)
    alias(libs.plugins.kotlinAndroid)
    alias(libs.plugins.composeCompiler)
}

android {
    namespace = "com.cinderblocksoftware.kaleidopaint"
    compileSdk = 36

    defaultConfig {
        // The applicationId becomes permanent at the first Play upload.
        applicationId = "com.cinderblocksoftware.kaleidopaint"
        minSdk = 26
        targetSdk = 36
        versionCode = 12
        versionName = "0.12.0"
        testInstrumentationRunner = "com.cinderblocksoftware.kaleidopaint.KaleidoPaintTestRunner"
    }

    signingConfigs {
        create("upload") {
            val secretDir = File(System.getProperty("user.home"), ".config/kaleidopaint-android")
            val passwordFile = File(secretDir, "upload-password")
            storeFile = File(secretDir, "upload.jks")
            storePassword = if (passwordFile.exists()) passwordFile.readText().trim() else null
            keyAlias = "kaleidopaint-upload"
            keyPassword = storePassword
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("upload")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }
}

dependencies {
    implementation(project(":geometry"))
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    debugImplementation(libs.androidx.compose.ui.tooling)
}

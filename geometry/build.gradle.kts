// Android port © 2026 Cinderblock Software, GPLv3+. See LICENSE.
//
// The maths of KaleidoPaint, with no Android dependency,
// so that it can be unit tested on the JVM.

plugins {
    alias(libs.plugins.kotlinJvm)
}

kotlin {
    jvmToolchain(17)
}

dependencies {
    testImplementation(libs.junit)
}

tasks.test {
    testLogging {
        events("failed")
        showStandardStreams = false
    }
}

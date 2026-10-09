// Official PaddleOCR PP-OCRv6 Android source. Only build tooling adapted to Flutter AGP 9.
plugins { id("com.android.library") }
android {
    namespace = "com.paddle.ocr"
    compileSdk = 36
    defaultConfig { minSdk = 26 }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
}
kotlin { compilerOptions { jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17 } }
dependencies {
    implementation("com.microsoft.onnxruntime:onnxruntime-android:1.21.1")
    // Modern Android compatible OpenCV Java API, replacing upstream's obsolete QuickBird AAR.
    implementation("org.opencv:opencv:4.13.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
    implementation("androidx.core:core-ktx:1.13.1")
}

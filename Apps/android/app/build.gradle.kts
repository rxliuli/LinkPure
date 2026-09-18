plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "com.rxliuli.linkpure"
    compileSdk {
        version = release(37)
    }

    defaultConfig {
        // ★ Release **必须**复用 Flutter 版在 Play 上的包名，否则老用户收不到更新、
        //   评分/下载量归零。跟 iOS/macOS 复用 bundle id 是同一个道理。
        //   Debug 加 .dev 以便与 Play 版共存（也因此 debug 包读不到 Flutter 版的旧规则，
        //   规则迁移要在 Release 配置下才验得了）。
        applicationId = "com.rxliuli.linkpure"
        minSdk = 26
        targetSdk = 37
        // ★ versionCode 必须**大于 Flutter 版在 Play 上的当前值**（0.5.2 → 502），
        //   否则 Play 会直接拒掉。命名与 Swift 侧的 build 号对齐（0.6.0 → 600）。
        versionCode = 600
        versionName = "0.6.0"
    }

    buildTypes {
        debug {
            // 平时用 .dev 后缀以便与 Play 版共存。
            //
            // 要验证 **Flutter 规则迁移**时必须用真实包名（否则数据目录不同、
            // 读不到 Flutter 版留下的 shared_prefs）：
            //   ./gradlew :app:assembleDebug -PrealPackage
            if (!project.hasProperty("realPackage")) {
                applicationIdSuffix = ".dev"
            }
        }
        release {
            isMinifyEnabled = false
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
    }
}

dependencies {
    implementation(project(":core"))

    implementation(libs.kotlinx.coroutines.android)

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material.icons)
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)

    debugImplementation(libs.androidx.compose.ui.tooling)
}

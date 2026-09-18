plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
}

// ── 版本号不在这里存第二份 ────────────────────────────────────────────────
// 唯一来源是仓库根部的 project.yml（跟 :core 引用规则库/一致向量是同一个做法，
// 见 core/build.gradle.kts）。于是“改版本号”在两端都是同一个动作：改 project.yml。
//
// 用 providers.fileContents 而不是 file().readText()：前者会被记成构建输入，
// 将来打开 configuration cache 也不会读到缓存的旧值（Gradle 一直在提示可以开）。
val projectYmlFile = layout.projectDirectory.file("../../../project.yml")
// 文件不存在时 asText 是一个“没有值”的 provider，.get() 只会抛
// "Cannot query the value of this provider…"；先 orElse 成空串，
// 再由下面的检查给出能看懂的报错。
val projectYmlText = providers.fileContents(projectYmlFile).asText.orElse("")

fun projectYmlSetting(text: String, key: String): String {
    if (text.isBlank()) {
        error("读不到 ${projectYmlFile.asFile}——Android 的版本号从仓库根的 project.yml 派生（见 Scripts/check-version.sh）")
    }
    return Regex("""^\s*$key:\s*"?([^"#\s]+)""", RegexOption.MULTILINE)
        .find(text)?.groupValues?.get(1)
        ?: error("project.yml 里读不到 $key")
}

val marketingVersion: String = projectYmlText.map { projectYmlSetting(it, "MARKETING_VERSION") }.get()

// 与 Apple 侧 release.yml、以及 Flutter 那条线用同一个公式：x*10000 + y*100 + z
val versionCodeFromVersion: Int = marketingVersion.split(".").let { parts ->
    if (parts.size != 3 || parts.any { it.toIntOrNull() == null }) {
        error("project.yml 的 MARKETING_VERSION '$marketingVersion' 不是 x.y.z 形式")
    }
    parts[0].toInt() * 10000 + parts[1].toInt() * 100 + parts[2].toInt()
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
        //   否则 Play 会直接拒掉。值来自 project.yml 的 MARKETING_VERSION，
        //   公式与 Apple 侧的 build number 相同（0.6.1 → 601）。
        versionCode = versionCodeFromVersion
        versionName = marketingVersion
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

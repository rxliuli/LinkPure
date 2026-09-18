import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
}

// 纯 JVM 模块：**不依赖 Android**。
// 这样 1053 条一致性向量能在几秒内跑完，而且引擎里不可能不小心用到 Android API。
kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

// ── 共享 spec 的唯一来源 ────────────────────────────────────────────────
// 规则库和向量**不在这里存第二份**：直接引用仓库根部那一份，
// 也就是 Swift 侧 LinkPureCore / LinkPureCoreTests 用的同一批文件。
// 从 Apps/android/core 往上三级 = 仓库根。
val sharedRulesDir = "../../../Sources/LinkPureCore/Resources"
val vectorsDir = "../../../Tests/LinkPureCoreTests/Vectors"

// 配置期就检查，缺了立刻失败——而不是跑出一个「0 条向量且全绿」的假成功
listOf(
    "$sharedRulesDir/shared-rules.json",
    "$vectorsDir/01-params.json",
    "$vectorsDir/11-rules-shared.json",
).forEach { relative ->
    check(file(relative).exists()) {
        "找不到共享 spec：$relative\n" +
            "Apps/android 依赖仓库根部的 Sources/LinkPureCore/Resources 与 Tests/LinkPureCoreTests/Vectors。"
    }
}

sourceSets {
    main {
        // 规则库要进产物（运行时 RulesManager 从 classpath 读）
        resources.srcDir(sharedRulesDir)
    }
}

dependencies {
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.kotlinx.coroutines.core)

    testImplementation(kotlin("test"))
}

// 向量只是测试数据，不进产物；同步到 build/ 下再告诉测试去哪儿找。
val syncVectors = tasks.register<Sync>("syncVectors") {
    from(vectorsDir)
    into(layout.buildDirectory.dir("vectors"))
}

tasks.test {
    dependsOn(syncVectors)
    systemProperty("linkpure.vectorsDir", layout.buildDirectory.dir("vectors").get().asFile.absolutePath)
    useJUnitPlatform()
    testLogging {
        events("passed", "skipped", "failed")
        showStandardStreams = true
    }
}

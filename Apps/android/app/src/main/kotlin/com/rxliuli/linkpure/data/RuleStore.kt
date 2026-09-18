package com.rxliuli.linkpure.data

import android.content.Context
import androidx.compose.runtime.mutableStateListOf
import com.rxliuli.linkpure.core.FlutterRuleMigration
import com.rxliuli.linkpure.core.LocalRule
import com.rxliuli.linkpure.core.Rule
import com.rxliuli.linkpure.core.RuleFileCodec
import com.rxliuli.linkpure.core.RulesManager
import java.io.File

/**
 * 用户规则 + 内置规则库。
 *
 * **存在文件里，不用 `SharedPreferences`**——理由跟 Swift 侧避开 `UserDefaults` 一样：
 * 它是按包名分域的，换个包名就等于换了个空库，而且毫无痕迹。
 * 文件路径与包名无关，也更好备份、迁移、调试。
 */
object RuleStore {

    private const val FILE_NAME = "rules.json"

    /**
     * Flutter 版 `shared_preferences` 插件用的文件名。
     * 规则存在它下面 `flutter.local_rules` 键，值是 JSON **字符串**。
     */
    private const val FLUTTER_PREFS_FILE = "FlutterSharedPreferences"

    private var appContext: Context? = null

    /** 内置规则库（只读，不可启用/禁用）。 */
    var bundledRules: List<Rule> = emptyList()
        private set

    /** 用户规则。UI 直接读这个列表，改完调 [save]。 */
    val userRules = mutableStateListOf<LocalRule>()

    val enabledUserRuleCount: Int get() = userRules.count { it.enabled }

    fun init(context: Context) {
        if (appContext != null) return
        appContext = context.applicationContext
        bundledRules = runCatching { RulesManager.loadBundledRules() }.getOrDefault(emptyList())
        load()
    }

    /** 先用户规则（新规则优先），再内置规则库——顺序会影响命中结果。 */
    fun rulesForCleaning(): List<Rule> =
        userRules.filter { it.enabled }.map { it.rule } + bundledRules

    // MARK: 改动

    /**
     * 新增或更新一条用户规则。
     *
     * **新增放到最前**（新规则优先）；编辑已有规则则**原位替换**，保留它的优先级位置。
     */
    fun upsert(rule: LocalRule) {
        val index = userRules.indexOfFirst { it.id == rule.id }
        if (index < 0) userRules.add(0, rule) else userRules[index] = rule
        save()
    }

    fun remove(id: String) {
        val index = userRules.indexOfFirst { it.id == id }
        if (index < 0) return
        userRules.removeAt(index)
        save()
    }

    /** 移除并返回它原来的下标，供「撤销」插回原位——规则集是有序的，顺序会影响命中结果。 */
    fun removeWithIndex(id: String): Pair<LocalRule, Int>? {
        val index = userRules.indexOfFirst { it.id == id }
        if (index < 0) return null
        val removed = userRules.removeAt(index)
        save()
        return removed to index
    }

    fun insertAt(rule: LocalRule, index: Int) {
        userRules.add(index.coerceIn(0, userRules.size), rule)
        save()
    }

    fun setEnabled(id: String, enabled: Boolean) {
        val index = userRules.indexOfFirst { it.id == id }
        if (index < 0) return
        userRules[index] = userRules[index].copy(enabled = enabled)
        save()
    }

    fun replaceAll(rules: List<LocalRule>) {
        userRules.clear()
        userRules.addAll(rules)
    }

    fun save() {
        val context = appContext ?: return
        val target = File(context.filesDir, FILE_NAME)
        val tmp = File(context.filesDir, "$FILE_NAME.tmp")
        runCatching {
            tmp.writeText(RuleFileCodec.encode(userRules.toList()))
            // 先写临时文件再换过去：直接覆盖的话，写到一半被杀就只剩半个文件
            if (!tmp.renameTo(target)) {
                target.delete()
                tmp.renameTo(target)
            }
        }
    }

    // MARK: 加载 / 迁移

    private fun load() {
        val context = appContext ?: return
        val file = File(context.filesDir, FILE_NAME)

        if (file.exists()) {
            val rules = runCatching { RuleFileCodec.decode(file.readText()) }.getOrNull()
            if (rules != null) {
                replaceAll(rules)
                return
            }
            // 文件解析不了：**别静默清空**，先留个备份再走迁移
            runCatching { file.renameTo(File(context.filesDir, "$FILE_NAME.corrupt")) }
        }

        migrateFromFlutter()?.let {
            replaceAll(it)
            save()
        }
    }

    /**
     * 从 Flutter 版迁入用户规则。
     *
     * Flutter 版把规则存在 `shared_preferences` 里（`flutter.local_rules` 键，
     * 值是 JSON 字符串）。原生版**复用同一个包名**，所以升级替换后能直接读到。
     *
     * 不写死文件名：`shared_prefs/` 下的 xml 文件名随插件版本变过，
     * 干脆把这目录里每个文件都当 preferences 试一遍。
     */
    private fun migrateFromFlutter(): List<LocalRule>? {
        val context = appContext ?: return null

        for (name in flutterPrefsCandidates(context)) {
            val json = runCatching {
                context.getSharedPreferences(name, Context.MODE_PRIVATE)
                    .getString(FlutterRuleMigration.DEFAULT_KEY, null)
            }.getOrNull() ?: continue
            FlutterRuleMigration.decode(json)?.let { return it }
        }
        return null
    }

    private fun flutterPrefsCandidates(context: Context): List<String> {
        val names = LinkedHashSet<String>()
        names.add(FLUTTER_PREFS_FILE)
        runCatching {
            File(context.dataDir, "shared_prefs").listFiles()
                ?.filter { it.extension == "xml" }
                ?.map { it.nameWithoutExtension }
                ?.let { names.addAll(it) }
        }
        return names.toList()
    }
}

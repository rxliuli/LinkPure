#!/usr/bin/env bash
# 从 LinkPure（Flutter 仓库）同步「共享真相」：规则库 + conformance 向量。
#
#   ./Scripts/sync-spec.sh [LinkPure 仓库路径]
#
# 规则库和向量是跨语言的数据契约，以 Flutter 仓库为唯一来源；
# 这里做一份 vendored 拷贝，好让本仓库能自包含地构建与测试（也方便进 CI）。
set -euo pipefail

SRC="${1:-$HOME/code/flutter/LinkPure}"
DST="$(cd "$(dirname "$0")/.." && pwd)"

if [ ! -f "$SRC/assets/shared-rules.json" ]; then
  echo "找不到规则库：$SRC/assets/shared-rules.json" >&2
  exit 1
fi

# Swift 侧先加的规则（上游 Flutter 仓库的规则源里暂时没有）。
# 同步是整体覆盖，上游没跟上就会把这几条冲掉——所以先查、直接失败，
# 而不是静默丢功能（Tests 里也有对应的守护断言）。
# 等它们上游进 internal/rules/sources/custom-rules.json 之后，这段可以删。
LOCAL_ONLY_RULES=(linkpure-youtu.be-short-link linkpure-youtu.be-short-link-query)
for id in "${LOCAL_ONLY_RULES[@]}"; do
  if ! grep -q "\"$id\"" "$SRC/assets/shared-rules.json"; then
    echo "上游规则库里还没有 ${id}：这次同步会冲掉它。" >&2
    echo "请先把它加进 Flutter 仓库的 internal/rules/sources/custom-rules.json 再同步。" >&2
    exit 1
  fi
done

cp "$SRC/assets/shared-rules.json" "$DST/Sources/LinkPureCore/Resources/shared-rules.json"

# 注：Apps/android 的 :core 模块**不存副本**，它的 build.gradle.kts 直接引用
# Sources/LinkPureCore/Resources 与 Tests/LinkPureCoreTests/Vectors。
# 所以改这里的路径 = 同时改了两个平台，改完记得 `./gradlew :core:test`
# （在 Apps/android 下跑）验一下 Kotlin 侧。

# 先把向量拷到临时目录、成功了再把目录换过去：
# 直接 `rm -rf` 再 `cp` 的话，一旦源目录里没有向量（或 cp 失败），
# 本地就只剩下一个空目录——测试会“跑 0 条向量且全绿”，比直接报错隐蔽得多。
VECTORS_TMP="$(mktemp -d)"
cp "$SRC"/conformance/vectors/*.json "$VECTORS_TMP"/
rm -rf "$DST/Tests/LinkPureCoreTests/Vectors"
mv "$VECTORS_TMP" "$DST/Tests/LinkPureCoreTests/Vectors"

echo "已从 $SRC 同步："
echo "  规则库  -> Sources/LinkPureCore/Resources/shared-rules.json"
echo "  向量    -> Tests/LinkPureCoreTests/Vectors/ ($(ls -1 "$DST/Tests/LinkPureCoreTests/Vectors" | wc -l | tr -d ' ') 个文件)"

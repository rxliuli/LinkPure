#!/usr/bin/env bash
#
# 版本号一致性检查（CI 里也会跑）。
#
# 版本号的**唯一来源**是仓库根 project.yml 的 MARKETING_VERSION，两端都从它派生，
# 公式与 Flutter 那条线一致：x*10000 + y*100 + z
#   - Apple：release.yml 按公式算出 CFBundleVersion 覆盖进去
#   - Android：Apps/android/app/build.gradle.kts 直接读 project.yml
#
# 这里防两件事：
#   1. project.yml 里手写的 CURRENT_PROJECT_VERSION 与公式算出来的不一致
#      （那样本机 Xcode archive 的结果与 CI 发的包不是同一个 build number）
#   2. 有人在 Android 侧又写死一份版本号
set -euo pipefail
cd "$(dirname "$0")/.."

PROJECT_YML=project.yml
ANDROID_GRADLE=Apps/android/app/build.gradle.kts

fail() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

# 取 `KEY: "value"` 里的 value：掐掉行尾注释、引号与空白。
# 刻意只用 grep/sed 的公共子集——之前踩过 GNU 与 BSD 的 sed BRE 区间不一致。
read_setting() {
  grep -E "^[[:space:]]*$1:" "$PROJECT_YML" \
    | head -1 \
    | sed 's/#.*//' \
    | sed -E "s/^[[:space:]]*$1:[[:space:]]*//" \
    | tr -d '"[[:space:]]'
}

version=$(read_setting MARKETING_VERSION)
build=$(read_setting CURRENT_PROJECT_VERSION)

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || fail "project.yml 的 MARKETING_VERSION 不是 x.y.z 形式：'${version}'"

IFS='.' read -r major minor patch <<< "$version"
expected=$((major * 10000 + minor * 100 + patch))

[[ "$build" == "$expected" ]] \
  || fail "project.yml 的 CURRENT_PROJECT_VERSION=${build} 与公式算出来的 ${expected} 不一致（${version} → ${expected}）"

# 写死的版本号（带引号的字符串或纯数字）说明又存了第二份
hardcoded='^[[:space:]]*(versionCode|versionName)[[:space:]]*=[[:space:]]*("[^"]*"|[0-9]+)'
if grep -nE "$hardcoded" "$ANDROID_GRADLE" >/dev/null; then
  grep -nE "$hardcoded" "$ANDROID_GRADLE" >&2
  fail "$ANDROID_GRADLE 里又出现了写死的 versionCode/versionName——应该从 project.yml 派生"
fi

# 注意：中文紧跟在变量后面时必须用 ${...}，否则 bash 会把多字节字符的首字节
# 当成变量名的一部分（`$build（` → unbound variable: build\xe4）。
echo "版本号一致：MARKETING_VERSION=${version}  CURRENT_PROJECT_VERSION=${build}（Android 的 versionName/versionCode 与 Apple 的 build number 都由它派生）"

#!/usr/bin/env bash
#
# 校验「点 Open LinkPure…」或「Finder 双击图标」之后，app 是否真的到了前台。
#
# 为什么需要它：这是个**时机竞态**——`openWindow` 是异步的，`NSApp.activate` 是同步的，
# 激活一旦发生在窗口存在之前就会失效。回归时肉眼只有约 15% 的概率能撞上，所以留一个
# 能复跑的量化检查。背景见 Apps/macOS/LinkPureApp.swift 里 MainWindowOpener 的注释。
#
# 用法:  Scripts/verify-window-activation.sh [轮数]        （默认 20 轮）
#
# 注意：运行期间会反复抢前台（在 Finder 与你当前的 app 之间来回切），别在专心做事时跑。
set -euo pipefail

TRIALS=${1:-20}
PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$PROJECT_DIR"

echo "→ 构建 macOS（确保测的是当前源码，不是旧产物——这个坑踩过）"
if ! xcodebuild -project LinkPure.xcodeproj -scheme LinkPureMac -configuration Debug build >/dev/null 2>&1; then
    echo "  构建失败，先修好再验"
    exit 1
fi

APP="$(xcodebuild -project LinkPure.xcodeproj -scheme LinkPureMac -configuration Debug \
        -showBuildSettings 2>/dev/null \
        | awk -F' = ' '/ BUILT_PRODUCTS_DIR =/{print $2; exit}')/LinkPure.app"
if [ ! -d "$APP" ]; then
    echo "  找不到产物: $APP"
    exit 1
fi
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")
echo "  app:        $APP"
echo "  bundle id:  $BUNDLE_ID"
echo "  产物时间:   $(stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' "$APP/Contents/MacOS/LinkPure")"

# 它只有为真时，启动才会抑制窗口（否则每次启动都弹窗，测的就不是同一条路径了）
defaults write "$BUNDLE_ID" linkpure.hasLaunched -bool true

# 探针：必须把「谁在前台」和「LinkPure 有几个可见窗口」分开报告，
# 才能区分「窗口没打开」和「打开了但 app 没激活」——后者正是这个 bug 的症状。
PROBE_DIR=$(mktemp -d)
trap 'rm -rf "$PROBE_DIR"; killall LinkPure 2>/dev/null || true' EXIT
cat > "$PROBE_DIR/probe.swift" <<'SWIFT'
import AppKit

let bid = CommandLine.arguments[1]
let front = NSWorkspace.shared.frontmostApplication
print("frontmost=\(front?.localizedName ?? "?")")

let app = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first
print("running=\(app != nil) active=\(app?.isActive ?? false)")

if let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] {
    // 只数 layer-0 且高度 > 100 的窗口：排除菜单栏状态项那类辅助窗口
    let mine = list.filter {
        ($0[kCGWindowOwnerName as String] as? String) == "LinkPure"
            && ($0[kCGWindowLayer as String] as? Int) == 0
            && (($0[kCGWindowBounds as String] as? [String: Any])?["Height"] as? Double ?? 0) > 100
    }
    print("windows=\(mine.count)")
} else {
    print("windows=?")
}
SWIFT
swiftc -O -o "$PROBE_DIR/probe" "$PROBE_DIR/probe.swift" 2>/dev/null

killall LinkPure 2>/dev/null || true
sleep 1

ok=0; no_activate=0; no_window=0
for i in $(seq 1 "$TRIALS"); do
    killall LinkPure 2>/dev/null || true; sleep 1
    open -a "$APP"; sleep 2.5            # 启动：窗口被抑制
    open -a Finder; sleep 1.5            # 把别的 app 置为前台
    open -a "$APP"; sleep 2.5            # ← 被测路径（applicationShouldHandleReopen）

    out=$("$PROBE_DIR/probe" "$BUNDLE_ID")
    frontmost=$(echo "$out" | awk -F= '/^frontmost=/{print $2}')
    windows=$(echo "$out"   | awk -F= '/^windows=/{print $2}')

    if [ "$frontmost" = "LinkPure" ] && [ "$windows" = "1" ]; then
        ok=$((ok + 1))
    elif [ "$windows" = "1" ]; then
        no_activate=$((no_activate + 1))
        echo "  ✗ 第 $i 轮：窗口在但没激活（frontmost=$frontmost）"
    else
        no_window=$((no_window + 1))
        echo "  ✗ 第 $i 轮：窗口没打开"
    fi
done

echo
echo "共 $TRIALS 轮：正常 $ok，窗口在但没激活 $no_activate，窗口没打开 $no_window"

if [ "$((no_activate + no_window))" -gt 0 ]; then
    echo "失败：app 没有稳定地到达前台（这正是不该回归的行为）"
    exit 1
fi
echo "通过：每一轮都到达了前台"

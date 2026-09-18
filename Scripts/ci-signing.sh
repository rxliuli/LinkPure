#!/usr/bin/env bash
#
# CI 用的签名物料准备 / 清理 —— 整个仓库只有这一份。
#
# 为什么要有它：同一段「建临时 keychain → 导入 p12 → 落 .p8 → 校验 → 清理」
# 原来在 release.yml 里复制了三份（macos-appstore / ios-appstore / macos-dmg），
# 然后三份分别漂移过——丢过 `mkdir ~/private_keys`、在空 keychain 上跑
# `set-key-partition-list`、把 appstore 证书导入删了又加回来。逻辑只有一份就
# 不会再漂。
#
# 用法：
#   Scripts/ci-signing.sh setup [--expect <身份名片段>]... <CERT_ENV_VAR>...
#   Scripts/ci-signing.sh teardown
#
# 证书用**环境变量名**传（值由调用方注入，脚本自己不读 secrets），密码按
# `<前缀>_BASE64` → `<前缀>_PASSWORD` 的约定自动推导，正好对上仓库里现有的
# APPLE_CERTIFICATE_{APPSTORE,INSTALLER,DEVELOPERID}_{BASE64,PASSWORD}。
#
# setup 结束后向 $GITHUB_ENV（若存在）写入：
#   SIGNING_KEYCHAIN   临时 keychain 的路径
#   SIGNING_IDENTITY   实际导入、且被选中的那个身份的全名，供
#                      `CODE_SIGN_IDENTITY="$SIGNING_IDENTITY"` 精确钉住
#   ASC_KEY_PATH       AuthKey_<keyId>.p8 的路径（没给 APPLE_API_KEY 时为空）
#   ASC_KEY_ID         App Store Connect API key id

set -euo pipefail

KEYCHAIN="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/app-signing.keychain-db"
KEYCHAIN_PASSWORD=actions

fail() {
  echo "::error::$*" >&2
  exit 1
}

# $GITHUB_ENV 只在 Actions 里存在；本机跑的时候静默跳过。
export_env() {
  if [ -n "${GITHUB_ENV:-}" ]; then
    printf '%s=%s\n' "$1" "$2" >>"$GITHUB_ENV"
  fi
}

# secret 里存的可能是「尾部 padding 被丢掉的 base64」，也可能直接就是 PEM。
# 不能只用 `base64 --decode`：它对残缺输入**静默丢字节**——踩过一次，少一个 '='
# 就丢 2 字节，PEM 结束行被砍成 `-----END PRIVATE KEY---`，结果 notarytool /
# xcodebuild 在几分钟后才报一个看不懂的 invalidPEMDocument。
# 所以：补回 padding → 解码 → 由调用方立刻验一遍。
decode_base64() {
  python3 -c 'import base64,sys; s=sys.argv[1].strip(); sys.stdout.buffer.write(s.encode()+b"\n" if "BEGIN PRIVATE KEY" in s else base64.b64decode(s+"="*(-len(s)%4)))' "$1"
}

teardown() {
  security delete-keychain "${SIGNING_KEYCHAIN:-$KEYCHAIN}" >/dev/null 2>&1 || true
  rm -rf "$HOME/private_keys"
  echo "已清理临时 keychain 与 ~/private_keys"
}

setup() {
  local expects=()
  local certs=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --expect)
        [ $# -ge 2 ] || fail "--expect 后面要跟一个身份名片段"
        expects+=("$2")
        shift 2
        ;;
      *)
        certs+=("$1")
        shift
        ;;
    esac
  done
  [ ${#certs[@]} -gt 0 ] || fail "至少要给一个证书环境变量名，例如 APPLE_CERTIFICATE_APPSTORE_BASE64"

  # 同一个 runner 上重跑（或者上一步失败留下的）时先清干净
  security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
  security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
  # 默认几分钟就会自动锁；这条流水线的 job 最长 40 分钟，锁了必然失败。
  security set-keychain-settings -lut 21600 "$KEYCHAIN"
  security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"

  # 把临时 keychain 放到搜索列表最前面，而不是替换掉原列表：runner 上其它
  # keychain 还要能被解析到。
  # 这里不能用 mapfile/readarray —— macOS 的 /bin/bash 卡在 3.2，两个内建都没有。
  local existing=()
  while IFS= read -r line; do
    existing+=("$line")
  done < <(security list-keychains -d user | sed -e 's/^[[:space:]]*"//' -e 's/"[[:space:]]*$//')
  if [ ${#existing[@]} -gt 0 ]; then
    security list-keychains -d user -s "$KEYCHAIN" "${existing[@]}"
  else
    security list-keychains -d user -s "$KEYCHAIN"
  fi
  security default-keychain -s "$KEYCHAIN"

  local name pw_name value password dir
  for name in "${certs[@]}"; do
    case "$name" in
      *_BASE64) pw_name="${name%_BASE64}_PASSWORD" ;;
      *) pw_name="${name}_PASSWORD" ;;
    esac
    value="${!name:-}"
    password="${!pw_name:-}"
    [ -n "$value" ] || fail "$name 是空的（secret 没配？）"
    [ -n "$password" ] || fail "$pw_name 是空的（secret 被设成空值了？）"

    dir="$(mktemp -d)"
    decode_base64 "$value" >"$dir/cert.p12"
    # -A：允许任何程序使用导入的私钥。这只是一次性 runner 上的一次性 keychain，
    # 保留 -A 是这里的常规做法。extport 那边改成了逐个 -T 点名
    # (codesign/security/productbuild)，少点一个（productbuild 没被信任）会让
    # 它**静默卡在**一个永远弹不出来的 keychain 授权框上，最后以 job 超时收场——
    # 已经踩过，所以这里不缩窄。
    security import "$dir/cert.p12" -P "$password" -f pkcs12 -A -k "$KEYCHAIN" >/dev/null \
      || fail "$name 导入失败（密码不对？或者 p12 里只有证书没有私钥？）"
    rm -rf "$dir"
  done

  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null

  # 关键的一道闸：必须在**归档之前**确认 keychain 里确实有可用的签名身份。
  # 自动签名（CODE_SIGN_STYLE=Automatic + -allowProvisioningUpdates）找不到本地
  # 身份时不会报错，而是向 Apple 申请一张新证书；那张证书的私钥随 runner 一起
  # 销毁，永远无法再用，每次跑烧掉一张，直到撞上 Apple 的证书上限
  # （"Your account has reached the maximum number of certificates"）。
  # 这个坑真的踩过：一天之内出现 10 张 "Apple Development: Created via API"。
  local identities
  identities="$(security find-identity -v -p codesigning "$KEYCHAIN")"
  printf '%s\n' "$identities"
  local count
  count="$(printf '%s\n' "$identities" | grep -cE '^[[:space:]]*[0-9]+\) ' || true)"
  [ "$count" -gt 0 ] \
    || fail "keychain 里没有可用的 codesigning 身份：导入的 p12 大概只有证书、没有私钥。自动签名在这种情况下会去 Apple 造一张新证书，那正是这里要挡住的失败模式。"

  # 从 find-identity 的输出里把证书全名抠出来，挑一个导出成 SIGNING_IDENTITY，
  # 让 workflow 用 `CODE_SIGN_IDENTITY="$SIGNING_IDENTITY"` 精确钉住它。
  #
  # 为什么不写死名字：Mac App Store 的 app 证书有新旧两套名字
  # （Apple Distribution ↔ 老的 3rd Party Mac Developer Application），secret
  # 里到底是哪张不该由 workflow 猜。而**不钉住**的后果是把选择权交给 Xcode 的
  # 自动签名：它找不到想要的开发身份就向 Apple 申请一张新的，那张证书的私钥
  # 随 runner 一起销毁，每次跑烧一张，直到撞上账号上限——这个坑真踩过。
  local names picked
  names="$(printf '%s\n' "$identities" | sed -n 's/^[[:space:]]*[0-9]*) [0-9A-Fa-f]\{1,\} "\(.*\)"$/\1/p')"
  picked=""
  if [ ${#expects[@]} -gt 0 ]; then
    local n e
    while IFS= read -r n; do
      for e in "${expects[@]}"; do
        case "$n" in
          *"$e"*)
            picked="$n"
            break 2
            ;;
        esac
      done
    done <<<"$names"
    [ -n "$picked" ] \
      || fail "keychain 里没有名字包含 $(printf '"%s" ' "${expects[@]}")的身份——归档用不上它，Xcode 会转身去 Apple 造一张新的。"
  else
    picked="$(printf '%s\n' "$names" | head -1)"
  fi
  [ -n "$picked" ] || fail "没能从 find-identity 的输出里解析出身份名，无法钉住签名身份。"
  echo "::notice title=选中的签名身份::$picked"

  export_env SIGNING_KEYCHAIN "$KEYCHAIN"
  export_env SIGNING_IDENTITY "$picked"

  if [ -n "${APPLE_API_KEY:-}" ]; then
    [ -n "${APPLE_API_KEY_ID:-}" ] \
      || fail "APPLE_API_KEY_ID 是空的（secret 被设成空值了？）——文件名与 -authenticationKeyID 都会错。"
    mkdir -p "$HOME/private_keys"
    local key="$HOME/private_keys/AuthKey_${APPLE_API_KEY_ID}.p8"
    decode_base64 "$APPLE_API_KEY" >"$key"
    # 立刻验一遍，别让残缺的 base64 在几分钟后以 invalidPEMDocument 的形式暴露
    openssl pkey -in "$key" -noout \
      || fail "APPLE_API_KEY 解出来不是合法的 PKCS#8 私钥（$(wc -c <"$key" | tr -d ' ') 字节）。应该存 p8 文件的 base64（含结尾的 '='），或者直接存 PEM 全文。"
    chmod 600 "$key"
    local size sha
    size="$(wc -c <"$key" | tr -d ' ')"
    sha="$(shasum -a 256 "$key" | cut -c1-12)"
    # 注意这里花括号不能省：macOS 的 bash 3.2 在 UTF-8 locale 下会把紧跟其后的
    # 全角逗号当成变量名的一部分，直接报 `APPLE_API_KEY_ID，: unbound variable`。
    echo "::notice title=ASC API key::${APPLE_API_KEY_ID}，${size} 字节，sha256 ${sha}"
    export_env ASC_KEY_PATH "$key"
    export_env ASC_KEY_ID "$APPLE_API_KEY_ID"
  fi
}

case "${1:-}" in
  setup)
    shift
    setup "$@"
    ;;
  teardown)
    teardown
    ;;
  *)
    fail "用法：$(basename "$0") setup [--expect <身份名片段>] <CERT_ENV_VAR>... | teardown"
    ;;
esac

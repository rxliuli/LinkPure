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
#   Scripts/ci-signing.sh setup [--expect <身份名片段>]... [<CERT_ENV_VAR>...]
#   Scripts/ci-signing.sh teardown
#
# 证书用**环境变量名**传（值由调用方注入，脚本自己不读 secrets），密码按
# `<前缀>_BASE64` → `<前缀>_PASSWORD` 的约定自动推导，正好对上仓库里现有的
# APPLE_CERTIFICATE_{INSTALLER,DEVELOPERID}_{BASE64,PASSWORD}。
# 证书列表可以是空的：上架那条路只需要 ASC API key —— app 的签名身份由
# cloud signing 提供（见 release.yml 里 appstore job 的注释）。
#
# --expect 只在需要**手动指定签名身份**时给（目前只有 Developer ID 那条路）：
# 给了它就会要求 keychain 里存在名字匹配的 codesigning 身份，并把匹配到的全名
# 导出成 SIGNING_IDENTITY，供 `CODE_SIGN_IDENTITY="$SIGNING_IDENTITY"` 用。
#
# setup 结束后向 $GITHUB_ENV（若存在）写入：
#   SIGNING_KEYCHAIN  临时 keychain 的路径
#   SIGNING_IDENTITY  选中的身份全名（只在给了 --expect 时）
#   ASC_KEY_PATH      AuthKey_<keyId>.p8 的路径（没给 APPLE_API_KEY 时为空）
#   ASC_KEY_ID        App Store Connect API key id

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

# 从 p12 里取出证书 PEM。不依赖 keychain 的信任评估，也不依赖我们去猜证书叫什么。
# 末尾的 -legacy 是兜底：老式 PBE 加密的 p12 在 OpenSSL 3 下必须显式打开才读得到。
p12_cert_pem() {
  openssl pkcs12 -in "$1" -passin "pass:$2" -clcerts -nokeys 2>/dev/null \
    || openssl pkcs12 -legacy -in "$1" -passin "pass:$2" -clcerts -nokeys 2>/dev/null \
    || true
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
  if [ ${#certs[@]} -eq 0 ] && [ -z "${APPLE_API_KEY:-}" ]; then
    fail "既没给证书环境变量，也没给 APPLE_API_KEY —— 那这一步只是准备了一个空 keychain"
  fi

  # 同一个 runner 上重跑（或者上一步失败留下的）时先清干净
  security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true
  security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
  # 默认几分钟就会自动锁；这条流水线的 job 最长 60 分钟，锁了必然失败。
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

  local name pw_name value password dir pem subject
  # 用 if 包住而不是直接 for：bash 3.2 在 `set -u` 下展开空数组会报
  # `certs[@]: unbound variable`（bash 4.4 才修）。
  if [ ${#certs[@]} -gt 0 ]; then
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

    # 先用 openssl 从 p12 里把证书本身读出来，查有效期。
    # 过期证书必须当场挡掉：拿它手动签名会失败，而更阴的情况是导出阶段发现本地
    # 没有可用身份，于是转头让 Apple 现造一张——installer 证书的上限只有 3 张。
    # 这个坑真踩过：APPLE_CERTIFICATE_APPSTORE 里那张 Apple Distribution 早已
    # 过期，而流水线一直没发现（旧流程只把 `find-identity -v` 的输出打出来给人看，
    # 没人校验过）。
    pem="$(p12_cert_pem "$dir/cert.p12" "$password")"
    [ -n "$pem" ] || fail "$name 解出来的 p12 里读不到证书（密码不对？或者这根本不是个 p12？）"
    subject="$(printf '%s\n' "$pem" | openssl x509 -noout -subject 2>/dev/null || true)"
    printf '%s\n' "$pem" | openssl x509 -noout -checkend 0 >/dev/null 2>&1 \
      || fail "$name 里的证书已经过期（${subject}）——去 developer.apple.com 重新签发、更新 secret 之后再发版。"
    echo "::notice title=$name::${subject}"

    # 导入的原始输出故意留着不重定向：它只有几行（"1 key imported" /
    # "1 certificate imported"），而一旦后面报错，这几行就是「到底是只有证书
    # 还是没有私钥」的唯一直接证据。
    #
    # -A：允许任何程序使用导入的私钥。这只是一次性 runner 上的一次性 keychain，
    # 保留 -A 是这里的常规做法。extport 那边改成了逐个 -T 点名
    # (codesign/security/productbuild)，少点一个（productbuild 没被信任）会让
    # 它**静默卡在**一个永远弹不出来的 keychain 授权框上，最后以 job 超时收场——
    # 已经踩过，所以这里不缩窄。
    security import "$dir/cert.p12" -P "$password" -f pkcs12 -A -k "$KEYCHAIN" \
      || fail "$name 导入失败（密码不对？或者 p12 里只有证书没有私钥？）"
    rm -rf "$dir"
  done

  # 空 keychain 上跑这条会直接报 “The specified item could not be found”——旧流程
  # 里就犯过这个错（把它放在导入之前）。所以它必须待在这个 if 里面。
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
  fi

  export_env SIGNING_KEYCHAIN "$KEYCHAIN"

  # 只有真的要手动指定签名身份时，才需要 keychain 里有 codesigning 身份。
  # 上架那条路不需要：它归档阶段不签名（macOS 走 ad-hoc 只为把 entitlements 带
  # 进归档），真正的签名在导出阶段由 cloud signing 提供。
  if [ ${#expects[@]} -gt 0 ]; then
    # 注意**不能用 -v**。`-v` 是「只显示 valid 身份」，而 valid 要看证书有没有
    # 过期、信任链能不能跑通——导入到临时 keychain 的 p12 只带叶子证书、缺
    # Apple WWDR 中间证书，valid 就恒为 0，**而 codesign 照样拿它签名**。
    # 旧流程里那条 `find-identity -v` 只是打印给人看、没人校验输出，所以在成功的
    # 发布运行里它写的也是「0 valid identities found」。
    # 不带 -v 时那份 "Matching identities" 才是要的：证书 + 私钥配对、且证书带
    # codeSigning EKU 的全部身份，不要求信任链完整。
    local identities names
    identities="$(security find-identity -p codesigning "$KEYCHAIN")"
    printf '%s\n' "$identities"
    # 抠名字时不能假设行尾就是引号：信任链不完整的身份后面会跟一个
    # `(CSSMERR_TP_NOT_TRUSTED)` 尾巴，所以只取第一对引号里的内容、忽略后缀。
    names="$(printf '%s\n' "$identities" | sed -n 's/^[[:space:]]*[0-9]*) [0-9A-Fa-f]\{1,\} "\([^"]*\)".*$/\1/p')"
    [ -n "$names" ] \
      || fail "keychain 里没有任何证书+私钥配对的身份：导入的 p12 大概只有证书、没有私钥。"

    local picked n e
    picked=""
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
      || fail "keychain 里没有名字包含 $(printf '"%s" ' "${expects[@]}")的身份——签名用不上它，Xcode 会转身去 Apple 造一张新的。"
    echo "::notice title=选中的签名身份::$picked"
    export_env SIGNING_IDENTITY "$picked"
  fi

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
    fail "用法：$(basename "$0") setup [--expect <身份名片段>]... [<CERT_ENV_VAR>...] | teardown"
    ;;
esac

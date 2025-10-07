#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Configuration --------------------------------------------------------------
APP_NAME=${APP_NAME:-"LinkPure"}
BIN_DIR=${BIN_DIR:-"bin"}
APP_PATH=${APP_PATH:-"${BIN_DIR}/${APP_NAME}.app"}
PKG_FILE_NAME=${PKG_FILE_NAME:-"${BIN_DIR}/${APP_NAME}.pkg"}
ENTITLEMENTS=${ENTITLEMENTS:-"build/darwin/entitlements.plist"}

SIGNING_IDENTITY_APP=${SIGNING_IDENTITY_APP:-"Apple Distribution: KAI WANG (N2X78TUUFG)"}
SIGNING_IDENTITY_INSTALLER=${SIGNING_IDENTITY_INSTALLER:-"Apple Distribution: KAI WANG (N2X78TUUFG)"}
TEAM_ID=${TEAM_ID:-"N2X78TUUFG"}
APP_BUNDLE_ID=${APP_BUNDLE_ID:-"com.rxliuli.linkpure2"}
ASC_PROVIDER=${ASC_PROVIDER:-"${TEAM_ID}"}

APPLE_ID=${APPLE_ID:-""}
APP_STORE_CONNECT_PASSWORD=${APP_STORE_CONNECT_PASSWORD:-""}
APP_STORE_CONNECT_KEYCHAIN_ITEM=${APP_STORE_CONNECT_KEYCHAIN_ITEM:-""}
ASC_API_KEY_ID=${ASC_API_KEY_ID:-""}
ASC_API_KEY_ISSUER_ID=${ASC_API_KEY_ISSUER_ID:-""}
ASC_API_KEY_PATH=${ASC_API_KEY_PATH:-""}

# Helpers -------------------------------------------------------------------
log() {
  printf '\n[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

fail() {
  printf '\nERROR: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

require_file() {
  [[ -e "$1" ]] || fail "Required file not found: $1"
}

require_non_empty() {
  local var_name="$1"
  local value="${!var_name:-}" 
  [[ -n "$value" ]] || fail "Environment variable $var_name is required"
}

select_altool_password() {
  if [[ -n "$APP_STORE_CONNECT_PASSWORD" ]]; then
    printf '%s' "$APP_STORE_CONNECT_PASSWORD"
  elif [[ -n "$APP_STORE_CONNECT_KEYCHAIN_ITEM" ]]; then
    printf '@keychain:%s' "$APP_STORE_CONNECT_KEYCHAIN_ITEM"
  else
    fail "Provide either APP_STORE_CONNECT_PASSWORD or APP_STORE_CONNECT_KEYCHAIN_ITEM"
  fi
}

# Pre-flight -----------------------------------------------------------------
log "Checking prerequisites"
require_command task
require_command codesign
require_command productbuild
require_command pkgutil
require_command xcrun

require_file "$ENTITLEMENTS"
require_non_empty SIGNING_IDENTITY_APP
require_non_empty SIGNING_IDENTITY_INSTALLER
require_non_empty TEAM_ID
require_non_empty APP_BUNDLE_ID
ALTOOL_AUTH_ARGS=()

select_altool_auth() {
  if [[ -n "$ASC_API_KEY_ID" ]]; then
    require_non_empty ASC_API_KEY_ISSUER_ID
    local key_path="${ASC_API_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_API_KEY_ID}.p8}"
    require_file "$key_path"
    ALTOOL_AUTH_ARGS=(
      --apiKey "$ASC_API_KEY_ID"
      --apiIssuer "$ASC_API_KEY_ISSUER_ID"
      --private-key-file "$key_path"
    )
  else
    require_non_empty APPLE_ID
    require_non_empty ASC_PROVIDER
    local password
    password=$(select_altool_password)
    ALTOOL_AUTH_ARGS=(
      --username "$APPLE_ID"
      --password "$password"
      --asc-provider "$ASC_PROVIDER"
    )
  fi
}

select_altool_auth

# Build ----------------------------------------------------------------------
log "Building application bundle via task"
task darwin:package:universal

[[ -d "$APP_PATH" ]] || fail "Application bundle not found at $APP_PATH"

# Codesign -------------------------------------------------------------------
log "Signing app bundle with entitlements"
codesign --force --deep --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" \
  --sign "$SIGNING_IDENTITY_APP" \
  "$APP_PATH"

log "Verifying app signature"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

# Package --------------------------------------------------------------------
log "Generating signed installer package"
[[ -f "$PKG_FILE_NAME" ]] && rm -f "$PKG_FILE_NAME"
productbuild \
  --component "$APP_PATH" /Applications \
  --identifier "$APP_BUNDLE_ID" \
  --sign "$SIGNING_IDENTITY_INSTALLER" \
  "$PKG_FILE_NAME"

log "Checking package signature"
pkgutil --check-signature "$PKG_FILE_NAME"

# Upload ---------------------------------------------------------------------
log "Validating package with App Store Connect"
xcrun altool --validate-app \
  --type osx \
  --file "$PKG_FILE_NAME" \
  "${ALTOOL_AUTH_ARGS[@]}"

log "Uploading package to App Store Connect"
xcrun altool --upload-app \
  --type osx \
  --file "$PKG_FILE_NAME" \
  "${ALTOOL_AUTH_ARGS[@]}"

log "Upload submitted. Monitor App Store Connect for processing status."

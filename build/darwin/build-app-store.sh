#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Configuration --------------------------------------------------------------
APP_NAME=${APP_NAME:-""}
BIN_DIR=${BIN_DIR:-""}
ENTITLEMENTS=${ENTITLEMENTS:-"build/darwin/entitlements.plist"}

SIGNING_IDENTITY_APPSTORE=${SIGNING_IDENTITY_APPSTORE:-""}
SIGNING_IDENTITY_INSTALLER=${SIGNING_IDENTITY_INSTALLER:-""}
TEAM_ID=${TEAM_ID:-""}
APP_BUNDLE_ID=${APP_BUNDLE_ID:-""}

# Derived configuration
APP_PATH="${BIN_DIR}/${APP_NAME}.app"
PKG_FILE_NAME="${BIN_DIR}/${APP_NAME}.pkg"
ASC_PROVIDER="${TEAM_ID}"

# API Key configuration (from file path)
APPLE_API_KEY_ID=${APPLE_API_KEY_ID:-""}
APPLE_API_ISSUER=${APPLE_API_ISSUER:-""}
APPLE_API_KEY_PATH=${APPLE_API_KEY_PATH:-""}

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

# Pre-flight -----------------------------------------------------------------
log "Checking prerequisites"
require_command task
require_command codesign
require_command productbuild
require_command pkgutil
require_command xcrun

require_non_empty APP_NAME
require_non_empty BIN_DIR
require_file "$ENTITLEMENTS"
require_non_empty SIGNING_IDENTITY_APPSTORE
require_non_empty SIGNING_IDENTITY_INSTALLER
require_non_empty TEAM_ID
require_non_empty APP_BUNDLE_ID
require_non_empty APPLE_API_KEY_ID
require_non_empty APPLE_API_ISSUER
require_non_empty APPLE_API_KEY_PATH

require_file "$APPLE_API_KEY_PATH"

ALTOOL_AUTH_ARGS=(
  --apiKey "$APPLE_API_KEY_ID"
  --apiIssuer "$APPLE_API_ISSUER"
  --private-key-file "$APPLE_API_KEY_PATH"
)

# Build ----------------------------------------------------------------------
log "Building application bundle via task"
task darwin:package:universal

[[ -d "$APP_PATH" ]] || fail "Application bundle not found at $APP_PATH"

# Codesign -------------------------------------------------------------------
log "Signing app bundle with entitlements"
codesign --force --deep --options runtime --timestamp \
  --entitlements "$ENTITLEMENTS" \
  --sign "$SIGNING_IDENTITY_APPSTORE" \
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

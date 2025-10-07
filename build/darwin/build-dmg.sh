#!/usr/bin/env bash
set -e

# Configuration
APP_NAME="${APP_NAME:-}"
BIN_DIR="${BIN_DIR:-}"
SIGNING_IDENTITY_DMG="${SIGNING_IDENTITY_DMG:-}"
TEAM_ID="${TEAM_ID:-}"

# Validation
[[ -z "$APP_NAME" ]] && { echo "ERROR: APP_NAME is required"; exit 1; }
[[ -z "$BIN_DIR" ]] && { echo "ERROR: BIN_DIR is required"; exit 1; }
[[ -z "$SIGNING_IDENTITY_DMG" ]] && { echo "ERROR: SIGNING_IDENTITY_DMG is required"; exit 1; }
[[ -z "$TEAM_ID" ]] && { echo "ERROR: TEAM_ID is required"; exit 1; }

DMG_FILE_NAME="${BIN_DIR}/${APP_NAME}-Installer.dmg"
VOLUME_NAME="${APP_NAME} Installer"
APP_PATH="${BIN_DIR}/${APP_NAME}.app"

# API Key configuration (from base64)
APPLE_API_KEY_ID="${APPLE_API_KEY_ID:-}"
APPLE_API_ISSUER="${APPLE_API_ISSUER:-}"
APPLE_API_KEY="${APPLE_API_KEY:-}"

# Certificate configuration (from base64)
APPLE_CERTIFICATE_BASE64="${APPLE_CERTIFICATE_BASE64:-}"
APPLE_CERTIFICATE_PASSWORD="${APPLE_CERTIFICATE_PASSWORD:-}"

# Decode and setup API key if provided
TEMP_API_KEY_PATH=""
if [[ -n "$APPLE_API_KEY" ]]; then
  TEMP_API_KEY_PATH=$(mktemp)
  echo "$APPLE_API_KEY" | base64 --decode > "$TEMP_API_KEY_PATH"
  trap "rm -f $TEMP_API_KEY_PATH" EXIT
fi

# Decode and import certificate if provided
if [[ -n "$APPLE_CERTIFICATE_BASE64" && -n "$APPLE_CERTIFICATE_PASSWORD" ]]; then
  TEMP_CERT_PATH=$(mktemp)
  TEMP_KEYCHAIN_PATH=$(mktemp -d)/build.keychain
  echo "$APPLE_CERTIFICATE_BASE64" | base64 --decode > "$TEMP_CERT_PATH"

  # Create temporary keychain
  security create-keychain -p actions "$TEMP_KEYCHAIN_PATH"
  security set-keychain-settings -lut 21600 "$TEMP_KEYCHAIN_PATH"
  security unlock-keychain -p actions "$TEMP_KEYCHAIN_PATH"

  # Import certificate
  security import "$TEMP_CERT_PATH" -P "$APPLE_CERTIFICATE_PASSWORD" -A -t cert -f pkcs12 -k "$TEMP_KEYCHAIN_PATH"
  security list-keychain -d user -s "$TEMP_KEYCHAIN_PATH"

  trap "security delete-keychain $TEMP_KEYCHAIN_PATH 2>/dev/null || true; rm -f $TEMP_CERT_PATH $TEMP_API_KEY_PATH 2>/dev/null || true" EXIT
fi

# Build the application
task package

# Sign the application bundle
echo "Signing the application..."
codesign --force --options runtime --timestamp \
  --sign "${SIGNING_IDENTITY_DMG}" \
  "${APP_PATH}/Contents/MacOS/${APP_NAME}"
codesign --force --options runtime --timestamp \
  --sign "${SIGNING_IDENTITY_DMG}" \
  "${APP_PATH}"

# Verify the signature
echo "Verifying the application signature..."
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"

# Create the DMG
[[ -f "${DMG_FILE_NAME}" ]] && rm "${DMG_FILE_NAME}"
echo "Creating DMG..."
/opt/homebrew/bin/create-dmg \
  --volname "${VOLUME_NAME}" \
  --window-pos 200 120 \
  --window-size 800 400 \
  --icon-size 100 \
  --icon "${APP_NAME}.app" 200 190 \
  --hide-extension "${APP_NAME}.app" \
  --app-drop-link 600 185 \
  "${DMG_FILE_NAME}" \
  "${APP_PATH}"

# Sign the DMG
echo "Signing DMG..."
codesign --force --sign "${SIGNING_IDENTITY_DMG}" "${DMG_FILE_NAME}"

# Submit for notarization
echo "Submitting for notarization..."
if [[ -n "$APPLE_API_KEY_ID" && -n "$APPLE_API_ISSUER" && -n "$TEMP_API_KEY_PATH" ]]; then
  xcrun notarytool submit "${DMG_FILE_NAME}" \
    --key "$TEMP_API_KEY_PATH" \
    --key-id "$APPLE_API_KEY_ID" \
    --issuer "$APPLE_API_ISSUER" \
    --wait
else
  echo "ERROR: APPLE_API_KEY_ID, APPLE_API_ISSUER, and APPLE_API_KEY are required for notarization"
  exit 1
fi

# Staple the notarization ticket
echo "Stapling notarization ticket..."
xcrun stapler staple "${DMG_FILE_NAME}"

# Verify notarization
echo "Verifying notarization..."
spctl -a -t open --context context:primary-signature -v "${DMG_FILE_NAME}"

echo "Build completed successfully!"
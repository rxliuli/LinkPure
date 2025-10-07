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

# API Key configuration (from file path)
APPLE_API_KEY_ID="${APPLE_API_KEY_ID:-}"
APPLE_API_ISSUER="${APPLE_API_ISSUER:-}"
APPLE_API_KEY_PATH="${APPLE_API_KEY_PATH:-}"

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
if [[ -n "$APPLE_API_KEY_ID" && -n "$APPLE_API_ISSUER" && -n "$APPLE_API_KEY_PATH" ]]; then
  xcrun notarytool submit "${DMG_FILE_NAME}" \
    --key "$APPLE_API_KEY_PATH" \
    --key-id "$APPLE_API_KEY_ID" \
    --issuer "$APPLE_API_ISSUER" \
    --wait
else
  echo "ERROR: APPLE_API_KEY_ID, APPLE_API_ISSUER, and APPLE_API_KEY_PATH are required for notarization"
  exit 1
fi

# Staple the notarization ticket
echo "Stapling notarization ticket..."
xcrun stapler staple "${DMG_FILE_NAME}"

# Verify notarization
echo "Verifying notarization..."
spctl -a -t open --context context:primary-signature -v "${DMG_FILE_NAME}"

echo "Build completed successfully!"
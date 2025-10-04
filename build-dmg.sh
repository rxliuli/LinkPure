#!/usr/bin/env bash
set -e

APP_NAME="LinkPure"
BIN_DIR="bin"
DMG_FILE_NAME="${BIN_DIR}/${APP_NAME}-Installer.dmg"
VOLUME_NAME="${APP_NAME} Installer"
APP_PATH="${BIN_DIR}/${APP_NAME}.app"
SIGNING_IDENTITY="Developer ID Application: KAI WANG (N2X78TUUFG)"
TEAM_ID="N2X78TUUFG"
KEYCHAIN_PROFILE="LinkPure"

# Build the application
task package

# Sign the application bundle
echo "Signing the application..."
codesign --force --options runtime --timestamp \
  --sign "${SIGNING_IDENTITY}" \
  "${APP_PATH}/Contents/MacOS/${APP_NAME}"
codesign --force --options runtime --timestamp \
  --sign "${SIGNING_IDENTITY}" \
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
codesign --force --sign "${SIGNING_IDENTITY}" "${DMG_FILE_NAME}"

# Submit for notarization
echo "Submitting for notarization..."
xcrun notarytool submit "${DMG_FILE_NAME}" \
  --keychain-profile "${KEYCHAIN_PROFILE}" \
  --wait

# Staple the notarization ticket
echo "Stapling notarization ticket..."
xcrun stapler staple "${DMG_FILE_NAME}"

# Verify notarization
echo "Verifying notarization..."
spctl -a -t open --context context:primary-signature -v "${DMG_FILE_NAME}"

echo "Build completed successfully!"
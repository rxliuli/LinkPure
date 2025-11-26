; LinkPure Windows Installer Script
; Requires NSIS 3.x

!include "MUI2.nsh"

; General
Name "LinkPure"
OutFile "..\LinkPure-windows-x64-installer.exe"
InstallDir "$LOCALAPPDATA\LinkPure"
InstallDirRegKey HKCU "Software\LinkPure" "InstallDir"
RequestExecutionLevel user

; Version info
!ifdef VERSION
  VIProductVersion "${VERSION}.0"
  VIAddVersionKey "ProductName" "LinkPure"
  VIAddVersionKey "ProductVersion" "${VERSION}"
  VIAddVersionKey "FileVersion" "${VERSION}"
  VIAddVersionKey "FileDescription" "LinkPure - URL Cleaner"
  VIAddVersionKey "LegalCopyright" "rxliuli"
!endif

; UI Settings
!define MUI_ABORTWARNING
!define MUI_ICON "runner\resources\app_icon.ico"
!define MUI_UNICON "runner\resources\app_icon.ico"

; Pages
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES

; Languages
!insertmacro MUI_LANGUAGE "English"
!insertmacro MUI_LANGUAGE "SimpChinese"

; Installer Section
Section "Install"
  SetOutPath "$INSTDIR"
  
  ; Copy all files from the Flutter build
  File /r "..\build\windows\x64\runner\Release\*.*"
  
  ; Create uninstaller
  WriteUninstaller "$INSTDIR\uninstall.exe"
  
  ; Create Start Menu shortcuts
  CreateDirectory "$SMPROGRAMS\LinkPure"
  CreateShortcut "$SMPROGRAMS\LinkPure\LinkPure.lnk" "$INSTDIR\LinkPure.exe"
  CreateShortcut "$SMPROGRAMS\LinkPure\Uninstall.lnk" "$INSTDIR\uninstall.exe"
  
  ; Create Desktop shortcut
  CreateShortcut "$DESKTOP\LinkPure.lnk" "$INSTDIR\LinkPure.exe"
  
  ; Write registry keys for uninstaller
  WriteRegStr HKCU "Software\LinkPure" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\LinkPure" "DisplayName" "LinkPure"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\LinkPure" "UninstallString" "$INSTDIR\uninstall.exe"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\LinkPure" "DisplayIcon" "$INSTDIR\LinkPure.exe"
  WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\LinkPure" "Publisher" "rxliuli"
  !ifdef VERSION
    WriteRegStr HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\LinkPure" "DisplayVersion" "${VERSION}"
  !endif
SectionEnd

; Uninstaller Section
Section "Uninstall"
  ; Remove files
  RMDir /r "$INSTDIR"
  
  ; Remove Start Menu shortcuts
  RMDir /r "$SMPROGRAMS\LinkPure"
  
  ; Remove Desktop shortcut
  Delete "$DESKTOP\LinkPure.lnk"
  
  ; Remove registry keys
  DeleteRegKey HKCU "Software\LinkPure"
  DeleteRegKey HKCU "Software\Microsoft\Windows\CurrentVersion\Uninstall\LinkPure"
SectionEnd

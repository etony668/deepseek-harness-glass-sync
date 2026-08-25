Unicode True
RequestExecutionLevel user
SetCompressor /SOLID lzma
SetDatablockOptimize on
ShowInstDetails show
ShowUnInstDetails show

!ifndef APP_SOURCE
  !error "APP_SOURCE is required"
!endif
!ifndef PRODUCT_VERSION
  !error "PRODUCT_VERSION is required"
!endif
!ifndef OUTPUT_FILE
  !error "OUTPUT_FILE is required"
!endif

Name "DeepSeek Harness Glass ${PRODUCT_VERSION}"
OutFile "${OUTPUT_FILE}"
InstallDir "$LOCALAPPDATA\Programs\DeepSeek Harness Glass"

Page directory
Page instfiles
UninstPage uninstConfirm
UninstPage instfiles

Section "DeepSeek Harness Glass"
  SetOutPath "$INSTDIR"
  File /r "${APP_SOURCE}\*"

  WriteUninstaller "$INSTDIR\Uninstall DeepSeek Harness Glass.exe"

  CreateDirectory "$SMPROGRAMS\DeepSeek Harness Glass"
  CreateShortcut "$SMPROGRAMS\DeepSeek Harness Glass\DeepSeek Harness Glass.lnk" "$INSTDIR\DeepSeekHarnessGlass.exe"
  CreateShortcut "$SMPROGRAMS\DeepSeek Harness Glass\Uninstall DeepSeek Harness Glass.lnk" "$INSTDIR\Uninstall DeepSeek Harness Glass.exe"
SectionEnd

Section "Uninstall"
  Delete "$SMPROGRAMS\DeepSeek Harness Glass\DeepSeek Harness Glass.lnk"
  Delete "$SMPROGRAMS\DeepSeek Harness Glass\Uninstall DeepSeek Harness Glass.lnk"
  RMDir "$SMPROGRAMS\DeepSeek Harness Glass"
  RMDir /r "$INSTDIR"
SectionEnd

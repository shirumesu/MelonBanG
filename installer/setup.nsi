; Bootstrapper for the Flutter installer. It shows no UI of its own: it
; unpacks the installer and the program archive into a temporary directory,
; runs the installer and removes both when it closes.
;
;   makensis /DVERSION=<x.y.z[-pre]> /DNUMERIC_VERSION=<x.y.z.0>
;            /DSETUP_DIR=<installer build> /DPAYLOAD=<program zip>
;            /DOUTFILE=<setup exe> setup.nsi
Unicode true
SetCompressor lzma
RequestExecutionLevel user
SilentInstall silent
Name "MelonBanG"
OutFile "${OUTFILE}"
Icon "..\windows\runner\resources\app_icon.ico"

VIProductVersion "${NUMERIC_VERSION}"
VIAddVersionKey "ProductName" "MelonBanG"
VIAddVersionKey "FileDescription" "MelonBanG Setup"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "LegalCopyright" "Copyright (C) 2026 MelonBanG contributors. Licensed under GPL-3.0."

Section
  InitPluginsDir
  SetOutPath "$PLUGINSDIR\setup"
  File /r "${SETUP_DIR}\*"
  SetOutPath "$PLUGINSDIR"
  ; Already compressed; storing it keeps start-up quick.
  SetCompress off
  File "/oname=payload.zip" "${PAYLOAD}"
  SetCompress auto
  ExecWait '"$PLUGINSDIR\setup\melonbang_setup.exe" --payload "$PLUGINSDIR\payload.zip"' $0
  ; Leave the temporary directory so it can be removed.
  SetOutPath "$TEMP"
  SetErrorLevel $0
SectionEnd

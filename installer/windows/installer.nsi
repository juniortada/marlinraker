Unicode true
!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "x64.nsh"

!define APP_NAME "Marlinraker Desktop"
!define APP_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\MarlinrakerDesktop"
!define POWERSHELL "$SYSDIR\WindowsPowerShell\v1.0\powershell.exe"
!define LAUNCH_ARGS '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "$INSTDIR\marlinraker.ps1"'
!define DOCKER_DESKTOP "$PROGRAMFILES64\Docker\Docker\Docker Desktop.exe"
!define USBIPD "$PROGRAMFILES64\usbipd-win\usbipd.exe"

Name "${APP_NAME}"
OutFile "${OUTFILE}"
InstallDir "$PROGRAMFILES64\Marlinraker Desktop"
RequestExecutionLevel admin
SetCompressor /SOLID lzma
BrandingText "${APP_NAME} ${VERSION}"

!define MUI_ICON "marlinraker-desktop.ico"
!define MUI_UNICON "marlinraker-desktop.ico"
!define MUI_ABORTWARNING
!define MUI_WELCOMEPAGE_TEXT "Este assistente instala o Marlinraker com o Mainsail para usar uma impressora Marlin conectada por USB na OrcaSlicer.$\r$\n$\r$\nO Marlinraker roda no Docker Desktop e o cabo USB é repassado ao Docker pelo usbipd-win. Os dois são verificados durante a instalação.$\r$\n$\r$\nDepois, abra a OrcaSlicer pelo atalho $\"OrcaSlicer + Marlinraker$\" e use http://localhost:7125 como impressora OctoPrint."

!insertmacro MUI_PAGE_WELCOME
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "PortugueseBR"

Function .onInit
    ${IfNot} ${RunningX64}
        MessageBox MB_ICONSTOP "O ${APP_NAME} precisa do Windows 64 bits."
        Abort
    ${EndIf}
    SetRegView 64
FunctionEnd

Function un.onInit
    SetRegView 64
FunctionEnd

Function InstallWithWinget
    Pop $1
    Pop $0
    DetailPrint "Instalando $1 com o winget..."
    nsExec::ExecToLog 'winget install --exact --id $0 --silent --accept-package-agreements --accept-source-agreements'
    Pop $2
    Push $2
FunctionEnd

Function EnsureDockerDesktop
    ${If} ${FileExists} "${DOCKER_DESKTOP}"
        DetailPrint "Docker Desktop encontrado."
        Return
    ${EndIf}
    MessageBox MB_YESNO|MB_ICONQUESTION "O Docker Desktop é necessário e não foi encontrado.$\r$\n$\r$\nInstalar agora com o winget?" IDNO open_page
    Push "Docker.DockerDesktop"
    Push "o Docker Desktop"
    Call InstallWithWinget
    Pop $0
    ${If} $0 == 0
        MessageBox MB_ICONINFORMATION "Docker Desktop instalado. Abra o Docker Desktop uma vez para concluir a configuração dele (pode pedir para reiniciar o Windows)."
        Return
    ${EndIf}
    open_page:
    MessageBox MB_ICONINFORMATION "Instale o Docker Desktop pela página que vai abrir. O ${APP_NAME} continua instalado e passa a funcionar quando o Docker estiver pronto."
    ExecShell "open" "https://www.docker.com/products/docker-desktop/"
FunctionEnd

Function EnsureUsbipd
    ${If} ${FileExists} "${USBIPD}"
        DetailPrint "usbipd-win encontrado."
        Return
    ${EndIf}
    Push "dorssel.usbipd-win"
    Push "o usbipd-win"
    Call InstallWithWinget
    Pop $0
    ${If} $0 == 0
        Return
    ${EndIf}
    MessageBox MB_ICONINFORMATION "Não consegui instalar o usbipd-win automaticamente. Instale pela página que vai abrir (arquivo .msi)."
    ExecShell "open" "https://github.com/dorssel/usbipd-win/releases/latest"
FunctionEnd

Function ReportOrcaSlicer
    nsExec::ExecToStack '"${POWERSHELL}" -NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\marlinraker.ps1" find-orca'
    Pop $0
    Pop $1
    ${If} $0 == 0
        DetailPrint "OrcaSlicer encontrada: $1"
    ${Else}
        MessageBox MB_ICONINFORMATION "A OrcaSlicer não foi encontrada neste computador. Instale a OrcaSlicer quando quiser: o atalho $\"OrcaSlicer + Marlinraker$\" vai encontrá-la sozinho."
    ${EndIf}
FunctionEnd

Section "Instalar"
    SetShellVarContext all
    SetOutPath "$INSTDIR"
    File "marlinraker.ps1"
    File "MarlinrakerDesktop.psm1"
    File "docker-compose.yml"
    File "IMAGE"
    File "marlinraker-image.tar.gz"
    File "marlinraker-desktop.ico"

    Call EnsureDockerDesktop
    Call EnsureUsbipd

    CreateDirectory "$SMPROGRAMS\Marlinraker"
    CreateShortCut "$SMPROGRAMS\Marlinraker\OrcaSlicer + Marlinraker.lnk" "${POWERSHELL}" '${LAUNCH_ARGS} orca' "$INSTDIR\marlinraker-desktop.ico" 0 SW_SHOWMINIMIZED
    CreateShortCut "$SMPROGRAMS\Marlinraker\Marlinraker (Mainsail).lnk" "${POWERSHELL}" '${LAUNCH_ARGS} mainsail' "$INSTDIR\marlinraker-desktop.ico" 0 SW_SHOWMINIMIZED
    CreateShortCut "$SMPROGRAMS\Marlinraker\Parar Marlinraker.lnk" "${POWERSHELL}" '${LAUNCH_ARGS} stop' "$INSTDIR\marlinraker-desktop.ico" 0 SW_SHOWMINIMIZED
    CreateShortCut "$SMPROGRAMS\Marlinraker\Desinstalar Marlinraker Desktop.lnk" "$INSTDIR\uninstall.exe"
    CreateShortCut "$DESKTOP\OrcaSlicer + Marlinraker.lnk" "${POWERSHELL}" '${LAUNCH_ARGS} orca' "$INSTDIR\marlinraker-desktop.ico" 0 SW_SHOWMINIMIZED

    WriteUninstaller "$INSTDIR\uninstall.exe"
    WriteRegStr HKLM "${APP_KEY}" "DisplayName" "${APP_NAME}"
    WriteRegStr HKLM "${APP_KEY}" "DisplayVersion" "${VERSION}"
    WriteRegStr HKLM "${APP_KEY}" "Publisher" "Marlinraker"
    WriteRegStr HKLM "${APP_KEY}" "InstallLocation" "$INSTDIR"
    WriteRegStr HKLM "${APP_KEY}" "DisplayIcon" "$INSTDIR\marlinraker-desktop.ico"
    WriteRegStr HKLM "${APP_KEY}" "UninstallString" '"$INSTDIR\uninstall.exe"'
    WriteRegDWORD HKLM "${APP_KEY}" "NoModify" 1
    WriteRegDWORD HKLM "${APP_KEY}" "NoRepair" 1

    Call ReportOrcaSlicer
SectionEnd

Section "Uninstall"
    SetShellVarContext all
    StrCpy $1 ""
    MessageBox MB_YESNO|MB_ICONQUESTION "Apagar também a configuração, os arquivos G-code e o histórico do Marlinraker?" IDNO keep_data
    StrCpy $1 "-RemoveData"
    keep_data:
    nsExec::ExecToLog '"${POWERSHELL}" -NoProfile -ExecutionPolicy Bypass -File "$INSTDIR\marlinraker.ps1" uninstall $1'
    Pop $0
    ${If} $0 == 2
        MessageBox MB_ICONSTOP "Há uma impressão em andamento no Marlinraker. Desinstale quando ela terminar."
        Abort
    ${EndIf}

    Delete "$DESKTOP\OrcaSlicer + Marlinraker.lnk"
    RMDir /r "$SMPROGRAMS\Marlinraker"
    Delete "$INSTDIR\marlinraker.ps1"
    Delete "$INSTDIR\MarlinrakerDesktop.psm1"
    Delete "$INSTDIR\docker-compose.yml"
    Delete "$INSTDIR\IMAGE"
    Delete "$INSTDIR\marlinraker-image.tar.gz"
    Delete "$INSTDIR\marlinraker-desktop.ico"
    Delete "$INSTDIR\uninstall.exe"
    RMDir "$INSTDIR"
    DeleteRegKey HKLM "${APP_KEY}"
SectionEnd

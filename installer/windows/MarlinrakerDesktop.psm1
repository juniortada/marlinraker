$script:ApiUrl = 'http://127.0.0.1:7125'
$script:MainsailUrl = 'http://localhost:7125/'
$script:OrcaExecutablePattern = '^orca[-_ ]?slicer\.exe$'
$script:SerialDescriptionPattern = '\(COM\d+\)'
$script:VolumeName = 'marlinraker-desktop_marlinraker_files'
$script:SettingsPath = Join-Path $env:APPDATA 'Marlinraker Desktop\settings.json'

function Join-WindowsPath {
    param([string] $Base, [string] $Child)
    return $Base.TrimEnd('\', '/') + '\' + $Child
}

function Get-StartMenuShortcutTarget {
    $folders = @(
        (Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs'),
        (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs')
    )
    $shell = New-Object -ComObject WScript.Shell
    foreach ($folder in $folders) {
        Get-ChildItem -Path $folder -Filter '*.lnk' -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.BaseName -match 'Orca' -and $_.BaseName -notmatch 'Marlinraker' } |
            ForEach-Object { $shell.CreateShortcut($_.FullName).TargetPath }
    }
}

function Get-PortableOrcaSlicerPath {
    $folders = @('Downloads', 'Desktop', 'Documents') | ForEach-Object { Join-Path $env:USERPROFILE $_ }
    foreach ($folder in $folders) {
        Get-ChildItem -Path $folder -Filter 'orca-slicer.exe' -Recurse -Depth 3 -ErrorAction SilentlyContinue |
            ForEach-Object { $_.FullName }
    }
}

function Get-OrcaSlicerCandidatePath {
    $uninstallKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($key in $uninstallKeys) {
        Get-ItemProperty -Path $key -ErrorAction SilentlyContinue |
            Where-Object { $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -match 'Orca\s*Slicer' } |
            ForEach-Object {
                if ($_.PSObject.Properties['InstallLocation'] -and $_.InstallLocation) {
                    Join-WindowsPath $_.InstallLocation 'orca-slicer.exe'
                }
                if ($_.PSObject.Properties['DisplayIcon'] -and $_.DisplayIcon) {
                    ($_.DisplayIcon -split ',')[0].Trim('"')
                }
            }
    }

    $appPathKeys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\orca-slicer.exe',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\orca-slicer.exe'
    )
    foreach ($key in $appPathKeys) {
        $appPath = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
        if ($appPath -and $appPath.PSObject.Properties['(default)']) {
            $appPath.'(default)'
        }
    }

    $bases = @($env:ProgramFiles, ${env:ProgramFiles(x86)})
    if ($env:LOCALAPPDATA) {
        $bases += Join-Path $env:LOCALAPPDATA 'Programs'
    }
    foreach ($base in $bases) {
        if ($base) {
            Join-WindowsPath $base 'OrcaSlicer\orca-slicer.exe'
        }
    }

    Get-StartMenuShortcutTarget
    Get-PortableOrcaSlicerPath
}

function Find-OrcaSlicer {
    Get-OrcaSlicerCandidatePath |
        Where-Object { $_ -and ((($_ -split '[\\/]') | Select-Object -Last 1) -match $script:OrcaExecutablePattern) } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1
}

function ConvertTo-PrinterDevice {
    param([Parameter(ValueFromPipeline = $true)] $Device)
    process {
        if (-not $Device -or $Device.Description -notmatch $script:SerialDescriptionPattern) { return }
        if ($Device.InstanceId -notmatch 'VID_([0-9A-Fa-f]{4})&PID_([0-9A-Fa-f]{4})') { return }
        [pscustomobject]@{
            HardwareId  = ('{0}:{1}' -f $Matches[1], $Matches[2]).ToLowerInvariant()
            BusId       = $Device.BusId
            Description = $Device.Description
            IsBound     = [bool]$Device.PersistedGuid
            IsAttached  = [bool]$Device.ClientIPAddress
        }
    }
}

function Get-PrinterDevice {
    param([string] $StateJson)
    if (-not $StateJson) { return }
    ($StateJson | ConvertFrom-Json).Devices | ConvertTo-PrinterDevice
}

function Select-PrinterDevice {
    param($Devices, [string] $SavedHardwareId)
    $all = @($Devices | Where-Object { $_ })
    if ($SavedHardwareId) {
        $saved = $all | Where-Object { $_.HardwareId -eq $SavedHardwareId } | Select-Object -First 1
        if ($saved) { return $saved }
    }
    $connected = @($all | Where-Object { $_.BusId })
    if ($connected.Count -eq 1) { return $connected[0] }
    if ($connected.Count -gt 1) {
        return $connected | Out-GridView -Title 'Escolha a porta USB da impressora' -OutputMode Single
    }
    return $null
}

function Test-NeedsReconnect {
    param($PrinterInfo)
    return [bool]($PrinterInfo -and $PrinterInfo.state -eq 'error' -and $PrinterInfo.state_message -eq 'Cannot connect to printer')
}

function Test-PrintInProgress {
    param([string] $State)
    return @('printing', 'paused') -contains $State
}

function Get-Setting {
    param([string] $Path = $script:SettingsPath)
    if (Test-Path -LiteralPath $Path) {
        return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    }
    return [pscustomobject]@{ HardwareId = $null }
}

function Save-Setting {
    param($Settings, [string] $Path = $script:SettingsPath)
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $Settings | ConvertTo-Json | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-ToolPath {
    param([string] $Name, [string] $Fallback)
    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    if ($Fallback -and (Test-Path -LiteralPath $Fallback)) { return $Fallback }
    return $null
}

function Get-DockerPath {
    Get-ToolPath -Name 'docker.exe' -Fallback (Join-Path $env:ProgramFiles 'Docker\Docker\resources\bin\docker.exe')
}

function Get-UsbipdPath {
    Get-ToolPath -Name 'usbipd.exe' -Fallback (Join-Path $env:ProgramFiles 'usbipd-win\usbipd.exe')
}

function Test-DockerReady {
    param([string] $Docker)
    & $Docker info *> $null
    return $LASTEXITCODE -eq 0
}

function Wait-DockerReady {
    param([string] $Docker, [int] $TimeoutSeconds = 180)
    if (Test-DockerReady -Docker $Docker) { return $true }
    $desktop = Join-Path $env:ProgramFiles 'Docker\Docker\Docker Desktop.exe'
    if (Test-Path -LiteralPath $desktop) {
        Start-Process -FilePath $desktop
    }
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 3
        if (Test-DockerReady -Docker $Docker) { return $true }
    }
    return $false
}

function Initialize-MarlinrakerImage {
    param([string] $Docker, [string] $Image, [string] $Archive)
    & $Docker image inspect $Image *> $null
    if ($LASTEXITCODE -eq 0) { return $true }
    & $Docker load -i $Archive *> $null
    return $LASTEXITCODE -eq 0
}

function Get-SerialDeviceInDocker {
    param([string] $Docker, [string] $Image)
    $shellScript = 'for d in /dev/ttyUSB* /dev/ttyACM*; do [ -e "$d" ] && chmod 666 "$d" && echo "$d"; done; true'
    $output = & $Docker run --rm -u 0 --privileged -v /dev:/dev --entrypoint sh $Image -c $shellScript 2> $null
    return @($output | Where-Object { $_ })
}

function Test-UsbipdAutoAttachRunning {
    param([string] $HardwareId)
    $processes = Get-CimInstance -ClassName Win32_Process -Filter "Name = 'usbipd.exe'" -ErrorAction SilentlyContinue
    return [bool]($processes | Where-Object { $_.CommandLine -match 'attach' -and $_.CommandLine -match [regex]::Escape($HardwareId) })
}

function Stop-UsbipdAutoAttach {
    param([string] $HardwareId)
    Get-CimInstance -ClassName Win32_Process -Filter "Name = 'usbipd.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match 'attach' -and $_.CommandLine -match [regex]::Escape($HardwareId) } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

function Connect-PrinterUsb {
    param([string] $Docker, [string] $Image, [scriptblock] $Notify)
    $usbipd = Get-UsbipdPath
    if (-not $usbipd) {
        & $Notify 'O usbipd-win não está instalado, então o Marlinraker não consegue ver a impressora USB. Reinstale o Marlinraker Desktop ou instale o usbipd-win.'
        return $false
    }
    $settings = Get-Setting
    $device = Select-PrinterDevice -Devices (Get-PrinterDevice -StateJson ((& $usbipd state 2> $null) -join "`n")) -SavedHardwareId $settings.HardwareId
    if (-not $device) {
        & $Notify 'Nenhuma impressora USB encontrada. Conecte a impressora e abra o atalho de novo.'
        return $false
    }
    if ($device.HardwareId -ne $settings.HardwareId) {
        Save-Setting -Settings ([pscustomobject]@{ HardwareId = $device.HardwareId })
    }
    if (-not $device.IsBound) {
        Start-Process -FilePath $usbipd -ArgumentList @('bind', '--hardware-id', $device.HardwareId) -Verb RunAs -Wait -WindowStyle Hidden
    }
    if (-not (Test-UsbipdAutoAttachRunning -HardwareId $device.HardwareId)) {
        Start-Process -FilePath $usbipd -ArgumentList @('attach', '--wsl', '--hardware-id', $device.HardwareId, '--auto-attach') -WindowStyle Hidden
    }
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadline) {
        if ((Get-SerialDeviceInDocker -Docker $Docker -Image $Image).Count -gt 0) { return $true }
        Start-Sleep -Seconds 2
    }
    & $Notify "A impressora ($($device.Description)) não apareceu no Docker. Desconecte e conecte o cabo USB e abra o atalho de novo."
    return $false
}

function Invoke-Compose {
    param([string] $Docker, [string] $ComposeFile, [string[]] $Arguments)
    & $Docker compose -f $ComposeFile @Arguments *> $null
    return $LASTEXITCODE -eq 0
}

function Get-PrinterInfo {
    try {
        return (Invoke-RestMethod -Uri "$script:ApiUrl/printer/info" -TimeoutSec 3).result
    } catch {
        return $null
    }
}

function Wait-MarlinrakerApi {
    param([int] $TimeoutSeconds = 60)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $info = Get-PrinterInfo
        if ($info) { return $info }
        Start-Sleep -Seconds 2
    }
    return $null
}

function Test-MarlinrakerPrinting {
    try {
        $query = Invoke-RestMethod -Uri "$script:ApiUrl/printer/objects/query?print_stats=state" -TimeoutSec 3
        return Test-PrintInProgress -State $query.result.status.print_stats.state
    } catch {
        return $false
    }
}

function Start-Marlinraker {
    param([string] $InstallDir, [scriptblock] $Notify)
    $docker = Get-DockerPath
    if (-not $docker) {
        & $Notify 'O Docker Desktop não foi encontrado. Instale o Docker Desktop e abra o atalho de novo.'
        return $false
    }
    if (-not (Wait-DockerReady -Docker $docker)) {
        & $Notify 'O Docker Desktop não ficou pronto a tempo. Abra o Docker Desktop, espere ele iniciar e tente de novo.'
        return $false
    }
    $image = (Get-Content -LiteralPath (Join-Path $InstallDir 'IMAGE') -Raw).Trim()
    if (-not (Initialize-MarlinrakerImage -Docker $docker -Image $image -Archive (Join-Path $InstallDir 'marlinraker-image.tar.gz'))) {
        & $Notify 'Não consegui carregar a imagem do Marlinraker no Docker.'
        return $false
    }
    Connect-PrinterUsb -Docker $docker -Image $image -Notify $Notify | Out-Null
    $composeFile = Join-Path $InstallDir 'docker-compose.yml'
    $started = Invoke-Compose -Docker $docker -ComposeFile $composeFile -Arguments @('start', 'marlinraker')
    if (-not $started) {
        $started = Invoke-Compose -Docker $docker -ComposeFile $composeFile -Arguments @('up', '-d', '--no-build', 'marlinraker')
    }
    if (-not $started) {
        & $Notify 'Não consegui iniciar o Marlinraker no Docker.'
        return $false
    }
    $info = Wait-MarlinrakerApi
    if (Test-NeedsReconnect -PrinterInfo $info) {
        try {
            Invoke-RestMethod -Method Post -Uri "$script:ApiUrl/printer/firmware_restart" -TimeoutSec 5 | Out-Null
        } catch {
            return $true
        }
    }
    return $true
}

function Stop-Marlinraker {
    param([string] $InstallDir, [switch] $Force)
    $docker = Get-DockerPath
    if (-not $docker -or -not (Test-DockerReady -Docker $docker)) { return 0 }
    if (-not $Force -and (Test-MarlinrakerPrinting)) { return 2 }
    Invoke-Compose -Docker $docker -ComposeFile (Join-Path $InstallDir 'docker-compose.yml') -Arguments @('stop', 'marlinraker') | Out-Null
    $settings = Get-Setting
    $usbipd = Get-UsbipdPath
    if ($settings.HardwareId -and $usbipd) {
        Stop-UsbipdAutoAttach -HardwareId $settings.HardwareId
        & $usbipd detach --hardware-id $settings.HardwareId *> $null
    }
    return 0
}

function Uninstall-Marlinraker {
    param([string] $InstallDir, [switch] $RemoveData)
    $docker = Get-DockerPath
    if ($docker -and (Test-DockerReady -Docker $docker)) {
        if (Test-MarlinrakerPrinting) { return 2 }
        Invoke-Compose -Docker $docker -ComposeFile (Join-Path $InstallDir 'docker-compose.yml') -Arguments @('down') | Out-Null
        if ($RemoveData) {
            & $docker volume rm $script:VolumeName *> $null
            & $docker images marlinraker-desktop --format '{{.Repository}}:{{.Tag}}' 2> $null |
                ForEach-Object { & $docker image rm $_ *> $null }
        }
    }
    $settings = Get-Setting
    $usbipd = Get-UsbipdPath
    if ($settings.HardwareId -and $usbipd) {
        Stop-UsbipdAutoAttach -HardwareId $settings.HardwareId
        & $usbipd detach --hardware-id $settings.HardwareId *> $null
        & $usbipd unbind --hardware-id $settings.HardwareId *> $null
    }
    return 0
}

Export-ModuleMember -Variable MainsailUrl -Function @(
    'Find-OrcaSlicer', 'Get-OrcaSlicerCandidatePath', 'ConvertTo-PrinterDevice', 'Get-PrinterDevice',
    'Select-PrinterDevice', 'Test-NeedsReconnect', 'Test-PrintInProgress', 'Get-Setting', 'Save-Setting',
    'Start-Marlinraker', 'Stop-Marlinraker', 'Uninstall-Marlinraker'
)

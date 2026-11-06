param(
    [ValidateSet('orca', 'mainsail', 'start', 'stop', 'uninstall', 'find-orca')]
    [string] $Command = 'orca',
    [switch] $RemoveData,
    [switch] $Force,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]] $Files
)

$installDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $installDir 'MarlinrakerDesktop.psm1') -Force

function Show-Message {
    param([string] $Text, [string] $Icon = 'Warning')
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show($Text, 'Marlinraker', 'OK', $Icon) | Out-Null
}

$notify = { param($text) Show-Message -Text $text }

switch ($Command) {
    'orca' {
        $orca = Find-OrcaSlicer
        if ($orca) {
            if ($Files) {
                Start-Process -FilePath $orca -ArgumentList ($Files | ForEach-Object { '"{0}"' -f $_ })
            } else {
                Start-Process -FilePath $orca
            }
        } else {
            Show-Message -Text 'Não encontrei a OrcaSlicer neste computador. Instale a OrcaSlicer; enquanto isso, o Mainsail vai abrir no navegador.'
        }
        $started = Start-Marlinraker -InstallDir $installDir -Notify $notify
        if ($started -and -not $orca) {
            Start-Process $MainsailUrl
        }
    }
    'mainsail' {
        if (Start-Marlinraker -InstallDir $installDir -Notify $notify) {
            Start-Process $MainsailUrl
        }
    }
    'start' {
        Start-Marlinraker -InstallDir $installDir -Notify $notify | Out-Null
    }
    'stop' {
        $result = Stop-Marlinraker -InstallDir $installDir -Force:$Force
        if ($result -eq 2) {
            Add-Type -AssemblyName System.Windows.Forms
            $answer = [System.Windows.Forms.MessageBox]::Show(
                'Há uma impressão em andamento. Parar o Marlinraker agora cancela a impressão. Parar mesmo assim?',
                'Marlinraker', 'YesNo', 'Warning')
            if ($answer -eq 'Yes') {
                Stop-Marlinraker -InstallDir $installDir -Force | Out-Null
            }
        }
    }
    'uninstall' {
        exit (Uninstall-Marlinraker -InstallDir $installDir -RemoveData:$RemoveData)
    }
    'find-orca' {
        $orca = Find-OrcaSlicer
        if (-not $orca) { exit 1 }
        Write-Output $orca
    }
}

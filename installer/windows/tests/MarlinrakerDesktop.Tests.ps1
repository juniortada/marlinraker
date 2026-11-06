BeforeAll {
    $env:APPDATA = if ($env:APPDATA) { $env:APPDATA } else { [System.IO.Path]::GetTempPath() }
    Import-Module (Join-Path $PSScriptRoot '..' 'MarlinrakerDesktop.psm1') -Force

    $script:UsbipdState = @'
{
  "Devices": [
    {
      "BusId": "1-3",
      "ClientIPAddress": null,
      "Description": "USB-SERIAL CH340 (COM3)",
      "InstanceId": "USB\\VID_1A86&PID_7523\\5&2A7B3C1F&0&3",
      "IsForced": false,
      "PersistedGuid": null,
      "StubInstanceId": null
    },
    {
      "BusId": "1-7",
      "ClientIPAddress": null,
      "Description": "Integrated Webcam, Integrated IR Webcam",
      "InstanceId": "USB\\VID_0BDA&PID_5521\\200901010001",
      "IsForced": false,
      "PersistedGuid": null,
      "StubInstanceId": null
    },
    {
      "BusId": null,
      "ClientIPAddress": null,
      "Description": "Arduino Mega 2560 (COM5)",
      "InstanceId": "USB\\VID_2341&PID_0042\\75833353035351F0E1D1",
      "IsForced": false,
      "PersistedGuid": "3f5a1d0e-6a3c-4ad6-a8f1-0e5d3c2b1a90",
      "StubInstanceId": null
    },
    {
      "BusId": "2-1",
      "ClientIPAddress": "172.29.80.1",
      "Description": "Silicon Labs CP210x USB to UART Bridge (COM7)",
      "InstanceId": "USB\\VID_10C4&PID_EA60\\0001",
      "IsForced": false,
      "PersistedGuid": "9b1f4c2a-1d3e-4f5a-8b7c-6d5e4f3a2b1c",
      "StubInstanceId": null
    }
  ]
}
'@
}

Describe 'Get-PrinterDevice' {
    It 'keeps only serial devices and reads their hardware id and state' {
        $devices = @(Get-PrinterDevice -StateJson $script:UsbipdState)

        $devices.HardwareId | Should -Be @('1a86:7523', '2341:0042', '10c4:ea60')
        ($devices | Where-Object HardwareId -eq '1a86:7523').IsBound | Should -BeFalse
        ($devices | Where-Object HardwareId -eq '2341:0042').IsBound | Should -BeTrue
        ($devices | Where-Object HardwareId -eq '2341:0042').BusId | Should -BeNullOrEmpty
        ($devices | Where-Object HardwareId -eq '10c4:ea60').IsAttached | Should -BeTrue
    }

    It 'returns nothing without usbipd output' {
        Get-PrinterDevice -StateJson '' | Should -BeNullOrEmpty
    }
}

Describe 'Select-PrinterDevice' {
    BeforeAll {
        $script:Devices = @(Get-PrinterDevice -StateJson $script:UsbipdState)
    }

    It 'prefers the saved printer even while it is unplugged' {
        (Select-PrinterDevice -Devices $script:Devices -SavedHardwareId '2341:0042').HardwareId | Should -Be '2341:0042'
    }

    It 'picks the only plugged in serial device' {
        $single = @($script:Devices | Where-Object HardwareId -ne '10c4:ea60')
        (Select-PrinterDevice -Devices $single).HardwareId | Should -Be '1a86:7523'
    }

    It 'returns nothing when no serial device is plugged in' {
        $unplugged = @($script:Devices | Where-Object { -not $_.BusId })
        Select-PrinterDevice -Devices $unplugged | Should -BeNullOrEmpty
    }
}

Describe 'Find-OrcaSlicer' {
    It 'returns the first candidate that exists' {
        Mock -ModuleName MarlinrakerDesktop Get-OrcaSlicerCandidatePath {
            'C:\Missing\OrcaSlicer\orca-slicer.exe'
            'C:\Program Files\OrcaSlicer\orca-slicer.exe'
            'C:\Other\OrcaSlicer\orca-slicer.exe'
        }
        Mock -ModuleName MarlinrakerDesktop Test-Path { $LiteralPath -ne 'C:\Missing\OrcaSlicer\orca-slicer.exe' }

        Find-OrcaSlicer | Should -Be 'C:\Program Files\OrcaSlicer\orca-slicer.exe'
    }

    It 'ignores executables that are not OrcaSlicer' {
        Mock -ModuleName MarlinrakerDesktop Get-OrcaSlicerCandidatePath { 'C:\Program Files\OrcaSlicer\uninstall.exe' }
        Mock -ModuleName MarlinrakerDesktop Test-Path { $true }

        Find-OrcaSlicer | Should -BeNullOrEmpty
    }

    It 'returns nothing when OrcaSlicer is not installed' {
        Mock -ModuleName MarlinrakerDesktop Get-OrcaSlicerCandidatePath { }

        Find-OrcaSlicer | Should -BeNullOrEmpty
    }
}

Describe 'Get-OrcaSlicerCandidatePath' {
    It 'builds candidates even when the install drive no longer exists' {
        Mock -ModuleName MarlinrakerDesktop Get-ItemProperty {
            if ($Path -like 'HKCU:*Uninstall*') {
                [pscustomobject]@{ DisplayName = 'Orca Slicer'; InstallLocation = 'Q:\Removed\OrcaSlicer\' }
            }
        }
        Mock -ModuleName MarlinrakerDesktop Get-StartMenuShortcutTarget { }
        Mock -ModuleName MarlinrakerDesktop Get-PortableOrcaSlicerPath { }

        Get-OrcaSlicerCandidatePath | Should -Contain 'Q:\Removed\OrcaSlicer\orca-slicer.exe'
    }

    It 'reads the install location and icon of uninstall entries named OrcaSlicer' {
        Mock -ModuleName MarlinrakerDesktop Get-ItemProperty {
            if ($Path -like '*Uninstall*' -and $Path -like 'HKLM:\SOFTWARE\Microsoft*') {
                [pscustomobject]@{ DisplayName = 'OrcaSlicer'; InstallLocation = 'D:\Apps\OrcaSlicer'; DisplayIcon = '"D:\Apps\OrcaSlicer\orca-slicer.exe",0' }
                [pscustomobject]@{ DisplayName = 'Something Else'; InstallLocation = 'D:\Apps\Other' }
            }
        }
        Mock -ModuleName MarlinrakerDesktop Get-StartMenuShortcutTarget { 'E:\Portable\OrcaSlicer\orca-slicer.exe' }
        Mock -ModuleName MarlinrakerDesktop Get-PortableOrcaSlicerPath { }

        $candidates = @(Get-OrcaSlicerCandidatePath)

        @($candidates | Where-Object { $_ -eq 'D:\Apps\OrcaSlicer\orca-slicer.exe' }).Count | Should -Be 2
        $candidates | Should -Contain 'E:\Portable\OrcaSlicer\orca-slicer.exe'
        $candidates | Should -Not -Contain 'D:\Apps\Other\orca-slicer.exe'
    }
}

Describe 'Test-NeedsReconnect' {
    It 'is true only when Marlinraker found no serial port' {
        Test-NeedsReconnect -PrinterInfo ([pscustomobject]@{ state = 'error'; state_message = 'Cannot connect to printer' }) | Should -BeTrue
        Test-NeedsReconnect -PrinterInfo ([pscustomobject]@{ state = 'error'; state_message = 'Printer initialization took too long' }) | Should -BeFalse
        Test-NeedsReconnect -PrinterInfo ([pscustomobject]@{ state = 'ready'; state_message = 'Printer ready' }) | Should -BeFalse
        Test-NeedsReconnect -PrinterInfo $null | Should -BeFalse
    }
}

Describe 'Test-PrintInProgress' {
    It 'treats printing and paused jobs as in progress' {
        Test-PrintInProgress -State 'printing' | Should -BeTrue
        Test-PrintInProgress -State 'paused' | Should -BeTrue
        Test-PrintInProgress -State 'standby' | Should -BeFalse
        Test-PrintInProgress -State 'complete' | Should -BeFalse
    }
}

Describe 'Settings' {
    It 'round trips the saved printer hardware id' {
        $path = Join-Path ([System.IO.Path]::GetTempPath()) "marlinraker-settings-$([guid]::NewGuid()).json"
        try {
            Get-Setting -Path $path | Select-Object -ExpandProperty HardwareId | Should -BeNullOrEmpty
            Save-Setting -Settings ([pscustomobject]@{ HardwareId = '1a86:7523' }) -Path $path
            (Get-Setting -Path $path).HardwareId | Should -Be '1a86:7523'
        } finally {
            Remove-Item -LiteralPath $path -ErrorAction SilentlyContinue
        }
    }
}

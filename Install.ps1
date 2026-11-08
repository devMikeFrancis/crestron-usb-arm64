<#
.SYNOPSIS
    Makes Crestron USB devices usable by Crestron Toolbox on Windows on ARM (for
    example Windows 11 in Parallels on Apple Silicon).

.DESCRIPTION
    UNOFFICIAL. NOT AFFILIATED WITH CRESTRON. PROVIDED AS-IS, WITHOUT SUPPORT.

    Installs nothing of its own. For each connected Crestron USB device that has no
    driver, it:

      1. Sets the device interface GUID that Toolbox looks for.
      2. Binds the device to Microsoft's WinUSB driver (winusb.inf, which ships
         with Windows), the same as picking "WinUsb Device" in Device Manager.

    No driver package, catalog or certificate is involved, because everything
    installed is Microsoft's. Devices already on WinUSB are checked and fixed if
    the interface GUID is missing. Devices bound to some other driver are left alone.

    Windows remembers the binding per USB port. If a device shows up as an unknown
    "Crestron Device" again after you use a different port, run this again.

    Uninstall.ps1 reverses it.

    Exit code: 0 if every device is set up (or nothing needed doing), 1 otherwise.

.PARAMETER Force
    Run even if this is not ARM64 Windows. On x64, use Crestron's own driver instead.

.EXAMPLE
    .\Install.ps1 -WhatIf
    Shows what would be done, without administrator rights and without changing anything.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Force,
    [switch]$PauseAtEnd
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3
. (Join-Path $PSScriptRoot 'lib\ArmUsb.ps1')

# Run in native PowerShell, elevated. A -WhatIf run only reads, so it does not
# need elevation.
$relaunchExit = Invoke-SelfRelaunch -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters -NoElevate:$WhatIfPreference
if ($null -ne $relaunchExit) { exit $relaunchExit }

$exitCode = 0
try {
    $arch = Get-OsArchitecture
    if ($arch -ne 'ARM64' -and -not $Force) {
        throw "This Windows is $arch, not ARM64. Use Crestron's own Toolbox USB driver on x86/x64. (-Force overrides.)"
    }
    Initialize-Binder
    $winusbInf = Join-Path $env:windir 'INF\winusb.inf'
    if (-not (Test-Path $winusbInf)) { throw "$winusbInf is missing; this Windows has no inbox WinUSB." }

    # Clean up after the first version of this tool (signed package, rejected on ARM64).
    if (Test-LegacyInstall) {
        if ($PSCmdlet.ShouldProcess('old ArmUsb driver package and signing certificate', 'Remove')) {
            $legacyProblems = @(Remove-LegacyInstall)
            if ($legacyProblems.Count) { $legacyProblems | ForEach-Object { Write-Warning $_ } }
        }
    }

    $devices = @(Get-CrestronUsbDevices)
    if (-not $devices.Count) {
        Write-Host 'No Crestron USB device is connected. Plug one in (in Parallels: Devices >'
        Write-Host 'USB & Bluetooth > "Crestron Device"), then run this again.'
        return
    }

    # What to report when ShouldProcess says no: -WhatIf, or "No" at -Confirm.
    $notDone = { param($what) if ($WhatIfPreference) { "would $what" } else { 'skipped: not confirmed' } }

    $results = @()
    foreach ($d in $devices) {
        $id = $d.InstanceId
        $action = ''
        $changed = $false
        $reboot = $false
        try {
            if ($d.Service -ieq 'WINUSB') {
                if ($d.HasGuid -and (Test-CrestronInterfaceEnabled $id)) {
                    $action = 'already set up'
                } elseif ($PSCmdlet.ShouldProcess($id, 'Set Toolbox interface GUID and restart device')) {
                    [ArmUsb.WinUsbBinder]::SetInterfaceGuid($id, $CrestronInterfaceGuid)
                    $reboot = Restart-UsbDevice $id
                    $action = 'on WinUSB; interface GUID added'
                    $changed = $true
                } else {
                    $action = & $notDone 'add interface GUID'
                }
            } elseif ($d.Service) {
                $action = "skipped: uses driver '$($d.Service)', left alone"
            } else {
                # Previewing which driver would be picked is only for -WhatIf; a real
                # run finds it in Bind itself, after it has set the device class.
                $target = 'WinUSB Device (winusb.inf)'
                if ($WhatIfPreference) {
                    $target = [ArmUsb.WinUsbBinder]::Bind($id, $winusbInf, $false, [ref]$reboot)
                }
                if ($PSCmdlet.ShouldProcess($id, "Bind to $target")) {
                    [ArmUsb.WinUsbBinder]::SetInterfaceGuid($id, $CrestronInterfaceGuid)
                    [ArmUsb.WinUsbBinder]::Bind($id, $winusbInf, $true, [ref]$reboot) | Out-Null
                    # WinUSB normally comes up with the interface on its own; if it
                    # has not after a moment, a restart makes it re-read the GUID.
                    if (-not $reboot -and -not (Wait-CrestronInterface $id -TimeoutMs 2000)) {
                        $reboot = Restart-UsbDevice $id
                    }
                    $action = 'bound to WinUSB'
                    $changed = $true
                } else {
                    $action = & $notDone "bind to $target"
                }
            }
            if ($reboot) {
                # The interface cannot come up until Windows restarts; not a failure.
                $action += ' (restart Windows to finish)'
            } elseif ($changed -and -not (Wait-CrestronInterface $id)) {
                throw 'finished, but Toolbox interface is not enabled on the device'
            }
        } catch {
            $action = "FAILED: $($_.Exception.Message)"
            $exitCode = 1
        }
        $results += [pscustomobject]@{ Device = $id; Result = $action }
    }

    Write-Host ''
    $results | Format-Table -AutoSize -Wrap | Out-String -Width 200 | Write-Host
    if ($devices.Count -gt 1) {
        Write-Host 'Tip: Toolbox Learn IR uses the first Crestron device it finds. Connect only the'
        Write-Host 'IR learner while learning, or it reports "An invalid device is connected".'
    }
    if ($exitCode -eq 0 -and -not $WhatIfPreference) {
        Write-Host 'Done. Open Toolbox and connect over USB.' -ForegroundColor Green
    }
} catch {
    Write-Host "INSTALL FAILED: $($_.Exception.Message)" -ForegroundColor Red
    $exitCode = 1
} finally {
    if ($PauseAtEnd) { Read-Host 'Press Enter to close' | Out-Null }
}
exit $exitCode

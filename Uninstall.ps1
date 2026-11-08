<#
.SYNOPSIS
    Reverses Install.ps1: Crestron USB devices go back to having no driver.

.DESCRIPTION
    Removes the Windows device entry for each Crestron USB device that is on
    Microsoft's WinUSB through winusb.inf (the binding Install.ps1 makes, or the
    same one made by hand in Device Manager), connected or not. Connected devices
    are then re-detected and show as an unknown "Crestron Device" again.

    Also removes anything left by the first version of this tool (a signed driver
    package and its local certificate) and %ProgramData%\ArmUsb (where earlier
    versions kept a state file).

    Exit code: 0 on success, 1 if anything could not be removed.

    Devices on any other driver are not touched, and Crestron's own driver
    packages are never touched.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch]$Quiet,
    [switch]$PauseAtEnd
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3
. (Join-Path $PSScriptRoot 'lib\ArmUsb.ps1')

$relaunchExit = Invoke-SelfRelaunch -ScriptPath $PSCommandPath -BoundParameters $PSBoundParameters -NoElevate:$WhatIfPreference
if ($null -ne $relaunchExit) { exit $relaunchExit }

$problems = @()
$say = { param($m) if (-not $Quiet) { Write-Host $m } }

try {
    # Ours: on WinUSB via the inbox INF. Includes devices not plugged in right now,
    # so an old port's entry does not keep the binding around.
    $targets = @(Get-CrestronUsbDevices -All | Where-Object {
        $_.Service -ieq 'WINUSB' -and $_.InfPath -and (Split-Path $_.InfPath -Leaf) -ieq 'winusb.inf'
    })
    $anyPresent = $false
    foreach ($d in $targets) {
        if ($PSCmdlet.ShouldProcess($d.InstanceId, 'Remove device entry (unbinds WinUSB)')) {
            & $say "Removing $($d.InstanceId)$(if (-not $d.Present) { ' (not connected)' })"
            $r = Invoke-PnpUtil @('/remove-device', $d.InstanceId)
            if ($PnpUtilSuccess -notcontains $r.ExitCode) {
                $problems += "pnputil could not remove $($d.InstanceId) (exit $($r.ExitCode)): $($r.Output)"
            }
            if ($d.Present) { $anyPresent = $true }
        }
    }
    if ($anyPresent) { Invoke-PnpUtil @('/scan-devices') | Out-Null }

    if (Test-LegacyInstall) {
        if ($PSCmdlet.ShouldProcess('old ArmUsb driver package and signing certificate', 'Remove')) {
            $problems += @(Remove-LegacyInstall -Say $say)
        }
    }

    if ((Test-Path $StateDir) -and $PSCmdlet.ShouldProcess($StateDir, 'Delete')) {
        Remove-Item $StateDir -Recurse -Force
    }

    if ($problems.Count) {
        $problems | ForEach-Object { Write-Host $_ -ForegroundColor Red }
        $exitCode = 1
    } else {
        if (-not $targets.Count) { & $say 'No Crestron device was bound to WinUSB.' }
        & $say 'ArmUsb is removed.'
        $exitCode = 0
    }
} catch {
    Write-Host "UNINSTALL FAILED: $($_.Exception.Message)" -ForegroundColor Red
    $exitCode = 1
} finally {
    if ($PauseAtEnd) { Read-Host 'Press Enter to close' | Out-Null }
}
exit $exitCode

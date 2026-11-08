# ArmUsb: Crestron USB devices on Windows on ARM

Lets Crestron Toolbox talk to Crestron USB devices (processor USB console,
program loading, USB IR learner) on **ARM64 Windows**, for example Windows 11
in Parallels on an Apple Silicon Mac.

> **Unofficial. Not affiliated with, endorsed by, or supported by Crestron
> Electronics, Inc. Provided as-is, with no warranty and no support.** Bug
> reports are welcome as issues, but there is no promise of a response.

## Status

Tested on Windows 11 ARM64 (Parallels) with Toolbox:

| Device | USB ID | Result |
|---|---|---|
| CP3 processor | VID 14BE PID 0009 | Console, IP configuration, program load: working |
| CSP-LIR-USB IR learner | VID 14BE PID 0009 | Learn IR: working |

Devices with PID 0003, 0004 or 0007 (older consoles and loaders) are bound the
same way but are **untested**. On x64, Crestron's driver adds a filter driver for them
that has no ARM64 build.

## Why it's needed

Crestron's Toolbox USB driver is Microsoft's built-in WinUSB driver plus
Crestron's USB IDs and an interface ID that Toolbox searches for. Its setup
file only lists x86 and x64, so Windows on ARM won't use it.

This tool doesn't install a driver of its own. It binds each connected Crestron
device to the **WinUSB driver that ships with Windows**, the same as picking
"WinUsb Device" by hand in Device Manager. It also sets the interface ID Toolbox
looks for. Everything installed is Microsoft's, so no certificate or signing
is involved.

## Install

1. In Parallels, pass the Crestron device through to Windows: Devices > USB &
   Bluetooth > **Crestron Device**. (Be careful not to pass through your
   keyboard/mouse receiver.)
2. Double-click `Install.cmd` and accept the administrator prompt.
3. Open Toolbox and connect over USB.

Windows remembers the binding **per USB port**. If a device shows up as an
unknown "Crestron Device" again later (new port, new device), run
`Install.cmd` again. `Install.ps1 -WhatIf` shows what it would do without
changing anything.

**Learn IR tip:** Toolbox uses the first Crestron USB device it finds. With a
processor and the IR learner both connected, it reports "An invalid device is
connected". Connect only the learner while learning IR.

## Uninstall

Double-click `Uninstall.cmd`. Crestron devices bound to WinUSB go back to
having no driver. Devices on any other driver, and Crestron's own driver
packages, are not touched.

## Files

- `Install.ps1` / `Uninstall.ps1` (+ `.cmd` wrappers), `lib\ArmUsb.ps1`.
- `CrestronWinUsb-arm64.inf`, `CrestronRNDIS-arm64.inf`: an INF version of the
  same binding. **The installer doesn't use them.** ARM64 Windows rejects
  them unless they're signed by Microsoft (attestation signing). They're kept
  for reference and for a possible signed release. The RNDIS one matches the
  generic Linux USB-gadget ID (`VID_0525&PID_A4A2`), so it would also claim
  non-Crestron devices.

## Troubleshooting

- **"Add-Type" / "Cannot add type" errors:** the installer compiles a small C#
  helper to call Windows' device-setup API. Machines locked down with
  Windows Defender Application Control (WDAC) or PowerShell Constrained
  Language Mode block that. Run it on an unmanaged machine, or ask IT for an
  exception.
- **Exit codes:** both scripts exit 0 on success and 1 on any failure, also
  when they relaunch themselves elevated, so they can be scripted.

## License

MIT. See `LICENSE`.

Crestron and Crestron Toolbox are trademarks of Crestron Electronics, Inc.

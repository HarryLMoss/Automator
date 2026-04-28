# Automator

> *"Hardware does what software cannot."*

Automator is a two-layer autonomous provisioning system developed during commercial deployment work at an enterprise IT configuration facility. It combines a **PowerShell state-machine automation engine** with an **STM32 Embedded C USB HID firmware controller** to deliver a fully deterministic, end-to-end Windows update and OOBE provisioning pipeline — removing all manual operator interaction from a process previously requiring constant human supervision.

This is **a real-world embedded systems solution** designed and implemented independently in a commercial environment, processing deployments across enterprise clients including Microsoft, Apple, HP, Lenovo, and Computacenter.

---

## Overview

The system solves a fundamental problem in enterprise-scale Windows deployment: PowerShell automation is highly effective for software-layer tasks (updates, logging, validation, network management) but cannot reliably interact with the Windows OOBE provisioning screen — a hardware-level UI barrier that occurs before the OS shell is fully active.

Automator bridges this gap by pairing the PowerShell engine with a dedicated STM32 Nucleo microcontroller running Embedded C firmware that enumerates as a USB HID keyboard. Windows sees a real hardware keyboard — not software automation — making the interaction deterministic and immune to focus loss, shell transitions, and timing fragility.

```
[PowerShell Automator]          [STM32 HID Controller]
  State machine                   USB HID firmware
  Windows Update pipeline   +     Button-triggered
  Network management              key sequence injection
  Logging & validation            OOBE provisioning trigger
  Reboot persistence              Hardware-level reliability
        ↓                               ↓
        └───────── Enterprise Windows Deployment ──────────┘
```

---

## System Architecture

```
automator/
│
├── README.md
├── LICENSE
├── AutomatorHID.c          — STM32 Embedded C USB HID firmware controller
└── Automator.ps1           — PowerShell state-machine automation engine
```

---

## Layer 1 — PowerShell Automation Engine (`Automator.ps1`)

The PowerShell layer handles the full software-side deployment lifecycle autonomously across reboots, using a persistent config file as a state store.

### State Machine

```
Initial
   ↓
Network validation + NTP time sync
   ↓
Scheduled task registration (SYSTEM account, ONSTART)
   ↓
Windows Update installation (loop with reboot persistence)
   ↓  [UpdatesContinue across reboots]
UpdatesComplete
   ↓
Windows version + edition validation
Driver error checks
System event log audit
   ↓
Cleanup — scheduled task deleted, config purged
```

### Key Features

- **Reboot-persistent state machine** — survives multiple reboots via a config file, resuming at the correct pipeline stage on each restart without operator input
- **Autonomous Windows Update pipeline** — installs all available updates including optional and cumulative preview updates via PSWindowsUpdate, with automatic reboot and resume
- **Network adapter management** — detects, isolates, and re-enables network adapters at the correct pipeline stages to prevent premature connectivity during OOBE
- **NTP time synchronisation** — sets timezone and forces w32tm resync before update installation to prevent certificate and update validation failures
- **Scheduled task automation** — registers itself as a SYSTEM-level ONSTART scheduled task to survive reboots without user login dependency
- **Windows version and edition validation** — reads expected version from config and validates against registry values post-update
- **Driver error detection** — runs PnP device error checks with a 60-second timeout watchdog before sign-off
- **Structured logging** — timestamped log written to USB drive throughout, readable live via `Get-Content`
- **Self-cleaning** — deletes scheduled task and config file on successful completion, leaving no residual artefacts on the target machine

### Deployment

Run from a USB drive on any target machine with Administrator PowerShell:

```powershell
powershell.exe -ExecutionPolicy Bypass -File D:\Automator.ps1
```

On first run the operator is prompted once for Windows version and edition — all subsequent stages run autonomously across reboots.

---

## Layer 2 — STM32 USB HID Firmware Controller (`AutomatorHID.c`)

The embedded firmware layer solves the one problem PowerShell cannot: reliable interaction with the Windows OOBE pre-provisioning screen, which exists below the software automation layer.

### Hardware

- **Platform:** STM32 Nucleo (STM32F4 series — F401RE, F446RE, F411RE)
- **IDE:** STM32CubeIDE with STM32CubeMX configuration
- **Peripherals:** USB Device (HID Class), GPIO (USER button input)

### Firmware Design

The firmware enumerates as a standard USB HID keyboard. Windows treats it as real hardware input — bypassing all focus, shell, and timing issues that affect software-based key injection.

```c
// HID report structure — standard 8-byte USB keyboard report
uint8_t report[8] = {0};
report[0] = modifier;   // Modifier byte (Shift, Ctrl, Alt)
report[2] = keycode;    // HID keycode
USBD_HID_SendReport(&hUsbDeviceFS, report, sizeof(report));
```

### State Machine

```
Power on → USB enumeration → Idle (waiting)
                                    ↓
                            Button pressed
                                    ↓
                            Debounce (50ms)
                                    ↓
                            triggered = 1
                                    ↓
                            send_key_sequence()
                                    ↓
                            Idle — reset on button release
```

### Key sequence

The default provisioning sequence (adjustable per workflow):

```
3000ms initial delay    — allow OOBE screen to fully render
TAB  → 300ms delay
TAB  → 300ms delay
ENTER → 1500ms delay
ENTER → 1000ms delay
```

### Key Features

- **USB HID enumeration** — enumerates as a real keyboard; works at BIOS, login, and OOBE level
- **Hardware debounce** — 50ms GPIO debounce prevents false triggering
- **Single-trigger state machine** — `triggered` flag prevents repeated firing on held button; resets cleanly on button release
- **Deterministic timing** — HAL_Delay-based timing ensures consistent key injection regardless of host OS state
- **Portable and reusable** — unplug and move to the next machine; no reconfiguration required

### Why Hardware Over Software

| | PowerShell Key Injection | STM32 HID Injection |
|---|---|---|
| OS dependency | High | None |
| Focus sensitivity | Fails on focus loss | Immune |
| OOBE compatibility | Unreliable | Full |
| Shell dependency | Required | None |
| Timing consistency | Variable | Deterministic |
| Reusability | Per-machine | Plug and move |

---

## Result

Deployed across enterprise-scale Windows provisioning workflows processing 20–30 devices simultaneously, the combined system reduced operator intervention to a single button press per machine at the OOBE stage — all update installation, reboot management, validation, and cleanup running autonomously. Speed of execution increased by approximately 300% compared to the previous manual method, with workforce labour reduced to approximately one quarter.

---

## Technologies

| Technology | Usage |
|---|---|
| PowerShell | State-machine automation engine, Windows lifecycle management |
| Embedded C | STM32 USB HID firmware |
| STM32CubeIDE | Embedded firmware development environment |
| STM32CubeMX | Peripheral configuration (USB Device, GPIO) |
| USB HID Protocol | Hardware keyboard emulation |
| PSWindowsUpdate | Windows Update automation module |
| Git | Version control |

---

## Future Extensions

- USB serial feedback channel — firmware reports provisioning success back to the PowerShell layer
- Multi-stage provisioning sequences — configurable key sequences via USB serial without reflashing
- LED / buzzer status indicators — visual and audible confirmation on sequence completion
- Watchdog timer — automatic reset on sequence timeout
- Automatic screen-state detection — camera or serial input to trigger without manual button press

---

## License

GNU General Public License v3.0 — see `LICENSE` for details.

---

## Author

Harry Moss — harrymoss33@gmail.com

Other embedded and audio DSP projects: [github.com/HarryLMoss](https://github.com/HarryLMoss)

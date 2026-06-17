# Modern Standby Notes

Modern Standby is Windows' phone-like sleep model. It can be excellent when the
firmware, drivers, network stack, and OEM services behave. It can also drain
battery, heat a laptop in a bag, or wake for maintenance.

Useful signals:

- `powercfg /a`: shows whether S0 Low Power Idle is supported.
- `powercfg /sleepstudy`: shows sessions, drain, top offenders, and connected
  vs disconnected standby behavior.
- `powercfg /requests`: shows active blockers.
- `powercfg /waketimers`: shows scheduled wake timers.
- `powercfg /devicequery wake_armed`: shows devices allowed to wake the machine.
- Kernel-Power events 506 and 507 often mark Modern Standby entry/exit.

Conservative policy used by this kit:

- Keep hibernation enabled.
- Never auto-hibernate on AC by idle timer.
- On battery, allow a delayed hibernation after a configurable standby window.
- Disable network connectivity during Modern Standby on battery.
- Keep connected Modern Standby on AC.
- Disable wake timers on battery, allow them on AC.

This tries to preserve the "open the lid and work" feeling for short breaks,
while protecting the battery during longer bag time.


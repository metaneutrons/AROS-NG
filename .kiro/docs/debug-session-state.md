# Current Debugging Session State (2026-04-18 10:26)

## Active Investigation: Wanderer deadlock when opening directory windows

### What's fixed
- Stack overflow crash (LR=0x1/0x4/0x5) — input.device stack too small for deep Zune call chain. Fixed: `AROS_STACKSIZE * 4` on aarch64. Commit `bc493de2ff`.
- EndCLI not closing shell — Shell.c reset `cli_Background` after script end. Fixed: preserve if already set. Commit `c01efaaeea`.
- Mirrored framebuffer mode — works, commit `0f6d5af271`.

### Current bug: Wanderer deadlock
- Wanderer freezes after opening 1-3 directory windows (not always the same window)
- NOT a crash — system is alive, CPU in idle loop, Wanderer task in TS_WAIT
- Wanderer task at `0x92a5c0`, `tc_SigWait: 0xfe1000`, `tc_SigRecvd: 0x120` — mismatch
- Received signals (0x120 = bits 5,8) don't match wait mask (0xfe1000 = bits 12,17-23)
- Something should signal Wanderer with one of the 0xfe1000 bits but isn't

### QEMU state
- Running on cachy with GDB on port 1234, VNC on :1 (port 5901)
- Command: `qemu-system-aarch64 -M raspi4b -m 2G -serial file:/tmp/aros_vnc.log -display vnc=:1 -gdb tcp::1234 -dtb bcm2711-rpi-4-b.dtb -kernel build/bin/raspi-aarch64/AROS/aros-aarch64-raspi.img -sd aros_sd_full.img -initrd build/bin/raspi-aarch64/AROS/aros-aarch64-bsp.rom -device usb-kbd -device usb-mouse -device usb-tablet`

### Key struct offsets (AArch64)
- SysBase: 0x12800
- `ThisTask` offset from SysBase: 0x228
- `TaskReady` list: SysBase + 0x330
- `TaskWait` list: SysBase + 0x350
- struct Task: `ln_Name`=24, `tc_State`=0x21, `tc_IDNestCnt`=0x22, `tc_TDNestCnt`=0x23, `tc_SigWait`=0x28, `tc_SigRecvd`=0x2C, `tc_SPReg`=0x60, `tc_SPLower`=0x68, `tc_SPUpper`=0x70
- TLS at 0x515000: [0]=SysBase, [8]=KernelBase, [16]=ThisTask

### Next steps
1. Dump all tasks in TaskWait and TaskReady lists to see who else is stuck
2. Find which task should be signaling Wanderer (likely a DOS handler or Intuition)
3. Check if it's a 64-bit pointer issue in message passing (signal sent to wrong task)

### Build commands
```bash
cd /home/fabian/AROS-AArch64/build
make -j12 wanderer-classes-iconlist-quick   # IconList.mui
make -j12 kernel-input-quick                # input.device
make kernel-package-raspi-aarch64           # BSP ROM
make kernel-raspi-aarch64-bootimg           # kernel image
```

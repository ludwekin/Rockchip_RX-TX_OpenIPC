# Boot 镜像（11/4 #4 内核 + HDMI DTB）

## 文件

`boot4-hdmi.itb`（41,772,544 字节）

- FIT：fdt + kernel + resource
- 内核：`6.1.141 #4 SMP Wed Nov 4 03:13:47 EST 2026`（SDK 构建）
- DTB：HDMI 可用版本（`hdmi@fe0a0000 = okay`、`dsi@fe070000 = disabled`、
  `route-hdmi = okay`、`route-dsi1 = disabled`）
- bootargs：`earlycon=uart8250,mmio32,0xfe660000 console=ttyFIQ0
  root=PARTUUID=614e0000-0000 rw rootwait`

sha256：

```
da7902c5ce252234ae892ad25fe46430bafdc7197939f06054300e7a756dd283
```

## 分区

泰山派 eMMC：

```
p1 uboot     LBA 0x4000
p2 misc      LBA 0x6000
p3 boot      LBA 0x8000, 64MB
p4 recovery  LBA 0x28000, 128MB
p5 backup    LBA 0x68000, 32MB
p6 rootfs    LBA 0x78000, PARTUUID=614e0000-0000
p7 oem
p8 userdata
```

`boot4-hdmi.itb` 写到 **p3**。

## 刷写（推荐：Linux 里 dd）

板子能正常启动 Linux 时：

```bash
adb push boot4-hdmi.itb /tmp/boot4-hdmi.itb
adb shell 'dd if=/tmp/boot4-hdmi.itb of=/dev/mmcblk0p3 bs=1M conv=fsync; sync'
adb shell reboot
```

验证：

```bash
cat /proc/device-tree/hdmi@fe0a0000/status    # okay
cat /sys/class/drm/card0-HDMI-A-1/status     # connected
```

## Maskrom / Loader 注意事项

实测当前 miniloader/Loader：

- `rkdeveloptool wl 0x8000 boot4-hdmi.itb` 会显示 100%，但 **16MB 之后读回 0xCC**，
  实际写入被截断，内核不完整 → HDMI logo 后反复重启；
- `db` 下载完整 loader 在 Loader 模式不支持（`The device does not support this operation!`）；
- 需要真正的 **Maskrom** 才能 `db`；
- 替代方案：用 SDK 的 `upgrade_tool UF`，打包一个只含
  `parameter + bootloader + boot` 的 update.img（不打包 rootfs），升级协议能写大分区。

详见 `docs/DEBUG_NOTES.md` 第 9 节。

## DSI 版本（3.1" 480x800）

`boot4-dsi.itb`（41,772,544 字节）是 #4 内核 + **DSI DTB**：

- sha256：`c910505b7f41cc292e299af2fec8448e159d57ab9b115bc6d9cebf7324057293`
- DTB：`tools/fdt-dsi.dtb`（sha256 `9b44e989...`）
  - `dsi@fe070000 = okay`
  - `hdmi@fe0a0000 = disabled`
  - 包含 3.1" 480x800 面板初始化和 CST128A 触摸节点
- 本内核只有一个 CRTC：**HDMI 和 DSI 不能同时用**

刷法同 HDMI：

```bash
adb push boot4-dsi.itb /tmp/boot4-dsi.itb
adb shell 'dd if=/tmp/boot4-dsi.itb of=/dev/mmcblk0p3 bs=1M conv=fsync; sync'
adb shell reboot
```

确认：

```bash
cat /proc/device-tree/dsi@fe070000/status   # okay
cat /sys/class/drm/card0-DSI-1/status       # connected
```

板端原始备份（64MB p3，含同名 FIT）：

```
/root/boot-backup/boot-20261116-dsi.img
```

也可以从 HDMI 版重建 DSI 版（两者都是 #4 内核，只换 fdt）：

```bash
python3 tools/patch_inplace.py boot/boot4-hdmi.itb tools/fdt-dsi.dtb boot/boot4-dsi.itb
```

## 重新生成 boot4-hdmi.itb

### 方法 A：patch_inplace（本仓库使用）

需要一个 #4 内核的原始 FIT（SDK 备份 `backup/boot_min.img`，DSI DTB）：

```bash
python3 tools/patch_inplace.py /path/to/boot_min.img tools/fdt-orig.dtb boot4-hdmi.itb
```

- `patch_inplace.py` 只替换 FIT 内 fdt 数据并重算 `/images/fdt/hash/value`；
- fdt slot 168355 字节，`fdt-orig.dtb` 也是 168355，正好；
- kernel/resource 布局不变。

### 方法 B：SDK 的 resource_tool + mkbootimg

用 SDK 的内核 Image 和 HDMI DTB 重新打 Android boot 镜像：

```bash
cd /path/to/tspi_sdk/extracted_sdk/kernel-6.1
# HDMI DTB（HDMI okay / DSI disabled）
scripts/resource_tool \
  arch/arm64/boot/dts/rockchip/tspi-rk3566-user-v10-linux.dtb \
  logo.bmp logo_kernel.bmp
scripts/mkbootimg --kernel arch/arm64/boot/Image \
  --second resource.img -o boot-hdmi.img
```

注意：SDK 默认打出来的 DTB 可能是 **DSI enabled / HDMI disabled**（用户之前为 DSI 屏改过）。
请确认 DTB 状态，或直接用本仓库 `tools/fdt-orig.dtb`。

## 还原/备份

板子 rootfs 里的备份：

```
/root/boot-backup/boot-20261116-dsi.img   # 原始 #4 + DSI
/root/boot-backup/boot-orig.img           # 更早的 vendor/旧内核
```

刷回 DSI 版：

```bash
adb push boot-20261116-dsi.img /tmp/
adb shell 'dd if=/tmp/boot-20261116-dsi.img of=/dev/mmcblk0p3 bs=1M conv=fsync; sync'
```

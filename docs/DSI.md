# 3.1 寸 MIPI DSI (480x800) + CST128A 触摸

同一路 wfb-ng 视频也可以输出到板子上的 **3.1 寸 MIPI DSI 屏**，不占用 HDMI。
RK3566 这套 BSP 内核只给一个 CRTC/VP0 分配 plane，**HDMI 和 DSI 不能同时使用**，
所以需要刷对应的 boot：

| 显示 | boot 镜像 | DTB |
|---|---|---|
| HDMI 1280x720p60 | `boot/boot4-hdmi.itb` | `tools/fdt-orig.dtb` |
| MIPI DSI 480x800 | `boot/boot4-dsi.itb` | `tools/fdt-dsi.dtb` |

## 硬件

- 3.1" MIPI DSI1：`dsi@fe070000`，面板初始化序列在 DSI DTB 里；
- 触摸：CST128A，i2c1 `i2c@fe5a0000`，地址 `0x38`，`compatible = "hyn,cst128a"`；
- 原始 DSI boot 的板端备份：`/root/boot-backup/boot-20261116-dsi.img`（64MB p3）。

## 刷 DSI boot

`boot/boot4-dsi.itb` 是 #4 内核 + DSI DTB（HDMI disabled），
sha256：

```
c910505b7f41cc292e299af2fec8448e159d57ab9b115bc6d9cebf7324057293
```

在板子 Linux 里写 p3（和 HDMI 版同样的方法）：

```bash
adb push boot/boot4-dsi.itb /tmp/boot4-dsi.itb
adb shell 'dd if=/tmp/boot4-dsi.itb of=/dev/mmcblk0p3 bs=1M conv=fsync; sync'
adb shell reboot
```

确认：

```bash
cat /proc/device-tree/dsi@fe070000/status   # okay
cat /proc/device-tree/hdmi@fe0a0000/status  # disabled
cat /sys/class/drm/card0-DSI-1/status       # connected
```

DRM summary 应是：

```
Video Port0: ACTIVE
    Connector:DSI-1  Encoder: DSI-120
    Display mode: 480x800p60
```

## 播放（DSI）

`wfb-watchdog.sh` 会自动检测 `card0-DSI-1`，并使用 DSI 管线：

```bash
gst-launch-1.0 -e udpsrc port=5600 buffer-size=33554432 \
  caps="application/x-rtp, media=(string)video, payload=(int)97, clock-rate=(int)90000, encoding-name=(string)H265" \
  ! rtpjitterbuffer latency=0 mode=none \
  ! rtph265depay ! h265parse \
  ! video/x-h265,stream-format=byte-stream,alignment=au \
  ! mppvideodec \
  ! queue leaky=downstream max-size-buffers=1 max-size-time=0 max-size-bytes=0 \
  ! videoconvert \
  ! videoflip method=counterclockwise \
  ! videoscale add-borders=true \
  ! video/x-raw,width=480,height=800 \
  ! kmssink sync=false
```

- 面板是竖屏 480x800，视频是横屏；`videoflip counterclockwise` + `videoscale add-borders`
  旋转并等比缩放，留黑边；
- **不要用 `mppvideodec fast-mode=true`**（会卡第一帧）；
- DSI 的 `kmssink` 不需要 `force-modesetting`（模式由面板固定 480x800）；
- 如果方向不对，改 `videoflip method=clockwise|horizontal-flip|vertical-flip`。

`wfb-hdmi.sh` 是一次性 HDMI 版；DSI 请用 `wfb-watchdog.sh`（或 systemd 服务）。

## 触摸 CST128A

### 安装

```bash
# 板子上（root）
cp touch/cst128a_ts.ko /lib/modules/$(uname -r)/extra/
depmod -a
cp touch/cst128a.conf /etc/modules-load.d/cst128a.conf
modprobe cst128a_ts
```

`cst128a.conf` 内容：

```
cst128a_ts
```

### 验证

```bash
dmesg | grep -i cst
cat /proc/bus/input/devices | grep -A6 CST128
ls /dev/input/
evtest /dev/input/event5     # 触摸屏幕看坐标事件
```

正常会看到：

```
input: CST128 TouchScreen as /devices/platform/fe5a0000.i2c/i2c-1/1-0038/input/input5
N: Name="CST128 TouchScreen"
H: Handlers=event5 dmcfreq
```

初始化时可能出现：

```
hyn_cst128a 1-0038: hyn_cst128_ts_write: write error, addr=0x0 len=1.
hyn_cst128a 1-0038: hyn_cst128_ts_write: write error, addr=0xa4 len=1.
```

触摸仍会注册并工作；如果完全没事件，检查 DTB 的 `i2c@fe5a0000/tp@38`
（`reset-gpios`/`irq-gpios`/`display-coords`）和排线。

### 源码/模块

- `touch/cst128a_ts.c`、`touch/hyn_core.c`、`Kconfig`、`Makefile`；
- `touch/cst128a_ts.ko`（与 #4 内核匹配，实测可加载）；
- `touch/cst128a.conf`（开机加载）。

触摸坐标/方向由 DTB 的 `display-coords`、`pos-swap`、`posx-reverse`、`posy-reverse`
控制；具体值见你板子的 DSI DTB，或参考 `tspi-screen` 工作区的 `mk_dts2.py`。

## DSI / HDMI 切换

- 当前内核一个 CRTC：**不要指望同时 HDMI + DSI**；
- 切 HDMI：dd `boot4-hdmi.itb`；切 DSI：dd `boot4-dsi.itb`；
- 两者都是 #4 内核，只有 DTB 不同；
- `boot4-dsi.itb` 也可以由 `boot4-hdmi.itb` + `tools/fdt-dsi.dtb` 重建：

```bash
python3 tools/patch_inplace.py boot/boot4-hdmi.itb tools/fdt-dsi.dtb boot/boot4-dsi.itb
```

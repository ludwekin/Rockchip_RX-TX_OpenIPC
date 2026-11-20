# MPP / librga / GStreamer 升级 + GPU 播放器

板子 rootfs 是 Ubuntu 22.04（glibc **2.35**），内核是 LCKFB SDK 的 **6.1.141**（新的
`mpp_rkvdec2` / RGA 驱动）。但 rootfs 里自带的用户态库是 2021 年的旧版，和新内核不匹配：

| 组件 | 升级前 | 升级后 |
|---|---|---|
| `librockchip_mpp.so.0` | 2021-05（旧） | SDK 2026 源码原生编译 |
| `librga.so.2` | 1.3.2（2021） | **1.10.5** |
| `libgstrockchipmpp.so` | 1.14-4（2021） | 同源码重编，链接新 MPP |

**为什么不能直接拷 SDK 的预编译库**：SDK buildroot 的库要求 `GLIBC_2.38`，板子是
2.35，拷进去会 `error while loading shared libraries: GLIBC_2.38 not found`。
所以 MPP / librga 都用 **板子上的 gcc 原生编译**。

## 现象与根因

- `dmesg` 里大量 `rga: ... failed to map buffer / request commit failed`
- 旧 `librga` 的 `RgaBlit()` 对 6.1 内核全部返回 `Invalid argument`
- GStreamer rockchip 插件靠 RGA 做每帧转换，于是每帧都失败重试
- 旧插件还用 `MPP_BUFFER_TYPE_DRM` 且不设 buffer 数上限；`mpi_dec_test` 用的是
  `ION + 24` 个 buffer

## 构建步骤

源码来自 SDK：

- MPP：`<SDK>/external/mpp`（**保留它的 `build/` 目录**，里面是 CMake 模块；
  不要把 `rockchip-mpp-develop.tar` 当源码，那是 install tree）
- librga：`<SDK>/external/linux-rga`
- 插件：`<SDK>/buildroot/.../build/gstreamer1-rockchip-master`（版本 1.14.4）

板子上需要 `gcc/g++/make/libdrm-dev` 和一个 aarch64 版 cmake
（Kitware 静态包 `cmake-3.28.3-linux-aarch64.tar.gz` 即可，解压到 `/opt`）。

```bash
# 1) 新版 MPP（板子上原生编译）
sudo scripts/build-mpp-native.sh /root/mppsrc /root/mppout

# 2) 新版 librga
sudo scripts/build-rga-native.sh /root/rgasrc /root/rgaout

# 3) GStreamer 插件（打了 0001-native-build-perf.patch）
#    $SDK 主机 sysroot 里的 gst 头是 1.24，板子运行时是 1.20.3：
#    必须把用于编译的 gstversion.h 改成 1.20，否则插件会被拒绝加载
#    （"incompatible version (plugin: 1.24, gst: 1.20)"）。
sudo scripts/build-gst-rockchipmpp-native.sh
```

插件补丁 `driver/gst-rockchipmpp/0001-native-build-perf.patch`：

- 缓冲组改用 `MPP_BUFFER_TYPE_ION`，并 `limit_config(..., 24)`
- 去掉 `MPP_SET_INPUT_TIMEOUT` / `MPP_SET_OUTPUT_TIMEOUT`（与 `mpi_dec_test` 一致）
- 编译时 **不定义 `HAVE_RGA`**（`driver/gst-rockchipmpp/config.h` 不定义它），
  避免旧插件逐帧走 RGA；`glupload/glcolorconvert` 在下游转 NV12→RGB

## 播放器（DSI）

旧方案是 Python + cairooverlay + kmssink，CPU 高且会卡死。现在用：

```
mppvideodec ! queue leaky ! glupload ! glcolorconvert ! glvideoflip ! glimagesink
```

- `scripts/openipc-gl-player.sh`：播放器（读 `/etc/openipc-rx.conf` 的 `RX_PORT`）
- `systemd/openipc-video-kms.service`：开机自启，替换原来的 Python OSD
- `driver/88xxau/88xxau.conf`：只开 `rtw_usb_rxagg_mode=2`
  （**不要**加 `rtw_rxgain_offset_*`：8812AU 的 HAL 根本不读这些参数，只有 8814A 用；
  远航需要满灵敏度，不能固定降增益）

> 近距离（1~2m）RSSI 到 -20 多 dBm 时 8812AU 前端会压缩丢包，这是接收机饱和。
> 8812AU 没有可用的“降增益”驱动旋钮（`rtw_rxgain_offset_*` 是 8814A 专用）。
> 台架测试请把天空端拿远或加 6~10dB 衰减器；飞行时用满增益，**不要**为了台架
> 流畅去降增益。

> **关键坑**：systemd 服务必须带 `GST_GL_API=gles2`（以及 `GST_GL_PLATFORM=egl`、
> `GST_GL_WINDOW=gbm`），否则 Mali 只支持 GLES2，绑桌面 GL 会报
> `Failed to bind OpenGL API: EGL_BAD_PARAMETER`。脚本里已经 export。

## 实测（2026-11）

- 天空端源：**27–30fps**，1280x720，H.265
- `mppvideodec ! fakesink`：**28.2fps**
- 完整 GL 链（含旋转）：**28.66fps，dropped=0**
- `wfb_rx`：RSSI **-28/-24 dBm**，近 15s 丢 **6 包**

> **测量陷阱**：不要用 `filesink` 写 `/tmp` 来测解码帧率。1280x720 NV12 每帧
> 1.38MB，27fps ≈ 37MB/s，写到 tmpfs 会把整条管线压到 **18fps 左右**，看起来像
> 解码慢。要用真实 sink 或 `fpsdisplaysink video-sink=fakesink` 测：
>
> ```bash
> gst-launch-1.0 -v ... ! mppvideodec ! fpsdisplaysink video-sink=fakesink sync=false
> ```

## 验证

```bash
systemctl is-active openipc-rx.service openipc-video-kms.service
journalctl -u openipc-video-kms.service -n 10 --no-pager
grep -m1 'Video Port0' /sys/kernel/debug/dri/0/summary   # ACTIVE
ps -eo pid,pcpu,comm | grep -E 'gst|wfb'
```

## 回滚

旧库/旧插件都备份在板子 `/root/`：

- `/root/librockchip_mpp.so.0.old`
- `/root/librga.so.2.1.0.old`
- `/root/libgstrockchipmpp.so.old`

覆盖回去后 `ldconfig` 并清 `~/.cache/gstreamer-1.0` 即可。

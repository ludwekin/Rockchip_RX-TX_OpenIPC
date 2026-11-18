# Rockchip RK3566 (LCKFB 泰山派 V10) — OpenIPC / wfb-ng 图传接收 → HDMI

一套已经在 **LCKFB 泰山派 V10 (RK3566)** 上跑通的 OpenIPC / wfb-ng 地面站接收方案：
RTL8812AU 监听 5.8G，`wfb_rx` 解密重组，RK MPP 硬解 H265，直接输出到 HDMI 显示器。

> 本仓库来自实际调试记录，包含：
> - 可用的 **HDMI boot 镜像**（11 月 4 日 #4 内核 + HDMI DTB）
> - 修复过的 **88XXau / rtl8812au 驱动**（128KB RX 缓冲、关闭 USB RX 聚合）及补丁
> - **wfb-ng + GStreamer + kmssink** 的完整启动/播放脚本
> - **断流自动重连看门狗**（天空端重启/图传断了会自动重启接收和播放）
> - 踩坑记录（内核/驱动 ABI、HDMI/DSI DTB、bcmdhd、信道、MPP fast-mode、Maskrom 写入限制、USB 供电）
>
> **不要提交任何 wfb-ng 密钥（`gs.key` / `drone.key`）到仓库。** 本仓库不包含密钥。

---

## 1. 已验证环境

| 项目 | 配置 |
|---|---|
| 板子 | LCKFB 泰山派 V10，RK3566，eMMC，HDMI |
| 系统 | Ubuntu 22.04.5 LTS (aarch64) |
| 内核 | `6.1.141 #4 SMP Wed Nov 4 03:13:47 EST 2026`（SDK 构建） |
| 无线网卡 | RTL8812AU-VS `0bda:881a`，USB2 |
| 驱动 | aircrack-ng/rtl8812au `v5.6.4.2` + 本仓库补丁 |
| wfb-ng | ~23.08，`/usr/local/bin/wfb_rx` |
| 天空端 | OpenIPC + wfb-ng TX，H265 1280x720@30，信道 161 HT20 |
| 显示 | HDMI 1280x720p60，`kmssink` + MPP 硬解 |
| DSI 屏 | 3.1" MIPI DSI 480x800，CST128A 触摸（i2c1 @0x38） |
| 实测 | RSSI -22 ~ -28 dBm，`wfb_rx` 正常收包，HDMI / DSI 均出图 |

> 版本相关：驱动必须和**运行中的内核**匹配。把为旧内核编译的 `88XXau.ko` 装到新内核上，
> 高码率收流时会 `skb_over_panic` 直接内核崩溃。换内核后请用本仓库补丁重新编译驱动。

---

## 2. 目录结构

```
.
├── boot/
│   ├── boot4-hdmi.itb          # 11/4 #4 内核 + HDMI DTB 的 FIT（写 p3）
│   ├── boot4-dsi.itb           # 11/4 #4 内核 + DSI 480x800 DTB（写 p3）
│   └── README.md               # 刷写/重建说明
├── driver/
│   ├── 88XXau.ko               # 预编译驱动（vermagic 6.1.141 SMP mod_unload aarch64）
│   ├── build.sh                # 交叉编译脚本
│   ├── patches/
│   │   └── 0001-rx-buffer-and-no-usb-rx-agg.patch
│   └── README.md
├── scripts/
│   ├── wfb-watchdog.sh         # 推荐：自动配置 + 收流 + 播放 + 断流重连
│   ├── wfb-dsi-osd.py          # DSI 480x800 横屏 + 半透明性能 OSD + 触摸翻页
│   ├── wfb-hdmi.sh             # 一次性启动版
│   ├── f3.sh                   # MPP 解码性能对比测试
│   ├── openipc-rx-setup.sh     # 旧版 monitor/channel 设置
│   ├── openipc-start.sh        # 旧版 wfb_rx 启动
│   ├── openipc-rx.conf         # 旧版配置
│   └── openipc-kms-osd.py      # 旧版 DSI 屏 OSD 播放（HDMI 不用）
├── systemd/
│   └── wfb-hdmi.service        # 运行 wfb-watchdog.sh
├── tools/
│   ├── patch_inplace.py        # 替换 FIT 内 fdt（保持布局，重算 hash）
│   ├── fdt-orig.dtb            # HDMI DTB（HDMI okay / DSI disabled）
│   └── fdt-dsi.dtb             # DSI 480x800 DTB（DSI okay / HDMI disabled）
├── touch/                      # CST128A 触摸驱动/模块/开机加载配置
├── docs/
│   ├── DEBUG_NOTES.md          # 详细踩坑记录
│   ├── DSI.md                  # 3.1" MIPI DSI + 触摸
│   └── AIR_TX.md               # 天空端 TX 侧参数模板
└── keys/README.md              # 密钥生成/配对说明（不含密钥）
```

---

## 3. 快速开始

### 3.1 刷 boot（HDMI 或 DSI）

> 本内核只有一个 CRTC：HDMI 和 DSI 不能同时用。HDMI 用 `boot4-hdmi.itb`，
> DSI 用 `boot4-dsi.itb`；DSI 详细步骤见 3.6 / `docs/DSI.md`。

目标板的分区：

```
p3 boot 64MB，起始 LBA 0x8000
p6 rootfs，PARTUUID=614e0000-0000
```

在板子已经能启动 Linux 的情况下，**用 dd 写 p3 最可靠**（Maskrom miniloader 对 >16MB 的
`wl` 写入可能截断，见 docs/DEBUG_NOTES.md）：

```bash
adb push boot/boot4-hdmi.itb /tmp/boot4-hdmi.itb
adb shell 'dd if=/tmp/boot4-hdmi.itb of=/dev/mmcblk0p3 bs=1M conv=fsync; sync'
adb shell reboot
```

启动后确认 HDMI：

```bash
cat /proc/device-tree/hdmi@fe0a0000/status   # okay
cat /sys/class/drm/card0-HDMI-A-1/status    # connected
```

> 如果你的 rootfs 不是 `PARTUUID=614e0000-0000`，请改 DTB 的 `/chosen/bootargs`。
> `boot4-hdmi.itb` 是 #4 内核 + HDMI DTB，基于 SDK 备份的 `boot_min.img` 用
> `tools/patch_inplace.py` 替换 fdt 生成；重建方法见 `boot/README.md`。

### 3.2 安装驱动

```bash
# 板子上（root）
cp driver/88XXau.ko /lib/modules/$(uname -r)/extra/88XXau.ko
depmod -a
echo 'blacklist 8812au' > /etc/modprobe.d/blacklist-8812au.conf
# 板载 SDIO WiFi 会和 88XXau 抢 cfg80211，接收图传时不要加载 bcmdhd
# （或用 modprobe -r bcmdhd 后再重载 88XXau）
modprobe 88XXau rtw_usb_rxagg_mode=0
```

如果你不是 #4 那个内核，请用 `driver/build.sh` 针对当前内核重新编译（见 `driver/README.md`）。

### 3.3 密钥（不要提交）

`wfb_keygen` 生成一对：

- 地面站：`/etc/gs.key`
- 天空端：`drone.key`

两者必须配对；天空端用 `drone.key`，地面用 `gs.key`。本仓库的 `wfb_rx` 命令使用：

```bash
wfb_rx -K /etc/gs.key -i 7669206 -p 0 -u 5600 wlxbcec23d80c81
```

`-i 7669206` 是流 ID，`-u 5600` 是本地 RTP 端口，必须和天空端一致。
**不要把 `gs.key` / `drone.key` 上传到 GitHub。** `.gitignore` 已排除 `*.key`。

### 3.4 安装自动启动（推荐）

```bash
sudo install -m755 scripts/wfb-watchdog.sh /usr/local/sbin/
sudo cp systemd/wfb-hdmi.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now wfb-hdmi.service
```

`wfb-watchdog.sh` 会：

- 停掉 NetworkManager / wpa_supplicant / hostapd，卸载 bcmdhd
- 加载 88XXau，设置 **monitor + 161 HT20**
- 启动 `wfb_rx` 和 GStreamer → MPP 硬解 → `kmssink` HDMI
- 检测 `/tmp/wfb_rx.log` 是否持续更新；**超过 6 秒没有新包**就自动重启
  `wfb_rx` + 播放器
- 如果接口掉回 type=1 / 信道 6，会自动恢复 monitor；必要时重载 88XXau
- 天空端重启、session 变化、HDMI 断开重连，都能自动恢复

### 3.5 GStreamer 管线（核心）

```bash
gst-launch-1.0 -e udpsrc port=5600 buffer-size=33554432 \
  caps="application/x-rtp, media=(string)video, payload=(int)97, clock-rate=(int)90000, encoding-name=(string)H265" \
  ! rtpjitterbuffer latency=0 mode=none \
  ! rtph265depay ! h265parse \
  ! video/x-h265,stream-format=byte-stream,alignment=au \
  ! mppvideodec \
  ! queue leaky=downstream max-size-buffers=1 max-size-time=0 max-size-bytes=0 \
  ! videoconvert \
  ! kmssink force-modesetting=true sync=false
```

关键点：

- **不要用 `mppvideodec fast-mode=true`**。在 RK3566 + 这条 H265 流上，fast-mode 会
  只出第一帧后卡死（`f3.sh` 实测 fast 模式 0 帧）。用默认的 `mppvideodec`。
- `videoconvert` 是必要的：VOP 的主平面只吃 RGB；直接 NV12 送 `plane-id=98`
  会 `failed to configure video mode`。
- `kmssink force-modesetting=true sync=false`：不等待 vsync，直接翻页。
- `queue leaky=downstream ... max-size-buffers=1`：kmssink 慢时丢旧帧，避免整条管线堵住。
- `rtpjitterbuffer latency=0` 是最低延迟；网络抖动大时改成 `10~50`。
- HDMI 输出为 1280x720p60（视频 1280x720@30）。

### 3.6 3.1" MIPI DSI（480x800）

同一路流也可以输出到 3.1" MIPI DSI 屏（HDMI 关闭）。这块内核只有一个 CRTC，
**HDMI 和 DSI 不能同时用**，需要刷对应的 boot：

| 显示 | boot | DTB |
|---|---|---|
| HDMI 1280x720p60 | `boot/boot4-hdmi.itb` | `tools/fdt-orig.dtb` |
| MIPI DSI 480x800 | `boot/boot4-dsi.itb` | `tools/fdt-dsi.dtb` |

刷 DSI（板子 Linux 里 dd 到 p3）：

```bash
adb push boot/boot4-dsi.itb /tmp/
adb shell 'dd if=/tmp/boot4-dsi.itb of=/dev/mmcblk0p3 bs=1M conv=fsync; sync'
adb shell reboot
```

确认：

```bash
cat /proc/device-tree/dsi@fe070000/status   # okay
cat /proc/device-tree/hdmi@fe0a0000/status  # disabled
cat /sys/class/drm/card0-DSI-1/status       # connected
```

`wfb-watchdog.sh` 会自动识别 DSI，启动 `scripts/wfb-dsi-osd.py`：

- 视频 1280x720 横屏，`videoscale add-borders` 到 **480x270**，480x800 面板上下留黑边；
- OSD **400x240（1/4 屏）** 半透明黑底（0.45），横向；
- 触摸（CST128A）切换两页：
  - WFB：CH/频率、RSSI、码率、RTP p/s、LOST、FPS、STREAM；
  - RK3566：CPU%/频率、LOAD、SOC/GPU 温度、内存、DDR/GPU/NPU/VDEC、UP；
- 不使用 `mppvideodec fast-mode=true`（会卡第一帧）。

触摸 CST128A（i2c1 @0x38）：

```bash
cp touch/cst128a_ts.ko /lib/modules/$(uname -r)/extra/
depmod -a
cp touch/cst128a.conf /etc/modules-load.d/cst128a.conf
modprobe cst128a_ts
evtest /dev/input/event5
```

详细说明见 `docs/DSI.md`。

---

## 4. 天空端（TX）需要匹配的参数

详见 `docs/AIR_TX.md`。最低要求：

| 参数 | 值 |
|---|---|
| 编码 | H265 |
| 分辨率/帧率 | 1280x720 @ 30 |
| 信道/带宽 | 161 / HT20 |
| 流 ID | 7669206 |
| 密钥 | 天空端 `drone.key` ↔ 地面 `/etc/gs.key` |
| 地面 RTP 端口 | UDP 5600 |

---

## 5. 常见问题

| 现象 | 原因/解决 |
|---|---|
| `wfb_rx: unknown encapsulation` | 网卡不在 monitor（sysfs type 不是 803）→ 重设 `iw set type monitor`；必要时重载 88XXau |
| 信道锁不住，一直是 6 / EBUSY | bcmdhd 还在，或驱动状态脏 → `ip link set wlan0 down; modprobe -r bcmdhd`，**卸载再重载 88XXau** 后设 161 |
| `Unable to decrypt packet` / 无画面 | `gs.key` 和天空端 `drone.key` 不配对；正确时日志会有 `SESSION`，错误时会大量 decrypt |
| 只出第一帧 | `mppvideodec fast-mode=true`；改成默认（无 fast-mode） |
| HDMI 黑屏 / DRM 不 ACTIVE | 缺 `videoconvert` 或 `force-modesetting`；检查 `cat /sys/kernel/debug/dri/0/summary` |
| DSI 黑屏 | 当前 boot 是 HDMI 版；刷 `boot4-dsi.itb`（内核只有一个 CRTC，HDMI/DSI 互斥） |
| 触摸无反应 | 加载 `cst128a_ts`，检查 DTB `i2c@fe5a0000/tp@38` 和 `/dev/input/event5`；见 `docs/DSI.md` |
| 画面卡住、天空端重启后不恢复 | 运行 `wfb-watchdog.sh`（会自动重启 `wfb_rx` + 播放器） |
| 板子/电脑重启、USB 掉 | 供电不足。USB2 口只有 500mA，8812AU 收流时电流冲高；用**带电源的 USB Hub** 或 USB3 蓝口 |
| 内核 panic `skb_over_panic` | 驱动和内核不匹配；用本仓库补丁针对当前内核重编 |
| Maskrom 写入后不启动 | `rkdeveloptool wl/wlx` 对 >16MB 的写入可能截断；用 Linux 里 `dd` 或官方 `upgrade_tool UF`（见 docs/DEBUG_NOTES.md） |

---

## 6. 重建 boot 镜像

`boot4-hdmi.itb` 的生成流程（需要 LCKFB/Rockchip SDK 里的 `backup/boot_min.img`）：

```bash
python3 tools/patch_inplace.py /path/to/boot_min.img tools/fdt-orig.dtb boot4-hdmi.itb
```

- `boot_min.img`：11/4 #4 内核 + DSI DTB 的原始 FIT（SDK 备份）
- `fdt-orig.dtb`：HDMI 可用的 DTB（`hdmi=okay`、`dsi=disabled`）
- `patch_inplace.py` 只替换 FIT 里的 fdt 数据并重算 sha256，保持 kernel/resource 布局不变

也可以用 SDK 自己的 `resource_tool + mkbootimg` 重新打包，见 `boot/README.md`。

---

## 7. 许可与来源

- 本仓库的脚本/文档：MIT（见 LICENSE）
- `driver/` 补丁与 `88XXau.ko`：GPLv2，源自
  [aircrack-ng/rtl8812au](https://github.com/aircrack-ng/rtl8812au) v5.6.4.2
- `boot/boot4-hdmi.itb`：包含 GPLv2 Linux 内核（Rockchip SDK 构建）和厂商 DTB/resource；
  再分发前请确认 Rockchip/LCKFB SDK 的授权条款
- wfb-ng: https://github.com/svpcom/wfb-ng
- OpenIPC: https://openipc.org
- Rockchip Linux SDK / LCKFB 泰山派

> 本仓库不包含任何密钥、私有数据或完整 SDK。

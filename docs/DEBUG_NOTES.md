# 调试记录 / 踩坑（RK3566 泰山派 + wfb-ng + RTL8812AU + HDMI）

这份记录按“现象 → 原因 → 解决”整理，方便复现时少走弯路。

---

## 1. 内核与驱动的 ABI 必须匹配（最关键的坑）

**现象**：RTL8812AU 能加载、AP/收包看起来正常，但 `wfb_rx` 一收高码率视频就内核 panic：

```
skbuff: skb_over_panic ... usb_read_port_complete+... [88XXau]
```

**原因**：

- 板子当时跑的是 **11 月 4 日 03:13 构建的 6.1.141 #4 内核**；
- 备份的 `88XXau.ko` 是更早（5 月头文件）编译的，vermagic 虽然都是 `6.1.141`，
  但结构体/ABI 与运行内核并不完全一致；
- 驱动的 RX 缓冲只有 32KB（或旧定制版约 64KB），遇到 USB 聚合大包就写越界。

**解决**：

- 用和运行内核匹配的源码/头文件重新编译驱动；
- 同时把 `MAX_RECVBUF_SZ` 改为 **0x20000 (128KB)**；
- 关闭 `CONFIG_USB_RX_AGGREGATION`（降低大包溢出风险，也降低一点延迟）；
- 补丁见 `driver/patches/0001-rx-buffer-and-no-usb-rx-agg.patch`。

```c
/* include/rtl8812a_recv.h */
-#define MAX_RECVBUF_SZ (32768)
+#define MAX_RECVBUF_SZ (0x20000)

/* include/rtl_autoconf.h */
-    #define CONFIG_USB_RX_AGGREGATION 1
+/* #define CONFIG_USB_RX_AGGREGATION 1 */
```

修复后驱动在当前内核上稳定收流，不再 panic。

---

## 2. HDMI / DSI：RK3566 这套内核只暴露一个 CRTC/VP0

**现象**：换 DSI 屏后 HDMI 没输出；或者刷了 SDK 的 `boot.img` 后 HDMI 黑屏。

**原因**：

- 泰山派这块 BSP 内核的 VOP 只给 **VP0** 分配了 plane（`vp1/vp2 assign plane mask: 0x0`），
  DSI 和 HDMI 不能同时用一个 CRTC；
- SDK 的 `kernel-6.1/boot.img` 里打包的 DTB 是 **DSI enabled / HDMI disabled**；
- 用户之前为了 DSI 屏把 HDMI 关掉了。

**解决**：

- 用 HDMI DTB：`hdmi@fe0a0000 = okay`、`dsi@fe070000 = disabled`、
  `route-hdmi = okay`、`route-dsi1 = disabled`；
- 本仓库 `tools/fdt-orig.dtb` 就是这份；
- 用 `tools/patch_inplace.py` 把原始 FIT（#4 内核 + DSI DTB）里的 fdt 换成 HDMI DTB，
  保持 kernel/resource 布局和 hash：

```bash
python3 tools/patch_inplace.py boot_min.img tools/fdt-orig.dtb boot4-hdmi.itb
```

`boot4-hdmi.itb` 是 #4 内核 + HDMI DTB + resource。启动后：

```bash
cat /proc/device-tree/hdmi@fe0a0000/status   # okay
cat /sys/class/drm/card0-HDMI-A-1/status    # connected
```

---

## 3. bcmdhd / NetworkManager / regulatory：信道锁不住

**现象**：

- `iw dev wlan set type monitor` 成功；
- `iw dev wlan set channel 161 HT20` 返回 0，但 `iw info` 仍是 **channel 6**；
- 或者 down 状态报 `-16 (Device or resource busy)`；
- dmesg 大量 `[dhd] CFG80211-ERROR ... wrong cfg ptr`。

**原因**：

- 板载 SDIO WiFi 使用 `bcmdhd`，和 `88XXau` 共用 cfg80211；
- NetworkManager/wpa_supplicant 还在管理 `wlan0`；
- 驱动在 AP/station 状态下直接切 monitor，信道不会真的切；
- 需要**先卸载 bcmdhd，再重载 88XXau**，然后设置 monitor/channel。

**可用顺序**：

```bash
systemctl stop NetworkManager.service wpa_supplicant.service
pkill -x wpa_supplicant
pkill -x hostapd
ip link set wlan0 down
modprobe -r bcmdhd
modprobe -r 88XXau
sleep 2
modprobe 88XXau rtw_usb_rxagg_mode=0
sleep 4

IF=wlxbcec23d80c81
ip link set $IF down
iw dev $IF set type monitor
iw dev $IF set monitor otherbss fcsfail
ip link set $IF up
iw reg set US
iw dev $IF set channel 161 HT20
iw dev $IF info
cat /sys/class/net/$IF/type     # 应该是 803
```

**判断 monitor 是否真的生效**：看 `cat /sys/class/net/$IF/type`，正常 monitor 是 **803**；
`iw dev info` 显示 `type monitor` + `channel 161`。只看 `iw info` 不够，驱动可能回退。

`wfb-watchdog.sh` 用 `type=803 && channel=161` 作为判断，掉了会自动恢复，必要时重载驱动。

---

## 4. MPP 解码：`fast-mode=true` 会卡第一帧

**现象**：

- 画面出第一帧后不动；
- `f3.sh` 测试：

```
no fast-mode:     180 frames/10s
queue+no fast:    174 frames/10s
jb latency=0:     156 frames/10s   # 这一项用了 fast-mode
identity 5s:      0 帧（fast-mode + jb latency=30）
```

**原因**：`mppvideodec fast-mode=true` 与这条 H265 流/当前内核组合不稳定，会停住；
`fast-mode` + `rtpjitterbuffer latency=30` 尤其容易卡死。

**解决**：

- 用 **默认 `mppvideodec`（不要 fast-mode）**；
- 解码后加 `queue leaky=downstream max-size-buffers=1`，避免 kmssink 把管线堵死；
- 这是本仓库最终采用的管线。

---

## 5. kmssink：NV12 直出 / RGB 转换

**现象**：

- 直接用 `mppvideodec ! kmssink` 时，`Video Port0: DISABLED`，没画面；
- 指定 `plane-id=98` 直送 NV12，报 `failed to configure video mode`。

**原因**：

- VOP 主平面 (Smart0, plane 58) 只支持 RGB；
- 支持 NV12 的 plane 98 在这个 kmssink/驱动组合下配置失败；
- 需要 `videoconvert` 转成 RGB，再送主平面。

**可用管线**：

```
... ! mppvideodec
    ! queue leaky=downstream max-size-buffers=1 max-size-time=0 max-size-bytes=0
    ! videoconvert
    ! kmssink force-modesetting=true sync=false
```

HDMI 输出 **1280x720p60**。

---

## 6. wfb-ng 密钥：必须和天空端 `drone.key` 成对

**现象**：

- 有 `PKT` 统计，但画面不更新/只第一帧；
- `/tmp/wfb_rx.log` 持续出现 `Unable to decrypt packet`；
- 正确密钥时日志会出现 `SESSION 0:1:8:12` 之类的会话行。

**原因**：`/etc/gs.key` 和天空端 `drone.key` 不配对。

**排查**：

```bash
wfb_rx -K /etc/gs.key -i 7669206 -p 0 -u 5600 wlxbcec23d80c81
grep -E 'SESSION|PKT|Unable to decrypt' /tmp/wfb_rx.log | tail
```

- 有 `SESSION`、`PKT` 持续增长、无大量 decrypt → key/信道/流 ID 正确；
- 大量 `Unable to decrypt`、没有 SESSION → key 不对，换回和天空端配对的那把。

**注意**：本仓库**不包含**任何 `gs.key`/`drone.key`，请自行 `wfb_keygen` 或用你自己的配对密钥。

---

## 7. 天空端重启 / 断流：自动重连

**现象**：天空端重启后，地面画面卡住不恢复；`wfb_rx` 可能还活着但 session 已变，
或者播放器停在旧 RTP 时间戳上。

**解决**：

- 手动：重启 `wfb_rx` + 播放器；
- 自动：`wfb-watchdog.sh` 监控 `/tmp/wfb_rx.log` 的 mtime；
  超过 6 秒没有新包 → 重启 `wfb_rx` + 播放器；
- watchdog 还会检查接口是否掉出 monitor（type 不是 803 / 信道不是 161），
  自动恢复，必要时重载 88XXau；
- 实测：`kill -9` 掉 `wfb_rx` 后，几秒内自动起新的 `wfb_rx` + 播放器，HDMI 恢复 ACTIVE。

---

## 8. USB 供电：电脑 USB2 口 500mA 不够

**现象**：

- 刷机/收流时**电脑直接重启**；
- 板子 USB 枚举时有时无；
- 驱动/解密偶发错误、画面卡顿。

**原因**：

- 板子只从电脑 USB2 口取电（500mA），RTL8812AU + HDMI + eMMC 写入时电流冲高，
  导致掉压/过流；
- 这也是“以前在 HDMI 上不卡、现在有点慢”的可能原因之一。

**建议**：

- 用 **带电源的 USB Hub**，或插电脑的 **USB3 蓝色口**（900mA）；
- 有条件给板子独立 5V/3A 供电（Type-C/DC），电脑只接数据；
- 供电稳定后再评估延迟/丢包。

---

## 9. Maskrom / Loader 写入限制（>16MB 的 boot 镜像）

**现象**：

- `rkdeveloptool wl 0x8000 boot.img` 显示 100%，但读回校验不一致；
- 读回 16MB 之后全是 `0xCC`；
- 板子 HDMI 停在 logo 后反复重启（内核被截断）。

**原因**：

- 当前 miniloader/Loader 模式对大文件写入有限制：实测只可靠写前 ~16MB，
  到 eMMC 绝对地址 32MB 之后就读回 `0xCC`；
- `db` 下载完整 loader 在 **Loader 模式** 不支持（提示
  `The device does not support this operation!`），需要真正的 **Maskrom**。

**解决（按可靠性排序）**：

1. **在板子 Linux 里 dd**（最可靠，本仓库推荐）：
   ```bash
   adb push boot4-hdmi.itb /tmp/
   adb shell 'dd if=/tmp/boot4-hdmi.itb of=/dev/mmcblk0p3 bs=1M conv=fsync; sync'
   ```
2. **官方 `upgrade_tool UF` + 只含 boot 的 update.img**：
   用 SDK 的 `afptool`/`rkImageMaker` 打包 `parameter + bootloader + boot`，
   不打包 rootfs；`upgrade_tool UF` 的升级协议能写大分区。
3. 真正 Maskrom + `db rk356x_spl_loader_*.bin`，再完整写入。

本仓库的 `boot4-hdmi.itb` 是 41.7MB，**不要**用 `wl` 一次写；用 dd。

---

## 10. 关于“以前不卡、现在有延迟”

地面管线已经压到最低（`rtpjitterbuffer=0`、队列 1 帧、无 fast-mode）。
如果仍觉得慢，优先排查：

1. **供电**：USB2 500mA → 带电源 Hub/USB3；
2. **天空端编码参数**：H265/H264、GOP、码率、分辨率是否变了；
3. **链路丢包/解密错误**：`/tmp/wfb_rx.log` 的 `PKT`/`Unable to decrypt`；
4. **帧率**：`f3.sh` 看实际解码帧数（本环境约 18fps，取决于天空端实际输出）。

---

## 11. 3.1" MIPI DSI 480x800 / CST128A 触摸

- 内核只有一个 CRTC/VP0：**HDMI 和 DSI 不能同时用**；
  HDMI 刷 `boot4-hdmi.itb`，DSI 刷 `boot4-dsi.itb`（#4 内核 + DSI DTB）。
- DSI 模式：`480x800p60`，`Connector: DSI-1`，`Video Port0 ACTIVE`。
- DSI 管线（watchdog 自动识别）：

```
... ! mppvideodec ! queue leaky=downstream max-size-buffers=1 ...
    ! videoconvert ! videoflip method=counterclockwise
    ! videoscale add-borders=true
    ! video/x-raw,width=480,height=800 ! kmssink sync=false
```

- 仍然不要用 `mppvideodec fast-mode=true`。
- 触摸 CST128A：i2c1 `i2c@fe5a0000` @0x38；`cst128a_ts.ko` +
  `/etc/modules-load.d/cst128a.conf`；输入设备通常 `/dev/input/event5`。
- 初始化可能有两条 `hyn_cst128_ts_write: write error, addr=0x0/0xa4`，
  但 input 会注册，触摸事件正常。
- 详细步骤见 `docs/DSI.md`，触摸文件在 `touch/`。

## 附：常用确认命令

```bash
uname -a
cat /sys/class/net/wlxbcec23d80c81/type        # 803 = monitor
iw dev wlxbcec23d80c81 info
cat /sys/class/drm/card0-HDMI-A-1/status
cat /sys/kernel/debug/dri/0/summary | head
tail -5 /tmp/wfb_rx.log
tail -5 /tmp/wfb-watchdog.log
```

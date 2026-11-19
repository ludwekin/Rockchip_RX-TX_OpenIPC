# 本机（x86 Ubuntu）接收 wfb-ng

除了 RK3566 板子，本机也可以直接收天空端。实测环境：

| 项目 | 配置 |
|---|---|
| 系统 | Ubuntu 22.04 x86_64 |
| 内核 | 6.8.0-149-generic |
| 接收网卡 | RTL8812AU-VS `0bda:881a`（aircrack `88XXau`） |
| 上网/备份网卡 | RTL8852BU `0bda:b832`（`rtw89`） |
| wfb-ng | `/usr/bin/wfb_rx`（apt 包） |
| 播放 | GStreamer `avdec_h265 ! autovideosink` |

分工：

- **RTL8812AU**：monitor 161 收图传（主方案）
- **RTL8852BU**：managed 连正常 WiFi 上网；需要时也可切 monitor 做备份 RX

---

## 1. RTL8812AU 驱动（aircrack v5.6.4.2）

```bash
sudo apt install dkms git build-essential linux-headers-$(uname -r)
git clone -b v5.6.4.2 https://github.com/aircrack-ng/rtl8812au.git
cd rtl8812au
```

在 **6.8.0-149** 上直接编译会报：

```
error: initialization of ‘int (*)(struct wiphy *, struct net_device *, struct cfg80211_chan_def *)’
from incompatible pointer type ‘int (*)(struct wiphy *, struct cfg80211_chan_def *)’
```

原因是 149 内核 backport 了新的 `set_monitor_channel` 三参数 API，而驱动只对 `>= 6.13` 做了判断。
应用本仓库补丁：

```bash
patch -p1 < /path/to/driver/host-8812au/0001-cfg80211-set-monitor-channel-6.8.patch
```

或手动把 `os_dep/linux/ioctl_cfg80211.c` 里：

```c
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 13, 0))
```

改成：

```c
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 8, 0))
```

然后：

```bash
sudo make dkms_install
sudo modprobe 88XXau
iw dev
```

会出现接口 `wlxbcec23d80c81`（RTL8812AU）。

## 2. 接收（主方案：8812AU）

```bash
sudo ./scripts/host-rx-8812au.sh
# 或者手动：
sudo ip link set wlxbcec23d80c81 down
sudo iw dev wlxbcec23d80c81 set type monitor
sudo iw dev wlxbcec23d80c81 set monitor otherbss fcsfail
sudo ip link set wlxbcec23d80c81 up
sudo iw reg set US
sudo iw dev wlxbcec23d80c81 set channel 161 HT20
sudo wfb_rx -K /etc/gs.key -i 7669206 -p 0 -u 5600 wlxbcec23d80c81
```

确认：

```bash
sudo tail -f /root/wfb_rx.log
# SESSION 1
# PKT ... 持续增长
# decrypt_errors 0
```

> `wfb_rx` 必须以 root 运行，否则：
> `Error: pcap_activate failed: socket: Operation not permitted`

## 3. 本机播放

```bash
./scripts/host-player.sh
# 或：
gst-launch-1.0 -e udpsrc port=5600 buffer-size=33554432 \
  caps="application/x-rtp, media=(string)video, payload=(int)97, clock-rate=(int)90000, encoding-name=(string)H265" \
  ! rtpjitterbuffer latency=50 mode=none \
  ! rtph265depay ! h265parse \
  ! avdec_h265 ! autovideosink sync=false
```

## 4. RTL8852BU 上网 / 备份 RX

切回 managed 上网（脚本 `scripts/host-internet-8852bu.sh`）：

```bash
sudo ip link set wlx6c1ff7475509 down
sudo iw dev wlx6c1ff7475509 set type managed
sudo ip link set wlx6c1ff7475509 up
sudo nmcli device set wlx6c1ff7475509 managed yes
sudo nmcli connection up JUSHI_12
```

备份 RX（脚本 `scripts/host-backup-rx-8852bu.sh`，会断本机 WiFi）：

```bash
sudo nmcli device set wlx6c1ff7475509 managed no
sudo ip link set wlx6c1ff7475509 down
sudo iw dev wlx6c1ff7475509 set type monitor
sudo ip link set wlx6c1ff7475509 up
sudo iw reg set US
sudo iw dev wlx6c1ff7475509 set channel 161 HT20
sudo wfb_rx -K /etc/gs.key -i 7669206 -p 0 -u 5600 wlx6c1ff7475509
```

> 8852BU（rtw89）实测 **RX 可用**；但 **TX/注入** 不建议。

## 5. 密钥

`/etc/gs.key` 必须和天空端 `drone.key` 配对。只是“能收到包”不够——如果日志出现：

```
Unable to decrypt session key
```

就是 key 不对，换回和天空端配对的那把。**不要把 key 提交到仓库**。

本机原来的 `/etc/gs.key` 可能和板子/天空端不是同一把；切换时先备份：

```bash
sudo cp -a /etc/gs.key /root/gs.key.host.bak
```

## 6. 常见问题

| 现象 | 原因 |
|---|---|
| `pcap_activate failed: Operation not permitted` | `wfb_rx` 没用 root |
| `Unable to decrypt session key` | key 和天空端不配对 |
| 6.8.0-149 编译失败 | `set_monitor_channel` 三参数 API，应用本仓库补丁 |
| 8812AU 没有接口 | `modprobe 88XXau` 失败/驱动未装当前内核 |
| 切 monitor 后不能上网 | 被用作 RX 的网卡无法同时 managed；用另一张卡上网 |
| 8852BU 收不到 | 确认 `rtw89` monitor + 161；它只建议做备份 RX |

## 7. 能收 wfb-ng 的网卡（参考）

- RTL8812AU / RTL8814AU / RTL8811AU / RTL8821AU
- RTL8812EU / RTL8822EU（`88x2eu`）
- RTL8852AU / 8852BU / 8832AU（`rtw89`，RX 可用）
- MT7612U / MT7610U（`mt76x2u` / `mt76x0u`）
- MT7921AU / MT7922（`mt7921u` / `mt7922`）
- AR9271（`ath9k_htc`，2.4G）
- AR9280 / AR9287（`ath9k`，PCIe）

RX 大多可行；TX/注入最稳的是 RTL8812AU/8814AU、MT7612U、AR9271。

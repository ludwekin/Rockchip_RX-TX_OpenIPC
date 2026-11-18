# RTL8812AU (88XXau) 驱动补丁 / 预编译

本目录是 **aircrack-ng/rtl8812au v5.6.4.2** 的补丁和预编译模块，用于 RK3566 泰山派
接收 OpenIPC/wfb-ng 图传。

## 补丁内容

`patches/0001-rx-buffer-and-no-usb-rx-agg.patch`：

1. `MAX_RECVBUF_SZ`：`32768` → `0x20000`（128KB）
   - 避免高码率 USB RX 聚合包触发 `skb_over_panic`。
2. 关闭 `CONFIG_USB_RX_AGGREGATION`
   - 降低大包溢出风险，也略微降低延迟。
   - 如果你需要更高吞吐，可以重新打开聚合，但请保留 128KB 缓冲。

## 从源码编译

```bash
git clone -b v5.6.4.2 https://github.com/aircrack-ng/rtl8812au.git
cd rtl8812au
patch -p1 < /path/to/0001-rx-buffer-and-no-usb-rx-agg.patch

# 方式 A：板子上原生编译
sudo apt install build-essential linux-headers-$(uname -r)
KSRC=/lib/modules/$(uname -r)/build ./build.sh

# 方式 B：主机交叉编译（示例：LCKFB/Rockchip SDK）
export KSRC=/path/to/tspi_sdk/extracted_sdk/kernel-6.1
export CROSS_COMPILE=/path/to/tspi_sdk/extracted_sdk/prebuilts/gcc/linux-x86/aarch64/\
gcc-arm-10.3-2021.07-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-
./build.sh
```

`build.sh`：

```bash
#!/bin/bash
set -euo pipefail
KSRC="${KSRC:-/lib/modules/$(uname -r)/build}"
KVER="${KVER:-6.1.141}"
CROSS_COMPILE="${CROSS_COMPILE:-aarch64-linux-gnu-}"
make -j"$(nproc)" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" \
     KSRC="$KSRC" KVER="$KVER" modules
```

产物是 `88XXau.ko`。

## 预编译模块

`88XXau.ko`：

- `vermagic: 6.1.141 SMP mod_unload aarch64`
- 使用 LCKFB/Rockchip SDK 的 6.1.141 内核树（11 月 4 日构建）编译；
- 实测可加载于 `6.1.141 #4 SMP Wed Nov 4 03:13:47 EST 2026` 并稳定收流；
- **内核构建不同/结构体变化时请重新编译**，不要混用。

安装：

```bash
cp 88XXau.ko /lib/modules/$(uname -r)/extra/88XXau.ko
depmod -a
echo 'blacklist 8812au' > /etc/modprobe.d/blacklist-8812au.conf
modprobe 88XXau rtw_usb_rxagg_mode=0
```

## monitor 模式注意事项

板载 SDIO WiFi（`bcmdhd`）和 88XXau 共用 cfg80211，必须先把 bcmdhd 拿掉，
并在 bcmdhd 卸载后**重载 88XXau**，否则 `iw set channel` 会返回 0 但信道不变：

```bash
systemctl stop NetworkManager wpa_supplicant
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
cat /sys/class/net/$IF/type      # 803
```

`scripts/wfb-watchdog.sh` 已经封装了这套逻辑。

## 许可

驱动源码与补丁来自 [aircrack-ng/rtl8812au](https://github.com/aircrack-ng/rtl8812au)，
GPLv2。预编译 `.ko` 同样按 GPLv2 分发。

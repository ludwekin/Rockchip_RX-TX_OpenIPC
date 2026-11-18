# 脚本说明

推荐使用 **wfb-watchdog.sh**：

```bash
sudo install -m755 wfb-watchdog.sh /usr/local/sbin/
sudo cp ../systemd/wfb-hdmi.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now wfb-hdmi.service
```

它会自动：停 NM/wpa/hostapd → 卸 bcmdhd → 加载 88XXau → monitor 161 HT20 →
启动 `wfb_rx` → 启动 GStreamer（MPP 硬解 + kmssink HDMI），并在断流 6 秒后
自动重启接收和播放器。

| 文件 | 用途 |
|---|---|
| `wfb-watchdog.sh` | 推荐；自动配置 + 收流 + 播放 + 断流重连 |
| `wfb-hdmi.sh` | 一次性启动（不监控/不重连） |
| `f3.sh` | MPP 解码性能对比（no fast / queue / jb latency） |
| `openipc-rx-setup.sh` | 旧版 monitor/channel 设置脚本 |
| `openipc-start.sh` | 旧版 wfb_rx 启动 |
| `openipc-rx.conf` | 旧版配置（IFACE/CH/BW/RX_PORT） |
| `openipc-kms-osd.py` | 旧版 DSI 480x800 OSD 播放，HDMI 不使用 |

注意：`wfb-watchdog.sh` 里的流 ID `7669206`、信道 `161`、`/etc/gs.key` 必须和你的天空端一致。

# 天空端（TX）参数模板

本仓库的地面站（RX）已经完整验证；天空端是 **OpenIPC + wfb-ng TX**。
不同 OpenIPC 镜像的 `wfb_tx`/`wifibroadcast.cfg` 写法可能不同，下面只列**必须匹配**的参数，
请按你天空端实际镜像填写。

## 必须和地面端一致

| 参数 | 本仓库使用值 | 说明 |
|---|---|---|
| 编码 | H265 | 地面 `rtph265depay`/`mppvideodec` |
| 分辨率/帧率 | 1280x720 @ 30 | |
| 射频信道 | **161** | 5.8G，地面 `iw set channel 161 HT20` |
| 带宽 | **HT20** | |
| wfb-ng 流 ID | **7669206** | 地面 `wfb_rx -i 7669206` |
| 加密密钥 | 天空端 `drone.key` ↔ 地面 `/etc/gs.key` | 必须成对 |
| 地面 RTP 端口 | UDP 5600 | `wfb_rx -u 5600` |

## OpenIPC 侧检查

1. **视频编码**：确认 OpenIPC 的 `majestic`/`vdec` 输出 H265、1280x720@30。
2. **wfb-ng TX**：确认 `wfb_tx` 使用的信道/带宽/流 ID 与上表一致，并且使用和地面
   `gs.key` 配对的 `drone.key`。
3. **天线/功放**：确认 TX 射频口接的是 5.8G 天线，信道 161 在法规域内可用。
4. **重启后的 session**：天空端重启会建立新 session；地面 `wfb-watchdog.sh` 会自动
   重启接收和播放。若手动运行，重启 `wfb_rx` + GStreamer 即可。

## 通用 wfb-ng TX 示例（按版本调整）

> 以下仅示意参数，不要直接照抄；不同 wfb-ng 版本的 `wfb_tx` 参数名不同。

```bash
# 天空端（示意）
wfb_tx -K /etc/drone.key \
       -i 7669206 \
       -p 0 \
       -C 161 -B 20 \
       <wlan_iface>
```

`wfb-ng` 的 `wfb_tx`/`wfb_rx` 详细参数请以你镜像里的
`wfb_tx --help` / `wifibroadcast.cfg` 为准：

- https://github.com/svpcom/wfb-ng
- https://openipc.org

## 不要提交密钥

`drone.key` / `gs.key` 只放在设备上，不要提交到本仓库。仓库 `.gitignore` 已排除 `*.key`。

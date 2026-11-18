# wfb-ng 密钥（不要提交）

本仓库不包含任何密钥。请自行生成/使用你自己的配对密钥。

## 生成

使用 wfb-ng 的 `wfb_keygen`：

```bash
wfb_keygen
# 生成 gs.key（地面）和 drone.key（天空端）
```

## 部署

- 地面站：把 `gs.key` 放到 `/etc/gs.key`，权限 600；
- 天空端：把配对的 `drone.key` 放到天空端对应位置；
- 两边必须是**同一对**，否则 `wfb_rx` 会出现大量
  `Unable to decrypt packet`，并且没有 `SESSION`。

本仓库的地面命令：

```bash
wfb_rx -K /etc/gs.key -i 7669206 -p 0 -u 5600 wlxbcec23d80c81
```

## 安全

`.gitignore` 已排除 `*.key` / `gs.key` / `drone.key`。
不要把密钥贴到 issue、README、日志或截图里。

# CST128A 触摸（3.1" MIPI DSI 屏）

- 触摸控制器：CST128A，i2c1 `i2c@fe5a0000`，地址 `0x38`
- DTB 节点：`i2c@fe5a0000/tp@38`，`compatible = "hyn,cst128a"`
- 驱动：`cst128a_ts.ko`（本目录预编译；源码 `cst128a_ts.c` + `hyn_core.c`）
- 输入设备：`CST128 TouchScreen`，通常是 `/dev/input/event5`

## 安装

```bash
cp cst128a_ts.ko /lib/modules/$(uname -r)/extra/
depmod -a
cp cst128a.conf /etc/modules-load.d/cst128a.conf
modprobe cst128a_ts
```

## 验证

```bash
dmesg | grep -i cst
cat /proc/bus/input/devices | grep -A6 CST128
evtest /dev/input/event5
```

初始化时可能出现两条 `hyn_cst128_ts_write: write error`，但输入设备仍会注册，
触摸事件正常。若完全无事件，检查 DTB 的 `tp@38`（reset/irq gpio）和排线。

## 构建

`Makefile`/`Kconfig` 是模块构建入口；需要与运行内核匹配的头文件：

```bash
make -C /lib/modules/$(uname -r)/build M=$PWD modules
```

## 坐标/方向

由 DTB 的 `display-coords`、`pos-swap`、`posx-reverse`、`posy-reverse` 决定。
DSI 面板 480x800；如果触摸方向与画面不一致，改这些属性后重新编译 DTB。

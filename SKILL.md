---
name: nvidia-headless-remote
description: Use when a Linux machine with an NVIDIA GPU shows a black screen or misplaced login window in remote desktop (向日葵/ToDesk/AnyDesk) after the monitor is unplugged, or when the user wants to run the machine headless while keeping remote desktop working. Sets up a software fake display via xorg.conf (ConnectedMonitor + CustomEDID + lenient ModeValidation), verifies it safely with a throwaway X server, and explains headless GPU power behavior.
---

# NVIDIA 无头远程桌面（软件假显示器）

帮用户在拔掉显示器的 NVIDIA Linux 主机上恢复/部署远程桌面。完整背景与故障对照表见同目录 README.md。

## 适用判断

- 拔显示器后远程黑屏 / 登录框错位 → 本技能
- 前提：X11 会话（`echo $XDG_SESSION_TYPE`）、NVIDIA 专有驱动。Wayland 需先在 `/etc/gdm3/custom.conf` 设 `WaylandEnable=false`
- 笔记本 Optimus 双显卡不适用

## 核心认知（先读，避免走弯路）

1. 黑屏根因：GNOME/X11 在"零显示输出"时 X 能活但桌面不渲染，远程抓到黑屏。改 X 无头参数救不了渲染，必须**提供假显示器**。
2. 假显示器 = `ConnectedMonitor`（强制有屏）+ `CustomEDID`（喂 EDID）+ **宽松 `ModeValidation`（必需！默认校验会拒绝所有模式，X 直接 no screens found）** + `MetaModes`。
3. EDID 用现成模板（本目录 `2560x1440.bin`，源自内核 edid-generator），**不要手搓**（DTD 字节序极易错，edid-decode 验证）。抓真机 EDID：显示器通电插好时 `sudo cat /sys/class/drm/card*-HDMI-*/edid > my.bin`。
4. 功耗：GPU 空转高功耗（3090 Ti 实测 98W）的根源是**屏幕唤醒状态**而非接线；GNOME 息屏（idle-delay，默认 300s）后降到 P8/~9W，与插线无关。省电靠调短息屏：`gsettings set org.gnome.desktop.session idle-delay 300`；远程机器保持不自动挂起（`sleep-inactive-ac-type` 应为 `nothing`）。

## 部署步骤

1. 安装文件：
   ```bash
   sudo cp 2560x1440.bin /etc/X11/edid-headless.bin
   sudo cp 10-headless-nvidia.conf /etc/X11/xorg.conf.d/
   sudo cp headless /usr/local/bin/ && sudo chmod +x /usr/local/bin/headless
   ```
2. **安全测试**（不动现有会话）：
   ```bash
   mkdir -p /tmp/empty-confdir
   sudo Xorg :9 -config /path/to/10-headless-nvidia.conf -configdir /tmp/empty-confdir -ac vt9 &
   sleep 7; DISPLAY=:9 xrandr --query | head -4   # 期望 HDMI-0 connected 2560x1440
   sudo pkill -f "Xorg :9"
   ```
   `-configdir` 指向空目录，防止旧配置合并干扰；测试失败看 X 日志中的 `(EE)` 行。
3. 生效：`sudo systemctl restart gdm3`，重连远程桌面验证（机器可能停在登录界面，需登录一次）。
4. 日常切换：`sudo headless off`（接真显示器前）/ `sudo headless on`（恢复无头）。

## 排查速查

| 症状 | 处理 |
|---|---|
| X 崩溃 `no screens found` / `No valid modes` | 缺 `ModeValidation` 宽松参数 |
| 接口一直 disconnected，EDID 0 字节 | 显示器未开机/输入源不对/HDMI 未插到底（HPD 需显示器应答） |
| SSH 能进但远程黑屏 | 假显示器未生效，`DISPLAY=:0 xrandr` 检查是否 connected |
| 息屏后远程画面黑 | 正常，动鼠标唤醒 |
| `edid-decode` 报时序错 | 换官方模板 EDID |

## 本目录文件

- `README.md` —— 面向人类的完整教程（含功耗实测数据与电费估算）
- `2560x1440.bin` —— EDID 模板（128 字节，GPL-3.0，来源 akatrevorjay/edid-generator）
- `10-headless-nvidia.conf` —— X 配置模板
- `headless` —— on/off 切换脚本

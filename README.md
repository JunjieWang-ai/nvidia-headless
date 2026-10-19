# nvidia-headless

**拔掉显示器，远程桌面照常用。** NVIDIA Linux 主机的"软件假显示器"方案 —— 不买假插头、不改 BIOS、不花一分钱。

> **English**: Keep remote desktop (Sunlogin/ToDesk/AnyDesk/RDP…) fully working on a monitor-less NVIDIA Linux box, using a software fake display via xorg.conf. No dummy plug, no BIOS changes, zero cost.

![license](https://img.shields.io/badge/license-MIT%20%2B%20GPL(bin)-green)
![platform](https://img.shields.io/badge/platform-Linux%20%2B%20NVIDIA-blue)
![session](https://img.shields.io/badge/display-X11%20only-orange)
![tested](https://img.shields.io/badge/tested-Ubuntu%2024.04%20·%20RTX%203090%20Ti-success)

---

## 目录

- [解决什么问题](#解决什么问题)
- [快速开始](#快速开始)
- [目录结构](#目录结构)
- [原理与配置解析](#原理与配置解析踩坑实录)
- [安全验证方法](#安全验证方法不动现有会话)
- [排查手册](#排查手册)
- [功耗实测与省电建议](#功耗实测与省电建议)
- [FAQ](#faq)
- [给 AI 助手用（SKILL）](#给-ai-助手用skill)
- [贡献](#贡献)
- [许可](#许可)

## 解决什么问题

机器拔掉显示器后，用向日葵 / ToDesk / AnyDesk 等远程桌面连接会遇到：

- **黑屏**：X 和桌面进程都活着，画面却全黑；
- **登录框错位**：能看到登录界面，但输入框位置不对，登录完又黑屏；
- 或者：机房/家里的机器想省掉一个显示器，又不想牺牲远程体验。

**根因**：X11 桌面需要至少一个"已连接的显示输出"才渲染画面。零输出时 X 服务器能启动，但桌面合成器不绘制任何内容——远程软件抓到的自然是黑屏或错位布局。

**解法**：用一份 EDID（显示器的"身份数据"）+ 几行 X 配置，让显卡永远认为接着一台 2560×1440 显示器。等效于 10 元的 HDMI 假插头，但不花钱。

## 快速开始

### 前置条件

- Linux + NVIDIA 专有驱动 + **X11 会话**（Wayland 不适用；Ubuntu 22.04/24.04 验证通过）
- 桌面机（笔记本 Optimus 双显卡场景不在本指南范围）

```bash
# 检查会话类型：应输出 x11
echo $XDG_SESSION_TYPE
# 若是 wayland：在 /etc/gdm3/custom.conf 设置 WaylandEnable=false 并重启
```

### 一键安装

```bash
git clone https://github.com/<you>/nvidia-headless.git
cd nvidia-headless
sudo bash install.sh
```

安装脚本会做环境检查（驱动、Wayland 警告），然后部署三个文件。之后：

```bash
sudo systemctl restart gdm3   # 生效（远程会断开约 10 秒，重连即可）
```

> 机器若没开自动登录，gdm 重启后会停在登录界面——**这次的登录框布局是正常的**，登录即可。

然后就可以永久拔掉显示器了。日常切换：

```bash
sudo headless off   # 想接真显示器时先执行，再把线插到显卡上
sudo headless on    # 恢复无头模式
```

### 手动安装

不愿跑脚本的话，手动四步：`2560x1440.bin → /etc/X11/edid-headless.bin`、`10-headless-nvidia.conf → /etc/X11/xorg.conf.d/`、`headless → /usr/local/bin/`、重启 gdm。

## 目录结构

```
nvidia-headless/
├── README.md                 # 本文档
├── LICENSE                   # MIT（2560x1440.bin 为 GPL-3.0，见文内说明）
├── install.sh                # 一键安装脚本
├── headless                  # on/off 切换脚本（装到 /usr/local/bin）
├── 10-headless-nvidia.conf   # X 配置模板（装到 /etc/X11/xorg.conf.d）
├── 2560x1440.bin             # EDID 模板，128 字节（内核 edid-generator）
└── SKILL.md                  # AI 编程助手技能格式
```

## 原理与配置解析（踩坑实录）

```conf
Section "Device"
    Identifier "NVIDIA-card"
    Driver     "nvidia"
    # 强制认为 DFP-0（第一个数字口）有显示器
    Option     "ConnectedMonitor" "DFP-0"
    # 用本地 EDID 文件充当该口的显示器数据
    Option     "CustomEDID"       "DFP-0:/etc/X11/edid-headless.bin"
    # ★ 必需！默认模式校验会拒绝假显示器的所有分辨率，
    #   导致 X 直接 "no screens found" 崩溃
    Option     "ModeValidation"   "NoMaxPClkCheck, NoEdidMaxPClkCheck, NoHorizSyncCheck, NoVertRefreshCheck, NoTotalSizeCheck, AllowNonEDIDModes, AllowNon3DVisionModes"
    # 显式指定输出模式
    Option     "MetaModes"        "DFP-0:2560x1440_60"
EndSection
```

三个最容易翻车的地方：

1. **`ModeValidation` 缺一不可**。少了它，X 日志刷 `Unable to add conservative default mode` / `No valid modes` 后直接起不来。这是各类教程最少提到、但最致命的一行。
2. **EDID 不要手写**。EDID 二进制的 DTD 时序描述符打包顺序极易记错（低字节在前、打包 nibble 在最后），手搓版本 `edid-decode` 一验就露馅。用现成模板（本仓库 `2560x1440.bin`），或接真显示器时抓原始数据：
   `sudo cat /sys/class/drm/card*-HDMI-*/edid > my.bin`
3. **先测试、再上线**。用一次性 X 服务器验证配置（见下节），不要在正在使用的会话上赌运气。

想要其他分辨率？从 [edid-generator](https://github.com/akatrevorjay/edid-generator) 取对应 `.bin`（1080p/4K 等都有），并同步替换配置里的 `2560x1440_60` Modeline 与 `Virtual`。

## 安全验证方法（不动现有会话）

起一个独立的测试 X 服务器，不影响正在使用的桌面和远程连接：

```bash
mkdir -p /tmp/empty-confdir
sudo Xorg :9 -config ./10-headless-nvidia.conf -configdir /tmp/empty-confdir -ac vt9 &
sleep 7
DISPLAY=:9 xrandr --query | head -4
# 期望: HDMI-0 connected primary 2560x1440+0+0
sudo pkill -f "Xorg :9"
```

看到 `connected 2560x1440` 即配置有效。`-configdir` 指向空目录，防止 `/etc/X11/xorg.conf.d/` 里的旧配置混进来干扰判断；失败时看 X 日志里的 `(EE)` 行。

## 排查手册

| 症状 | 原因与处理 |
|---|---|
| X 起不来，日志 `no screens found`、`No valid modes` | 缺 `ModeValidation` 宽松参数，见上节 |
| 接口一直 disconnected、EDID 0 字节 | 显示器没开机 / 输入源不在该口 / HDMI 没插到底（HPD 需显示器通电应答） |
| 远程黑屏但 SSH 正常 | 假显示器未生效；`DISPLAY=:0 xrandr` 应显示 connected，否则检查配置 |
| 登录界面能看但输入框错位 | 同为"零输出"根因，假显示器生效后自愈 |
| 远程画面冻结断开后 GPU 功耗骤降 | 正常：远程会话维持"屏幕唤醒"，断开即息屏降频 |
| 息屏后远程画面是黑的 | 正常，远程端动一下鼠标唤醒 |
| `edid-decode` 报时序错误 | 换用本仓库现成 EDID，别手搓 |

## 功耗实测与省电建议

（RTX 3090 Ti + Ryzen 7 5700G + Ubuntu 24.04，turbostat + RAPL 实测）

| 状态 | GPU 功耗 | 说明 |
|---|---|---|
| 屏幕唤醒（远程会话活跃/本地操作） | ~98W（P2，显存满频） | 显示管线在渲染 |
| GNOME 息屏（默认 5 分钟无操作） | **~9W（P8，显存 405MHz）** | 与是否插线无关 |
| 电源模式 power-saver vs performance（空载 CPU） | 6.0W vs 9.7W | 差别很小 |
| 电源模式（满载编译） | 54~58W | 无差别 |

反直觉的结论：

- **空转 98W 的根源是"屏幕处于唤醒状态"，不是"插着显示器"**。息屏（DPMS off）后即使线插着，GPU 立刻降到 P8。
- **省电的正确姿势是把息屏时间调短**，而不是折腾插线：

```bash
gsettings set org.gnome.desktop.session idle-delay 300   # 5 分钟无操作息屏
# 远程机器请保持不自动挂起，否则远程叫不醒：
gsettings get org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type  # 应为 'nothing'
```

- 电费估算：`日电费(元) ≈ 开机小时 × 整机功率(kW) × 电价`。参考：息屏整机 ~51W、活跃 ~152W，24h 常开 + 每天 6h 活跃 ≈ 1.8 度/天 ≈ 30 元/月（0.55 元/度）。

## FAQ

**Q: 和 10 元 HDMI 假插头比有什么区别？**
效果、功耗完全一样（都是"GPU 以为有屏"）。假插头即插即用、零配置，适合不想动 X 配置的人；本方案胜在免费、可版本化、远程即可部署。

**Q: 拔线后向日葵连接成功但黑屏/卡在登录界面？**
先确认假显示器已生效：`DISPLAY=:0 xrandr` 应显示 `HDMI-0 connected`。未生效按排查手册处理。机器没开自动登录的话，gdm 重启后需登录一次。

**Q: 支持 Wayland 吗？**
不支持。本方案依赖 X11 的 xorg.conf 机制。Wayland 下通常不需要假显示器（mutter 有 headless 后端），行为不同。

**Q: 笔记本能用吗？**
Optimus 双显卡机型未验证，风险自负。台式机纯独显是本方案的目标场景。

**Q: 真显示器和假显示器能共存吗？**
能。配置只针对 DFP-0 强制在线；接真显示器前建议 `sudo headless off` 关掉假显示器，避免真屏被模板 EDID 的 2560×1440 限制。

**Q: AMD 显卡行不行？**
思路类似（xorg 配置 + 内核 EDID 固件 `drm.edid_firmware`），但未经本仓库验证，欢迎 PR。

## 给 AI 助手用（SKILL）

把 `SKILL.md` 按其文件头说明放进 AI 编程助手的技能目录（如 ZCode 的 `~/.zcode/skills/`），之后对 Agent 说"这台机器拔线后远程黑屏了"它就会按本方案处理。

## 贡献

Issue / PR 均欢迎，特别期待：

- 其他分辨率 EDID（4K、 ultrawide）的配置模板
- 其他发行版（Arch/Fedora/Debian）的验证反馈
- 英文文档

## 许可

- 本项目的脚本、配置与文档：[MIT](LICENSE)
- `2560x1440.bin`：源自 Linux 内核 Documentation/EDID 模板（经 [akatrevorjay/edid-generator](https://github.com/akatrevorjay/edid-generator) 分发），按 **GPL-3.0** 提供，详见 LICENSE 文末说明。

## 致谢

- [akatrevorjay/edid-generator](https://github.com/akatrevorjay/edid-generator)（EDID 模板与构建方法）
- NVIDIA Linux 驱动文档（ConnectedMonitor / CustomEDID / ModeValidation 章节）
- 实测环境与数据：RTX 3090 Ti + Ryzen 7 5700G + Ubuntu 24.04.4 + 向日葵，2026-10

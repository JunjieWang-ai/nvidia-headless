#!/usr/bin/env bash
# nvidia-headless 一键安装
# 用法: sudo bash install.sh
set -euo pipefail

CONF_DIR=/etc/X11/xorg.conf.d
EDID_DST=/etc/X11/edid-headless.bin
SCRIPT_DST=/usr/local/bin/headless
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"

[ "$(id -u)" -eq 0 ] || { echo "请用 sudo 运行: sudo bash install.sh"; exit 1; }

echo "==> 环境检查"
command -v nvidia-smi >/dev/null 2>&1 \
  || { echo "  ✗ 未检测到 NVIDIA 驱动 (nvidia-smi)，请先安装驱动"; exit 1; }
echo "  ✓ NVIDIA 驱动: $(nvidia-smi --query-gpu=name,driver_version --format=csv,noheader | head -1)"
if [ "${XDG_SESSION_TYPE:-}" = "wayland" ]; then
  echo "  ⚠ 当前是 Wayland 会话，本方案需要 X11。"
  echo "    请在 /etc/gdm3/custom.conf 设置 WaylandEnable=false 后重启再安装。"
fi

echo "==> 安装文件"
install -d "$CONF_DIR"
install -m 644 "$SRC_DIR/2560x1440.bin"        "$EDID_DST"
install -m 644 "$SRC_DIR/10-headless-nvidia.conf" "$CONF_DIR/10-headless-nvidia.conf"
install -m 755 "$SRC_DIR/headless"             "$SCRIPT_DST"
echo "  ✓ EDID      -> $EDID_DST"
echo "  ✓ X 配置    -> $CONF_DIR/10-headless-nvidia.conf"
echo "  ✓ 切换脚本  -> $SCRIPT_DST"

cat <<'EOF'

安装完成。接下来（可选）:
  1) 安全测试(推荐，不影响现有会话): 见 README「安全验证方法」
  2) 立即生效:  sudo systemctl restart gdm3   # 远程连接会断开约 10 秒
  3) 日常切换:  sudo headless off（接真显示器前）/ sudo headless on（恢复无头）
提示: 机器若未开自动登录，gdm 重启后需在远程桌面登录一次。
EOF

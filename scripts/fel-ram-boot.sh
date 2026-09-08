#!/usr/bin/env bash
# =============================================================================
# fel-ram-boot.sh — USB FEL 模式一键 RAM 启动 Linux (宿主机执行)
#
# 原理:
#   F1C200s 上电无有效启动介质(BROM 检测 SD/SPI 失败)即进入 FEL,
#   sunxi-fel 经 USB 把 u-boot-sunxi-with-spl.bin 送入: SPL 初始化 DDR 后
#   继续保持 FEL 会话, 随后把 zImage/dtb/rootfs/uEnv 写入 DDR;
#   本工具退出时才真正执行 u-boot —— u-boot 自动 env import 本工具注入的
#   uEnv (见 board/f1c200s/fel-uEnv.txt) 并 bootz 启动内核。
#
# 前置条件:
#   - 先 make build fel-images 生成产物
#   - 板上无 SD/SPI 可启动介质(或按板卡方式强制 FEL, 详见 README)
#   - 本机有 sunxi-fel: macOS `brew install sunxi-tools`;
#     Linux 可 `apt install sunxi-tools` 或使用本 SDK 容器 (--privileged)
#
# 用法:
#   ./scripts/fel-ram-boot.sh
#   FEL_TOOL=/path/to/sunxi-fel ./scripts/fel-ram-boot.sh
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGES_DIR="$ROOT/output/images"
ENV_FILE="$ROOT/board/f1c200s/fel-uEnv.txt"
FEL_TOOL="${FEL_TOOL:-$(command -v sunxi-fel || true)}"

# --- 加载地址 (与 fel-uEnv.txt 中 bootcmd 一致) ---
ADDR_ZIMAGE=0x80008000
ADDR_DTB=0x80C00000
ADDR_ROOTFS=0x80D00000
ADDR_ENV=0x80C50000

# --- 工具 & 产物检查 ---
if [ -z "$FEL_TOOL" ]; then
  echo "错误: 找不到 sunxi-fel" >&2
  echo "   macOS : brew install sunxi-tools" >&2
  echo "   Linux : sudo apt install sunxi-tools" >&2
  echo "   或设置 FEL_TOOL=/路径/sunxi-fel" >&2
  exit 1
fi

declare -A need=(
  [u-boot-sunxi-with-spl.bin]="u-boot (含 SPL)"
  [zImage]="内核"
  [suniv-f1c100s-licheepi-nano.dtb]="设备树"
  [rootfs.cpio.gz.uImage]="rootfs ramdisk (先 make fel-images)"
)
for f in "${!need[@]}"; do
  [ -f "$IMAGES_DIR/$f" ] || { echo "错误: 缺少 $IMAGES_DIR/$f (${need[$f]})" >&2; exit 1; }
done

# --- FEL 设备检查 (vid:pid 1f3a:efe8) ---
echo "==> 检查 FEL 设备..."
if ! "$FEL_TOOL" -l 2>/dev/null | grep -q "1f3a:efe8"; then
  echo "错误: 未检测到 FEL 设备 (1f3a:efe8)" >&2
  echo "  提示: 拔掉 SD/TF 卡与 SPI flash(或短路其 CS 到 GND), 重新上电," >&2
  echo "        再执行 lsusb 确认出现 1f3a:efe8" >&2
  exit 1
fi

# --- 传输 (u-boot 在本工具退出后才开始执行, 无时序竞争) ---
echo "==> 上传 u-boot + zImage + dtb + rootfs + uEnv ..."
"$FEL_TOOL" -p uboot "$IMAGES_DIR/u-boot-sunxi-with-spl.bin" \
    write "$ADDR_DTB"    "$IMAGES_DIR/suniv-f1c100s-licheepi-nano.dtb" \
    write "$ADDR_ZIMAGE" "$IMAGES_DIR/zImage" \
    write "$ADDR_ROOTFS" "$IMAGES_DIR/rootfs.cpio.gz.uImage" \
    write "$ADDR_ENV"    "$ENV_FILE"

echo "==> 传输完成, u-boot 正在启动内核..."
echo "    串口 (UART0, 115200) 应可见 Linux 启动日志; 登录: root (无密码)"

#!/usr/bin/env bash
# =============================================================================
# fel-tools.sh — 在宿主机准备 sunxi-fel (FEL USB 工具)
#
# Homebrew 没有 sunxi-tools formula, 这里提供官方源码编译路径。
# Linux 发行版一般有现成包: sudo apt install sunxi-tools (Debian/Ubuntu)
#
# 用法:
#   ./scripts/fel-tools.sh            # 构建到 .host-tools/sunxi-tools/
#   构建完成后:
#     sudo cp .host-tools/sunxi-tools/sunxi-fel /usr/local/bin/   # 或
#     FEL_TOOL=$PWD/.host-tools/sunxi-tools/sunxi-fel ./scripts/fel-ram-boot.sh
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/.host-tools/sunxi-tools"
REPO_URL="https://github.com/linux-sunxi/sunxi-tools.git"

if command -v sunxi-fel >/dev/null 2>&1; then
  echo "==> sunxi-fel 已可用: $(command -v sunxi-fel)"
  exit 0
fi

case "$(uname)" in
  Darwin)
    # 依赖: Xcode 命令行工具 + Homebrew 的 libusb 与 dtc (libfdt) 头/库
    command -v brew >/dev/null 2>&1 || { echo "错误: 需要 Homebrew (https://brew.sh)" >&2; exit 1; }
    xcode-select -p >/dev/null 2>&1 || { echo "错误: 需要 Xcode 命令行工具 (xcode-select --install)" >&2; exit 1; }
    echo "==> 安装依赖 (libusb dtc pkg-config)..."
    for p in libusb dtc pkg-config; do
      brew list "$p" >/dev/null 2>&1 || brew install "$p"
    done
    ;;
  Linux)
    echo "==> Linux 建议直接用发行版包: sudo apt install sunxi-tools" >&2
    echo "    (继续用本脚本编译需 libusb-1.0-0-dev libfdt-dev pkg-config 等)" >&2
    if ! pkg-config --exists libusb-1.0 libfdt 2>/dev/null; then
      echo "错误: 缺少编译依赖 (libusb-1.0 / libfdt 开发包)" >&2
      echo "   Debian/Ubuntu: sudo apt install libusb-1.0-0-dev libfdt-dev pkg-config" >&2
      exit 1
    fi
    ;;
  *)
    echo "不支持的系统: $(uname)" >&2
    exit 1
    ;;
esac

if [ -x "$DEST/sunxi-fel" ]; then
  echo "==> 已构建: $DEST/sunxi-fel"
else
  echo "==> 编译 sunxi-tools (仅 sunxi-fel)..."
  mkdir -p "$(dirname "$DEST")"
  rm -rf "$DEST"
  git clone --depth 1 "$REPO_URL" "$DEST"
  make -C "$DEST" sunxi-fel
fi

echo ""
echo "==> 完成: $DEST/sunxi-fel"
echo "    安装到 PATH (任选):"
echo "      sudo cp $DEST/sunxi-fel /usr/local/bin/"
echo "    或仅本次使用:"
echo "      FEL_TOOL=$DEST/sunxi-fel $ROOT/scripts/fel-ram-boot.sh"

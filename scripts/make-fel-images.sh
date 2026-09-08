#!/usr/bin/env bash
# =============================================================================
# make-fel-images.sh — 制作 FEL RAM 启动所需镜像 (容器内, Makefile 调用)
#   把 buildroot 的 rootfs.cpio.gz 打包成 u-boot bootz 可用的 legacy ramdisk
#   (uImage 头 + 未压缩载荷; 内核自解压其中的 gzip cpio)
#
# 输出:
#   output/images/rootfs.cpio.gz.uImage
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGES_DIR="${1:-$ROOT/output/images}"

SRC="$IMAGES_DIR/rootfs.cpio.gz"
OUT="$IMAGES_DIR/rootfs.cpio.gz.uImage"

[ -f "$SRC" ] || { echo "错误: 缺少 $SRC (先 make build)" >&2; exit 1; }

echo "==> mkimage ramdisk: $SRC -> $OUT"
mkimage -A arm -O linux -T ramdisk -C none -n "f1c200s-rootfs" \
        -d "$SRC" "$OUT" >/dev/null

echo "==> 完成: $OUT ($(stat -c%s "$OUT" 2>/dev/null || stat -f%z "$OUT") B)"
echo "    配合 ./scripts/fel-ram-boot.sh 经 USB FEL 模式启动"

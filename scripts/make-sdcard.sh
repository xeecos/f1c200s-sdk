#!/usr/bin/env bash
# =============================================================================
# make-sdcard.sh — 由 buildroot 产物合成可 dd 的 SD 卡镜像
#
# 用法(容器内, Makefile 调用):
#   scripts/make-sdcard.sh [输出目录]     # 默认 output/images
#
# 依赖: dosfstools(mkfs.vfat) mtools(mcopy) util-linux(sfdisk) — docker 镜像内已装
#
# 布局(与 licheepi nano 社区标准一致):
#   offset 0       : 分区表(MBR)
#   offset 8KB     : u-boot-sunxi-with-spl.bin (BROM 从 SD 扇区16加载)
#   分区1  @1MiB   : FAT 32MiB, 启动分区: extlinux/extlinux.conf + zImage + dtb
#   分区2  @33MiB  : ext4 rootfs
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGES_DIR="${1:-$ROOT/output/images}"
EXT_CONF="$ROOT/board/f1c200s/extlinux/extlinux.conf"
IMG="$IMAGES_DIR/sdcard.img"

# ---- 产物检查 --------------------------------------------------------------
declare -A need=(
  [u-boot-sunxi-with-spl.bin]="u-boot 引导(带 SPL)"
  [zImage]="Linux 内核"
  [suniv-f1c100s-licheepi-nano.dtb]="设备树"
  [rootfs.ext4]="rootfs (ext4)"
)
for f in "${!need[@]}"; do
  if [ ! -f "$IMAGES_DIR/$f" ]; then
    echo "错误: 缺少 $IMAGES_DIR/$f (${need[$f]})，请先执行 make build" >&2
    exit 1
  fi
done

P1_SIZE=32                       # 分区1大小 MiB
P1_START=1                       # 分区1起始 MiB (1MiB 对齐)
P2_START=$((P1_START + P1_SIZE)) # 分区2起始 MiB

if [ "$(uname)" = "Darwin" ]; then
  ROOTFS_BYTES=$(stat -f%z "$IMAGES_DIR/rootfs.ext2")
else
  ROOTFS_BYTES=$(stat -c%s "$IMAGES_DIR/rootfs.ext2")
fi
P2_SECTORS=$(( (ROOTFS_BYTES / 512) + 2048 + 2048 ))   # rootfs + 1MiB 余量 + 对齐
TOTAL_SECTORS=$((P2_START * 2048 + P2_SECTORS))
TOTAL_M=$((TOTAL_SECTORS / 2048 + 1))

echo "==> 合成 $IMG (约 ${TOTAL_M}MiB, rootfs ${ROOTFS_BYTES}B)"
rm -f "$IMG"
truncate -s $((TOTAL_SECTORS * 512)) "$IMG"

# ---- MBR 分区表 ------------------------------------------------------------
sfdisk -q "$IMG" <<EOF
label: dos
unit: sectors
start=$((P1_START * 2048)), size=$((P1_SIZE * 2048)), type=e, bootable
start=$((P2_START * 2048)), size=$P2_SECTORS, type=83
EOF

# ---- 写入 u-boot (8KB 偏移, 扇区16) ---------------------------------------
echo "==> 写入 u-boot-sunxi-with-spl.bin @ 8KB"
dd if="$IMAGES_DIR/u-boot-sunxi-with-spl.bin" of="$IMG" bs=1024 seek=8 conv=notrunc status=none

# ---- 制作分区1 FAT32 内容 --------------------------------------------------
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
STAGE="$TMP/bootfs"
mkdir -p "$STAGE/extlinux"
cp "$EXT_CONF" "$STAGE/extlinux/extlinux.conf"
cp "$IMAGES_DIR/zImage" "$STAGE/zImage"
cp "$IMAGES_DIR/suniv-f1c100s-licheepi-nano.dtb" "$STAGE/suniv-f1c100s-licheepi-nano.dtb"

echo "==> 制作 FAT 启动分区 (mformat/mcopy, 兼容 mtools 读盘)"
truncate -s $((P1_SIZE * 1024 * 1024)) "$TMP/boot.vfat"
mformat -i "$TMP/boot.vfat" -c 1 -v BOOT ::
mcopy -s -i "$TMP/boot.vfat" "$STAGE"/* ::/
dd if="$TMP/boot.vfat" of="$IMG" bs=1M seek="$P1_START" conv=notrunc status=none

# ---- 写入分区2 rootfs ------------------------------------------------------
echo "==> 写入 rootfs.ext4 @ ${P2_START}MiB"
dd if="$IMAGES_DIR/rootfs.ext4" of="$IMG" bs=1M seek="$P2_START" conv=notrunc status=none

echo "==> 完成: $IMG"
echo "    FAT16/32 ${P1_SIZE}MiB (boot) @${P1_START}MiB  分区2: ext4 (rootfs) @${P2_START}MiB"
echo "    部署: sudo ./scripts/deploy-sd.sh /dev/<sdX|diskX>"

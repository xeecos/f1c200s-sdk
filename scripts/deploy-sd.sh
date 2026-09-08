#!/usr/bin/env bash
# =============================================================================
# deploy-sd.sh — 把 sdcard.img 写入 SD/TF 卡 (宿主机执行, 需要 root)
#
# 用法:
#   ./scripts/deploy-sd.sh /dev/disk4              # macOS
#   sudo ./scripts/deploy-sd.sh /dev/sdb           # Linux
#   IMG=xxx.img ./scripts/deploy-sd.sh /dev/sdb    # 指定镜像
#
# 安全提示: 脚本会核对设备为可移动磁盘并二次确认；仍请务必确认设备号!
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMG="${IMG:-$ROOT/output/images/sdcard.img}"
DEV="${1:-}"

if [ -z "$DEV" ]; then
  echo "用法: $0 /dev/<diskX|sdX>" >&2
  exit 1
fi
[ -f "$IMG" ] || { echo "错误: 找不到镜像 $IMG (先 make sdcard)" >&2; exit 1; }

# --- 设备存在性 & 类型检查 ---
case "$(uname)" in
  Darwin)
    [ -b "$DEV" ] || [ -c "$DEV" ] || { echo "错误: $DEV 不是块设备" >&2; exit 1; }
    # 阻止写到内置磁盘 (macOS 内置盘通常为 disk0/disk1)
    case "$DEV" in
      /dev/disk0|/dev/disk1|/dev/rdisk0|/dev/rdisk1)
        echo "错误: $DEV 是内置系统盘，拒绝写入!" >&2; exit 1 ;;
    esac
    INFO=$(diskutil info "$DEV" 2>/dev/null | awk -F: '/Removable Media|Device Location|Disk Size/ {gsub(/^ +| +$/, "", $2); print $1"="$2}')
    echo "==> 设备信息:"; echo "$INFO"
    if echo "$INFO" | grep -q "Removable Media=No"; then
      echo "错误: $DEV 不可移动，拒绝写入!" >&2; exit 1
    fi
    ;;
  Linux)
    [ -b "$DEV" ] || { echo "错误: $DEV 不是块设备" >&2; exit 1; }
    if [ "$(cat "/sys/class/block/$(basename "$DEV")/removable" 2>/dev/null)" != "1" ]; then
      echo "警告: $DEV 不标记为可移动设备，继续前请确认" >&2
    fi
    ;;
  *)
    echo "不支持的系统: $(uname)" >&2; exit 1 ;;
esac

IMG_M=$(( $(stat -f%z "$IMG" 2>/dev/null || stat -c%s "$IMG") / 1024 / 1024 ))
echo "==> 镜像: $IMG (${IMG_M}MiB)  -> 设备: $DEV"
read -r -p "确认写入? 设备上所有数据将丢失! 输入设备名 (如 $(basename "$DEV")) 以继续: " ans
[ "$ans" = "$(basename "$DEV")" ] || { echo "已取消"; exit 1; }

# --- 卸载已挂载分区 ---
case "$(uname)" in
  Darwin)
    diskutil unmountDisk "$DEV" >/dev/null 2>&1 || true
    ;;
  Linux)
    for p in "$DEV"?*; do
      [ -e "$p" ] && umount "$p" 2>/dev/null || true
    done
    ;;
esac

echo "==> 写入中 (可能需要几分钟)..."
dd if="$IMG" of="$DEV" bs=1m conv=fsync status=progress 2>/dev/null || \
dd if="$IMG" of="$DEV" bs=1m conv=fsync
echo "==> 写入完成，请弹出设备"

case "$(uname)" in
  Darwin) diskutil eject "$DEV" >/dev/null 2>&1 || true ;;
  Linux) sync ;;
esac

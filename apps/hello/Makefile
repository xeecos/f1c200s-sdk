# =============================================================================
# apps/<name>/Makefile — f1c200s SDK 应用模板
#
# 由仓库根目录 `make app` (或 make app APP=<name>) 在 SDK 容器内调用,
# 此时 CC 已指向 buildroot 交叉工具链; 也可脱离容器单独使用:
#   make CC=arm-buildroot-linux-gnueabi-gcc
#
# 目标:
#   all     编译 -> ./out/<BIN>   (out/ 已 gitignore)
#   install 安装到 rootfs overlay (随后 make build 即随镜像发布)
#   clean
#
# 新程序: cp -r ../hello ../<name> 后按需修改即可
# =============================================================================

# 交叉编译器(顶层 make app 注入), 缺省用本机 gcc 便于本地试跑
CC      ?= gcc
CFLAGS  ?= -O2 -Wall
LDFLAGS ?=

# 产物名 = 目录名; 编译中间产物统一放 out/ 避免污染源码目录
BIN     := $(notdir $(CURDIR))
SRCS    := $(wildcard *.c)
OUTDIR  := out

# 安装位置: rootfs 中的路径 + overlay 根(DESTDIR 由 make app 提供)
PREFIX  ?= /usr/bin
DESTDIR ?= $(abspath ../..)/board/f1c200s/rootfs-overlay

all: $(OUTDIR)/$(BIN)

$(OUTDIR)/$(BIN): $(SRCS)
	mkdir -p $(OUTDIR)
	$(CC) $(CFLAGS) -o $@ $(SRCS) $(LDFLAGS)

install: $(OUTDIR)/$(BIN)
	install -D -m 0755 $(OUTDIR)/$(BIN) $(DESTDIR)$(PREFIX)/$(BIN)
	@echo "==> 已安装 $(DESTDIR)$(PREFIX)/$(BIN) (make build 后随镜像发布)"

clean:
	rm -rf $(OUTDIR)

.PHONY: all install clean

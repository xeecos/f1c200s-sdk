# =============================================================================
# f1c200s-sdk — Allwinner F1C100s/F1C200s (suniv) Linux 开发 SDK
#
# 顶层入口 (macOS/Linux 宿主机执行; 实际构建都在 Docker 容器内完成)
#
# 常用命令:
#   make image                 构建编译环境镜像 (首次 ~几分钟)
#   make defconfig             生成 buildroot 配置 (Docker 卷内)
#   make build                 全量编译 u-boot + 内核 + rootfs (首次较久)
#   make sdcard                合成 SD 卡镜像 output/images/sdcard.img
#   make fel-images            生成 FEL RAM 启动的 rootfs ramdisk
#   make deploy-sd DEV=/dev/diskX   写入 SD 卡 (宿主机, 需 sudo)
#   make fel-ram-boot          经 USB FEL 模式 RAM 启动 Linux (需 sunxi-fel)
#   make shell                 进入编译容器交互终端
#
# 网络代理(下载慢/失败时): make build PROXY=http://host.docker.internal:7890
#   (colima 用 http://192.168.5.2:7890; Linux 无桌面版时加 NET=host 并用
#    http://127.0.0.1:7890)
# =============================================================================

IMG      ?= f1c200s-env
PROXY    ?=
NET      ?=

# buildroot 输出目录使用 Docker 命名卷(VM 原生文件系统):
# macOS colima 的共享挂载(virtiofs/sshfs)不支持 chown/符号链接时间戳,
# 高并行编译下还会出现文件一致性错误。产物在构建完成后同步回宿主机
# output/images/, 其余(构建缓存/源码)留在卷内可增量复用。
VOL      := f1c200s-out
OUT_HOST := $(CURDIR)/output
DL       := $(CURDIR)/dl
BR_SRC   := $(CURDIR)/.buildroot-src
BR_VER   := 2023.02.9

# 容器内: 仓库 = /work (绑定), 构建输出 = /build-out (命名卷)
DOCKER_ENV := -v $(CURDIR):/work -w /work \
	-v $(VOL):/build-out \
	-e BR2_DL_DIR=/work/dl -e BR2_CCACHE_DIR=/build-out/ccache
ifneq ($(PROXY),)
DOCKER_ENV += -e http_proxy=$(PROXY) -e https_proxy=$(PROXY)
endif
ifneq ($(NET),)
DOCKER_ENV += --network $(NET)
endif

BR_MAKE := make -C /work/.buildroot-src O=/build-out BR2_EXTERNAL=/work
# cp -r: 不用 -a/-p, 避免在 colima 共享挂载上触发 chown/符号链接时间戳
SYNC_IMAGES := mkdir -p /work/output/images && rm -f /work/output/images/* 2>/dev/null; cp -r /build-out/images/. /work/output/images/ && ls -la /work/output/images/

.PHONY: image shell defconfig menuconfig linux-menuconfig uboot-menuconfig \
        build app sdcard fel-images fel-tools deploy-sd fel-ram-boot clean distclean help

help:
	@grep -E '^[a-zA-Z_-]+:.*#' Makefile | sed 's/:.*#/ —/' | column -t -s '—'

# ---------- 1. 编译环境镜像 ----------
image: ## 构建 Docker 编译环境镜像
	docker build \
	  $(if $(PROXY),--build-arg http_proxy=$(PROXY) --build-arg https_proxy=$(PROXY),) \
	  -t $(IMG) docker/

shell: ## 进入编译容器 (交互终端)
	docker run --rm -it $(DOCKER_ENV) $(IMG) bash -l

# ---------- 2. buildroot 配置 ----------
$(BR_SRC)/.cloned:
	@echo "==> 拉取 buildroot $(BR_VER) 源码 ..."
	git clone --depth 1 --branch $(BR_VER) \
	  https://github.com/buildroot/buildroot.git $(BR_SRC)
	@touch $(BR_SRC)/.cloned

defconfig: $(BR_SRC)/.cloned ## 生成 buildroot 配置 (f1c200s_defconfig)
	docker run --rm $(DOCKER_ENV) $(IMG) bash -lc \
	  '$(BR_MAKE) f1c200s_defconfig'

menuconfig: ## 编辑 buildroot 配置 (需先 make defconfig)
	docker run --rm -it $(DOCKER_ENV) $(IMG) bash -lc '$(BR_MAKE) menuconfig'

linux-menuconfig: ## 编辑内核配置
	docker run --rm -it $(DOCKER_ENV) $(IMG) bash -lc '$(BR_MAKE) linux-menuconfig'

uboot-menuconfig: ## 编辑 u-boot 配置
	docker run --rm -it $(DOCKER_ENV) $(IMG) bash -lc '$(BR_MAKE) uboot-menuconfig'

# ---------- 3. 构建 ----------
# 交叉工具链在 Docker 卷 /build-out 内 (buildroot 构建), 通过 SDK 容器使用
CROSS_GCC := /build-out/host/bin/arm-buildroot-linux-gnueabi-gcc

# 应用编译并装入 rootfs overlay: make app [APP=hello]
# (随后 make build 重新打包 rootfs, 程序随镜像发布)
app: ## 交叉编译 apps/ 并安装到 rootfs overlay (make app APP=<name> 只编一个)
	docker run --rm $(DOCKER_ENV) $(IMG) bash -lc 'set -e; \
	  mkdir -p /work/board/f1c200s/rootfs-overlay; \
	  if [ -n "$(APP)" ]; then \
	    make -C /work/apps/$(APP) CC=$(CROSS_GCC) DESTDIR=/work/board/f1c200s/rootfs-overlay install; \
	  else \
	    for m in /work/apps/*/Makefile; do \
	      d=$$(dirname $$m); \
	      echo "==> building $$d"; \
	      make -C $$d CC=$(CROSS_GCC) DESTDIR=/work/board/f1c200s/rootfs-overlay install || exit 1; \
	    done; \
	  fi'

build: defconfig ## 全量编译 (u-boot + 内核 + rootfs) — 首次 30~60 分钟
	docker run --rm $(DOCKER_ENV) $(IMG) bash -lc \
	  '$(BR_MAKE) -j$$(nproc) && $(SYNC_IMAGES)'

sdcard: build ## 合成 SD 卡镜像 output/images/sdcard.img
	docker run --rm $(DOCKER_ENV) $(IMG) bash -lc \
	  'scripts/make-sdcard.sh /work/output/images'

fel-images: build ## 生成 FEL RAM 启动 rootfs (rootfs.cpio.gz.uImage)
	docker run --rm $(DOCKER_ENV) $(IMG) bash -lc \
	  'scripts/make-fel-images.sh /work/output/images'

# ---------- 4. 部署 (宿主机直接执行) ----------
fel-tools: ## 宿主机编译 sunxi-fel (macOS 无 brew formula; Linux 也可 apt)
	./scripts/fel-tools.sh

deploy-sd: sdcard ## 写 SD 卡: make deploy-sd DEV=/dev/diskX
	@[ -n "$(DEV)" ] || { echo "用法: make deploy-sd DEV=/dev/<diskX|sdX>"; exit 1; }
	./scripts/deploy-sd.sh $(DEV)

fel-ram-boot: fel-images ## USB FEL 一键 RAM 启动 (板上拔 SD/flash; 需 sunxi-fel, 缺则先 make fel-tools)
	./scripts/fel-ram-boot.sh

# ---------- 5. 清理 ----------
clean: ## 删除编译产物与镜像 (保留 dl/ 与 Docker 卷, 二次构建更快)
	rm -rf $(OUT_HOST)
	docker run --rm -v $(VOL):/build-out -w /build-out $(IMG) \
	  bash -lc 'rm -rf /build-out/* 2>/dev/null; true'

distclean: ## 全部清理 (产物+下载缓存+源码+命名卷)
	rm -rf $(OUT_HOST) $(DL) $(BR_SRC)
	-docker volume rm $(VOL)

# f1c200s-sdk 全量编译环境
#
# 构建:  docker build -t f1c200s-env docker/
# 用法:   由仓库根目录 Makefile 驱动（make image / make build ...）
#
# 包含:
#   - Debian bookworm 基础环境
#   - buildroot 所需的宿主机构建工具
#   - mkimage (u-boot-tools, 用于打包 FEL RAM 启动的 rootfs/脚本镜像)
#   - dosfstools / mtools / e2fsprogs / util-linux(sfdisk) — SD 卡镜像制作
#   - ccache — 加速重复编译
#   - sunxi-fel — FEL USB 工具（linux 宿主机可直接容器内部署）
#
# 构建期如需走代理（下载慢时）:
#   docker build --build-arg http_proxy=http://127.0.0.1:7890 \
#                --build-arg https_proxy=http://127.0.0.1:7890 \
#                -t f1c200s-env docker/

FROM debian:bookworm-slim

ARG DEBIAN_FRONTEND=noninteractive
ARG http_proxy=
ARG https_proxy=

RUN apt-get update && apt-get install -y --no-install-recommends \
        bash bc binutils build-essential bison cpio diffutils file flex \
        gcc g++ git locales make patch perl python3 rsync sed texinfo unzip \
        wget curl ca-certificates python-is-python3 python3-dev python3-distutils swig \
        libncurses-dev libssl-dev device-tree-compiler pkg-config \
        dosfstools mtools e2fsprogs fdisk u-boot-tools \
        libusb-1.0-0-dev zlib1g-dev libfdt-dev ccache \
    && rm -rf /var/lib/apt/lists/*

# 统一的 UTF-8 locale（buildroot 部分 host 工具依赖）
RUN sed -i 's/^# *\(en_US.UTF-8\)/\1/' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 LANGUAGE=en_US.UTF-8 LC_ALL=en_US.UTF-8

# sunxi-fel: 全志 FEL 模式 USB 工具（编译安装）
RUN git clone --depth 1 https://github.com/linux-sunxi/sunxi-tools.git /opt/sunxi-tools \
    && make -C /opt/sunxi-tools sunxi-fel \
    && install -m 0755 /opt/sunxi-tools/sunxi-fel /usr/local/bin/ \
    && rm -rf /opt/sunxi-tools

# tar 包装器: 见 tar-wrapper.sh (colima 共享挂载拒绝 chown 时保证可解包)
COPY tar-wrapper.sh /usr/local/bin/tar
RUN chmod 0755 /usr/local/bin/tar

WORKDIR /work

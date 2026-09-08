# f1c200s-sdk

全志 Allwinner **F1C100s / F1C200s**（suniv，ARM926EJ-S）Linux 开发 SDK。

基于社区经典型 LicheePi-Nano 源码组合，提供：

- **Docker 全量编译环境**（buildroot + 交叉工具链 + SD 镜像工具 + sunxi-fel）
- **u-boot / Linux 内核 / rootfs 一键构建**（commit 固定、可复现）
- **SD 卡部署**：自动合成可 dd 的 `sdcard.img`（u-boot @8KB + FAT32 启动分区 + ext4 rootfs）
- **FEL USB 部署**：无 SD/SPI 介质时经 USB FEL 模式把 Linux 直接载入 DDR 启动

> 目标板卡：LicheePi Nano 及各类 f1c100s/f1c200s 板卡（UART0 串口 115200 控制台）。
> 硬件前提：一张至少 4GB 的 SD/TF 卡（SD 启动）或 USB 线 + 板卡 FEL 模式（RAM 启动）。

## 快速开始

前置：装有 [Docker](https://www.docker.com/) 的 macOS / Linux；网络能访问 GitHub
（下载慢时见下文“代理”）。

```bash
make image        # 1. 构建编译环境镜像（首次约几分钟）
make build        # 2. 全量编译 u-boot + 内核 + rootfs（首次 20~50 分钟）
make sdcard       # 3. 合成 SD 卡镜像: output/images/sdcard.img
make deploy-sd DEV=/dev/diskX   # 4. 写入 SD 卡（macOS 示例，Linux 用 /dev/sdX，需 sudo）
```

SD 卡插回板卡上电，串口（UART0, 115200）即可看到 u-boot 与 Linux 启动日志，登录 `root`（无密码）。

### FEL RAM 启动（快速调试，不动 flash/SD）

```bash
make fel-images                 # 生成 FEL 用 rootfs ramdisk
make fel-tools                  # 宿主机编译 sunxi-fel（仅首次，macOS 需此步）
./scripts/fel-ram-boot.sh       # 经 USB FEL 模式启动
```

> 说明：Homebrew 没有 sunxi-tools formula。`make fel-tools` 会在宿主机
> 用源码编译（依赖 Xcode CLT + `brew install libusb dtc`），产物在
> `.host-tools/sunxi-tools/sunxi-fel`（目录已 gitignore，删除后重跑
> `make fel-tools` 即可重建；也可 `sudo cp` 到 /usr/local/bin）。
> Linux 可直接 `sudo apt install sunxi-tools`；本 SDK 的 Docker 镜像内也
> 自带 sunxi-fel（Linux 宿主机可把 `/dev/bus/usb` 挂进容器使用）。
>
> ✅ 已验证：macOS (Apple Silicon) 上 `make fel-tools` 编译通过，
> sunxi-fel (d7bbd17) 可正常运行、枚举 FEL 设备。

流程：拔掉 SD/SPI 介质（或按板卡方式强制 FEL）→ 板卡 USB 连电脑 → 上电后
`lsusb` 出现 `1f3a:efe8` → 执行脚本 → u-boot 自动把 Linux 从 DDR 启动。
再次上电即回到原状态，flash/SD 均未被改写。

## 目录结构

```
├── Makefile                  # 顶层入口（全部工作流）
├── external.desc             # buildroot BR2_EXTERNAL 声明（仓库根=外部树）
├── configs/
│   └── f1c200s_defconfig     # buildroot 配置：源码 pin + rootfs 形态
├── board/f1c200s/
│   ├── linux.config          # 内核配置（取自已 pin 的 licheepi 内核 defconfig）
│   ├── uboot.fragment        # u-boot kconfig 追加项（SPL MMC / with-spl 产物）
│   ├── fel-uEnv.txt          # FEL RAM 启动注入 u-boot 的环境（内存布局在此定义）
│   └── extlinux/extlinux.conf# SD 卡 distro 启动描述
├── docker/
│   └── Dockerfile            # 编译环境：构建依赖 + mkimage + sunxi-fel + ccache
└── scripts/
    ├── make-sdcard.sh        # 合成 sdcard.img（容器内）
    ├── make-fel-images.sh    # rootfs.cpio.gz -> bootz ramdisk uImage
    ├── fel-tools.sh          # 宿主机编译 sunxi-fel（macOS，Homebrew 无 formula）
    ├── deploy-sd.sh          # 写 SD 卡（宿主机）
    └── fel-ram-boot.sh       # FEL USB RAM 启动（宿主机）
```

编译产物会同步到 `output/images/`：`u-boot-sunxi-with-spl.bin`、`zImage`、
`suniv-f1c100s-licheepi-nano.dtb`、`rootfs.ext4`、`rootfs.cpio.gz`、
`sdcard.img`、`rootfs.cpio.gz.uImage`。

构建中间产物（工具链/源码树/缓存）保存在 Docker 命名卷 `f1c200s-out` 与
`dl/` 中：不在绑定挂载上编译，可避开 macOS colima/Docker Desktop 共享挂载的
文件系统语义限制（chown/符号链接时间戳等），并支持断点续编。
`make clean` 清空卷（保留 `dl/` 下载缓存）；`make distclean` 全清（含卷、
`dl/`、buildroot 源码）。

## 技术要点

| 组件 | 来源 | 说明 |
|---|---|---|
| u-boot | `Lichee-Pi/u-boot` @ commit `013ca457`（分支 nano-v2018.01） | `licheepi_nano_defconfig`，含 suniv DRAM 初始化、SD 与 FEL 支持 |
| 内核 | `Lichee-Pi/linux` @ commit `05696d01`（分支 nano-5.2-flash） | 5.2 内核，SD/SPI-flash 驱动齐备；板卡 dts：`suniv-f1c100s-licheepi-nano` |
| rootfs | buildroot 2023.02.9 内部工具链（glibc, gcc 11） | busybox + mdev，串口 getty ttyS0@115200 |
| SD 镜像 | 本 SDK `scripts/make-sdcard.sh` | MBR：u-boot@8KB + FAT32 32MiB(extlinux) @1MiB + ext4 @33MiB |
| FEL 启动 | sunxi-fel + u-boot SPL 头字段注入 | 无需自制 u-boot 变体，见下方原理 |

### 为什么选这个组合

suniv 芯片的 Linux 生态分两派：**主线**（内核 ≥6.5 / u-boot 2023，只支持
SPI NOR flash 启动）与 **licheepi fork**（u-boot 2018.01 + 内核 5.2，SD/TF 卡
启动，社区教程标准）。本 SDK 选后者以同时满足 SD 卡部署；两个 fork 均以
commit 固定，行为不会漂移。若你只需 SPI NOR 烧写，可参考上游
`sipeed_licheepi_nano_defconfig`（buildroot 主线 board）。

### 对 u-boot fork 的两个必要补丁（board/f1c200s/patches/uboot/）

2018 年的代码在 2026 年的工具链上编译有兼容问题，已随 SDK 以 buildroot
标准补丁机制（BR2_GLOBAL_PATCH_DIR）解决，commit 固定不受上游影响：

1. `0001` — dts 追加 `#include "sunxi-u-boot.dtsi"` 时写成了 `\#include`，
   现代 cpp 不再把转义井号当指令，导致 dtc 语法错误；改为未转义写法让
   cpp 正常展开。
2. `0002` — 组装 `u-boot-sunxi-with-spl.bin` 的 binman 是 python2 程序，
   无法在无 python2 的现代系统运行；改为等价的
   `tools/sunxi-mkwithspl.py`（布局不变：SPL + 0xff 填充到 32KB +
   u-boot.img + 填充到 env 偏移），产物与 binman 版逐字节一致。

如需升级/更换 u-boot 源码（改 `configs/f1c200s_defconfig` 中
`BR2_TARGET_UBOOT_CUSTOM_REPO_VERSION`），请先核对这两个补丁是否仍适用。

### FEL RAM 启动原理（为什么不用另编 u-boot）

1. `sunxi-fel uboot u-boot-sunxi-with-spl.bin`：SPL 入 SRAM → 初始化 DDR →
   回到 FEL 会话等待传输；
2. 同一进程内继续 `write` 把 zImage/dtb/rootfs/uEnv 写入 DDR —— 注意 u-boot
   在本工具**退出时**才被真正执行，因此没有“自动启动抢跑”的时序问题；
3. sunxi-fel 检测到 uEnv 文件（魔数 `#=uEnv`）即把其地址/长度写入 SPL 头字段，
   u-boot 的 `misc_init_r` 自动 `env import`（见 `board/f1c200s/fel-uEnv.txt`，
   bootcmd 里定义了 bootz 的加载地址）；
4. u-boot 启动后按 bootcmd 自动 bootz，Linux 以 initramfs（cpio.gz）方式运行。

## 常用命令

```bash
make help                 # 列出全部 target
make shell                # 进入容器手动操作（buildroot make 均在容器内执行）
make menuconfig           # 改 buildroot 配置（如增减 rootfs 软件包）
make linux-menuconfig     # 改内核配置（如加 LCD/音频驱动）
make uboot-menuconfig     # 改 u-boot 配置
make clean                # 删 Docker 卷内构建产物（dl/ 下载缓存保留）
make distclean            # 全清（卷 + dl + buildroot 源码）
```

自定义内核配置的推荐做法：`make linux-menuconfig` 保存到原
`board/f1c200s/linux.config`（即 BR2_LINUX_KERNEL_CUSTOM_CONFIG_FILE 指向的
文件），可让变更进入版本管理。如需修改 u-boot 环境（如 bootdelay、内存布局），
编辑 `board/f1c200s/uboot.fragment`。

## 代理

宿主机有 HTTP 代理（如 `127.0.0.1:7890`）且直连下载缓慢/失败时，把容器内
代理指到宿主机的可达地址即可（`PROXY` 同时用于镜像构建与构建期下载）：

```bash
# Docker Desktop (macOS/Windows): 代理经 host.docker.internal 可达
make image PROXY=http://host.docker.internal:7890
make build PROXY=http://host.docker.internal:7890

# colima (lima VM): 网关固定为 192.168.5.2
make image PROXY=http://192.168.5.2:7890
make build PROXY=http://192.168.5.2:7890

# Linux（容器以 host 网络运行，直连宿主代理）
make image PROXY=http://127.0.0.1:7890
make build PROXY=http://127.0.0.1:7890 NET=host
```

代理只需在下载阶段开启；产物缓存在 `dl/` 后不再需要网络。
注意：仓库不在 `$HOME` 下时 colima 需显式挂载且可写，参考
`colima start --mount "/绝对路径到本仓库:w"`。

## 故障排查

- **`sunxi-fel -l` 无设备**：确认无 SD/SPI 介质；部分板卡需短接 SPI flash CS 到
  GND 上电强制 FEL（详见 linux-sunxi.org/FEL）。
- **FEL 传输中断**：换短而好的 USB 线；某些 hub 不兼容 FEL。
- **SD 不启动**：确认 u-boot 写在第 16 扇区（脚本已按 8KB 偏移）、分区1为 FAT32
  bootable；首次建议 `make deploy-sd` 整卡写入。
- **内核引导 panic 于解压/内存重叠**：若自行增配内核导致 zImage 变大，可能挤占
  dtb 地址（0x80C00000）。SD 侧改 `extlinux.conf` 中 KERNEL/FDT 路径，FEL 侧
  同步改 `fel-uEnv.txt` 与 `fel-ram-boot.sh` 中的地址。
- **容器内 git/下载超时**：见上文“代理”。
- **rootfs 扩容**：改 `configs/f1c200s_defconfig` 中 `BR2_TARGET_ROOTFS_EXT2_SIZE`，
  `make-sdcard.sh` 会自动按 rootfs 实际大小计算分区2。

## 许可

- 本 SDK 编排代码：MIT（见 LICENSE）
- 构建的上游组件遵循各自许可：u-boot（GPL-2.0+）、Linux（GPL-2.0）、buildroot（GPL-2.0+ 等）

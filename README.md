# LXC Rootfs Build

通过 GitHub Actions 自动构建 LXC 容器的 Linux 发行版 rootfs 包，默认输出 **arm64** 平台、**tar.xz** 格式。

## 支持的发行版

| 发行版   | 默认版本      | 构建方式                                     |
| -------- | ------------- | -------------------------------------------- |
| Debian   | trixie        | distrobuilder (debootstrap)                  |
| Ubuntu   | 24.04 (noble) | distrobuilder (debootstrap)                  |
| ArchLinux| current       | distrobuilder (ArchLinux ARM 源构建 arm64)   |
| Kali     | kali-rolling  | distrobuilder (debootstrap + Kali 仓库)      |
| NixOS    | 26.05         | 官方 Hydra 预构建 rootfs 重新打包 (与 images.linuxcontainers.org 一致) |

## 使用

1. 把本目录推送到 GitHub 仓库
2. 进入 **Actions → Build LXC Rootfs → Run workflow**
3. 选择发行版 / 版本 / 架构 (`arm64` / `amd64` / `both`) / 变体 / 压缩算法
4. 可选开启 **KDE 桌面** (`none`/`min`/`conc`) 和 **Anland 支持**，指定用户名
5. 构建完成后在运行页面的 **Artifacts** 下载产物

仓库也配置了每周日 02:00 自动构建全部发行版 (arm64)。

## KDE 桌面与 Anland

构建完成后可对 rootfs 二次定制 (`scripts/customize-rootfs.sh`)，参考了 [Droidspaces-rootfs-KDE-builder](https://github.com/Goldzxcbug/Droidspaces-rootfs-KDE-builder) 的实现：

- **KDE 安装** (仅 debian / ubuntu / archlinux):
  - `min`: 最小 KDE 桌面 (`kde-plasma-desktop` 基础组件 + 中文字体 + konsole/dolphin/kate)
  - `conc`: 精简完整版 (在 min 基础上加系统监控、文件管理、缩略图等)
  - 自动创建普通用户 (默认 `user`，密码 `1234`，加入 `sudo`)
  - 非 Anland 模式写入 `DISPLAY=:5` 并安装 `plasma-x11.service` 自启动
- **Anland 支持** (仅 debian / ubuntu 的 arm64):
  - 写入 Anland 环境变量 (`WAYLAND_DISPLAY=wayland-0`、`ANLAND=1`、`ANLAND_SOCKET=/run/display.sock` 等)
  - 从 Droidspaces-rootfs-KDE-builder 拉取 patched KWin/Xwayland 预编译包 (debian trixie / ubuntu 26.04) 并 `apt-mark hold` 锁定
  - 安装 `plasma-wayland.service` 自启动 (容器内 `startplasma-wayland` 可手动启动)
  - 宿主侧需准备 anland daemon (`virtual-drm-daemon` + app，见 [anland](https://github.com/superturtlee/anland))，并把 socket 绑定挂载到 `/run/display.sock`
- **Mesa (Adreno) GPU 驱动** (arm64 + KDE 模式): 从 [mesa-for-android-container](https://github.com/lfdevs/mesa-for-android-container) 自动下载对应发行版的 KGSL 驱动包解压进 rootfs。Anland 模式写入 `MESA_LOADER_DRIVER_OVERRIDE=kgsl`、`GALLIUM_DRIVER=kgsl`、`FD_FORCE_KGSL=1`；X11 模式写入 `MESA_LOADER_DRIVER_OVERRIDE=kgsl`、`TU_DEBUG=noconform`。驱动资产缺失的发行版组合会跳过并告警，不影响构建

定制产物命名带后缀: `debian-trixie-arm64-default-kde-anland-rootfs.tar.xz`。

## 产物

- `debian-<release>-<arch>-<variant>-rootfs.tar.xz` — rootfs 包
- `debian-<release>-<arch>-<variant>-meta.tar.xz` — LXC 元数据 (仅 distrobuilder 构建的发行版)

### 导入 LXC

```bash
lxc-create -n c1 -t local -- --metadata meta.tar.xz --fstree rootfs.tar.xz
```

### 导入 LXD/Incus

```bash
lxc image import rootfs.tar.xz meta.tar.xz --alias debian-trixie
```

## 本地构建 (可选)

```bash
# 安装依赖: debootstrap, qemu-user-static (构建 arm64 时), golang, pkg-config, libgpgme-dev, libbtrfs-dev
sudo apt-get install -y debootstrap qemu-user-static golang-go pkg-config libgpgme-dev libbtrfs-dev
git clone --depth 1 --branch v3.3.1 https://github.com/lxc/distrobuilder /tmp/distrobuilder
cd /tmp/distrobuilder
go mod edit -replace=github.com/cyphar/filepath-securejoin=github.com/cyphar/filepath-securejoin@v0.5.2
go build -mod=mod -o distrobuilder.bin ./distrobuilder
sudo cp distrobuilder.bin /usr/local/bin/distrobuilder
# 构建 Debian arm64
bash scripts/build-distro.sh images/debian.yaml trixie arm64 default xz ./output

# 构建 NixOS arm64
bash scripts/build-nixos.sh 26.05 arm64 ./output

# 对已构建的 rootfs 安装 KDE + Anland
bash scripts/customize-rootfs.sh \
  ./output/debian-trixie-arm64-default-rootfs.tar.xz \
  debian trixie arm64 min true user \
  ./output/debian-trixie-arm64-default-kde-anland-rootfs.tar.xz
```

## 目录结构

```
├── .github/workflows/build-rootfs.yml   # 工作流 (动态矩阵)
├── images/                              # distrobuilder 模板 (来自 lxc-ci 上游)
│   ├── debian.yaml
│   ├── ubuntu.yaml
│   ├── archlinux.yaml
│   └── kali.yaml
└── scripts/
    ├── build-distro.sh                  # distrobuilder 构建脚本
    ├── build-nixos.sh                   # NixOS 构建脚本
    └── customize-rootfs.sh              # KDE / Anland 定制脚本
```

## 注意事项

- **arm64 构建**: 自动使用 GitHub 原生 arm64 托管 runner (`ubuntu-24.04-arm`)，无需 QEMU 模拟，速度与 amd64 相当；amd64 构建使用 `ubuntu-latest`。仅当两种架构混跑且需要交叉模拟时才会启用 binfmt
- **distrobuilder 缓存**: 编译产物缓存在 Actions cache 中，首次构建后不再重复编译
- **NixOS** 的特殊性: NixOS 无法用传统方式"组装" rootfs，官方容器镜像本身即由 Hydra CI 构建，因此本项目直接复用官方产物并重打包，保证与 images.linuxcontainers.org 一致
- **KDE/Anland 限制**: KDE 仅支持 debian/ubuntu/archlinux；Anland 仅支持 debian/ubuntu 的 arm64。patched KWin 包仅覆盖 debian trixie / ubuntu 26.04，其他版本会跳过 patched 包仅写入环境配置
- `images/*.yaml` 来自 [lxc/lxc-ci](https://github.com/lxc/lxc-ci/tree/main/images)，如需更新可直接覆盖后重新触发构建

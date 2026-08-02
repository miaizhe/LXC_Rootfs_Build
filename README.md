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
4. 构建完成后在运行页面的 **Artifacts** 下载产物

仓库也配置了每周日 02:00 自动构建全部发行版 (arm64)。

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
    └── build-nixos.sh                   # NixOS 构建脚本
```

## 注意事项

- **arm64 构建**: 在 amd64 的 GitHub Runner 上通过 QEMU 用户态模拟 (binfmt) 交叉构建，速度约为本机的 1/3~1/5，单任务可能需要 10~30 分钟
- **NixOS** 的特殊性: NixOS 无法用传统方式"组装" rootfs，官方容器镜像本身即由 Hydra CI 构建，因此本项目直接复用官方产物并重打包，保证与 images.linuxcontainers.org 一致
- `images/*.yaml` 来自 [lxc/lxc-ci](https://github.com/lxc/lxc-ci/tree/main/images)，如需更新可直接覆盖后重新触发构建

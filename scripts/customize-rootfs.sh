#!/usr/bin/env bash
# 对已构建的 LXC rootfs 进行二次定制: 安装 KDE 桌面 / 配置 Anland (Android Wayland)
#
# 参考实现:
#   - https://github.com/Goldzxcbug/Droidspaces-rootfs-KDE-builder (KDE 包清单、anland 配置、systemd 服务)
#   - https://github.com/superturtlee/anland (Wayland 显示协议)
#
# 用法: customize-rootfs.sh <rootfs.tar.xz> <distro> <release> <arch> <kde> <anland> <username> <输出tar.xz>
#   kde:    none | min | conc
#   anland: true | false
set -euo pipefail

ROOTFS_TAR=$1
DISTRO=$2
RELEASE=$3
ARCH=$4
KDE=$5
ANLAND=$6
USERNAME=$7
OUT_TAR=$8

if [ ! -f "$ROOTFS_TAR" ]; then
  echo "错误: 找不到 rootfs 包 $ROOTFS_TAR" >&2
  exit 1
fi

WORKDIR=$(mktemp -d)
cleanup() {
  for m in proc dev sys; do sudo umount -R "$WORKDIR/rootfs/$m" >/dev/null 2>&1 || true; done
  sudo umount -R "$WORKDIR/rootfs" >/dev/null 2>&1 || true
  sudo rm -rf "$WORKDIR" 2>/dev/null || sudo rm -rf -- "$WORKDIR/rootfs/proc" "$WORKDIR/rootfs/dev" "$WORKDIR/rootfs/sys" "$WORKDIR/rootfs" "$WORKDIR"
}
trap cleanup EXIT
mkdir -p "$WORKDIR/rootfs"

echo "==> 解包 $ROOTFS_TAR"
sudo tar -xf "$ROOTFS_TAR" -C "$WORKDIR/rootfs"

CHROOT() { sudo chroot "$WORKDIR/rootfs" "$@"; }
CHROOT_SH() { sudo chroot "$WORKDIR/rootfs" /bin/sh -c "$1"; }

# ---------- 准备 chroot 环境 ----------
sudo mount -t proc proc "$WORKDIR/rootfs/proc"
sudo mount --bind /dev "$WORKDIR/rootfs/dev"
sudo mount --bind /sys "$WORKDIR/rootfs/sys"
# distrobuilder 构建的 rootfs 中 /etc/resolv.conf 是悬空符号链接, 需先删除再覆盖
sudo rm -f "$WORKDIR/rootfs/etc/resolv.conf"
sudo cp /etc/resolv.conf "$WORKDIR/rootfs/etc/resolv.conf"

# ---------- 安装 KDE ----------
if [ "$KDE" != "none" ]; then
  echo "==> 安装 KDE ($KDE): $DISTRO"
  case "$DISTRO" in
    archlinux)
      CHROOT_SH "pacman -Syu --noconfirm --needed \
        plasma-desktop kwin konsole dolphin kate \
        xorg-server xorg-xinit xorg-xwayland \
        dbus sudo noto-fonts noto-fonts-cjk"
      ;;
    debian|ubuntu|kali)
      BASE="dbus-x11 x11-xserver-utils fonts-noto-cjk fonts-noto-color-emoji \
        kde-plasma-desktop powerdevil kscreen plasma-pa konsole dolphin kate \
        kinfocenter mesa-utils pulseaudio-utils upower plasma-session-x11 \
        kwin-x11 dbus-user-session polkit-kde-agent-1 libpam-systemd sudo"
      EXTRA=""
      [ "$KDE" = "conc" ] && EXTRA="kfind plasma-systemmonitor filelight \
        systemsettings kio-extras xdg-user-dirs dolphin-plugins \
        ffmpegthumbs kdegraphics-thumbnailers kimageformat6-plugins \
        plasma-browser-integration gstreamer1.0-plugins-base \
        sound-theme-freedesktop wayland-utils xserver-xorg"
      CHROOT_SH "apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends $BASE $EXTRA"
      ;;
    *)
      echo "警告: $DISTRO 不支持 KDE 安装, 跳过" >&2
      ;;
  esac
fi

# ---------- 创建普通用户 (UID 1000, 供桌面服务与登录使用) ----------
if [ "$KDE" != "none" ] && [ -n "$USERNAME" ]; then
  echo "==> 创建用户 $USERNAME (密码: 1234)"
  CHROOT_SH "id $USERNAME >/dev/null 2>&1 || useradd -m -s /bin/bash -G sudo,shadow $USERNAME; \
    echo '$USERNAME:1234' | chpasswd" || true
fi

# ---------- Mesa (Adreno GPU) 驱动 ----------
# 来自 https://github.com/lfdevs/mesa-for-android-container (KGSL 后端, 硬件加速)
if [ "$KDE" != "none" ] && [ "$ARCH" = "arm64" ]; then
  MESA_SUFFIX=""
  case "$DISTRO:$RELEASE" in
    debian:trixie)     MESA_SUFFIX="debian_trixie_arm64" ;;
    ubuntu:noble)      MESA_SUFFIX="ubuntu_noble_arm64" ;;
    ubuntu:questing)   MESA_SUFFIX="ubuntu_questing_arm64" ;;
    ubuntu:resolute)   MESA_SUFFIX="ubuntu_resolute_arm64" ;;
    archlinux:*)       MESA_SUFFIX="archlinux_arm64" ;;
  esac
  if [ -n "$MESA_SUFFIX" ]; then
    echo "==> 安装 Mesa (Adreno) 驱动 ($MESA_SUFFIX)"
    URL=$(curl -s https://api.github.com/repos/lfdevs/mesa-for-android-container/releases/latest \
      | grep -oE '"browser_download_url": "[^"]*'"$MESA_SUFFIX"'\.tar(\.gz)?"' \
      | sed 's/.*: "//;s/"$//' | head -1)
    if [ -n "$URL" ]; then
      curl -sfL "$URL" -o "$WORKDIR/mesa.tar" || echo "警告: Mesa 驱动下载失败" >&2
      if [ -s "$WORKDIR/mesa.tar" ]; then
        sudo tar -xf "$WORKDIR/mesa.tar" -C "$WORKDIR/rootfs"
        CHROOT ldconfig || true
        rm -f "$WORKDIR/mesa.tar"
      fi
    else
      echo "警告: 未找到 $MESA_SUFFIX 的 Mesa 驱动资产, 跳过 (不影响构建)" >&2
    fi
  else
    echo "警告: $DISTRO $RELEASE 无对应的 Mesa 驱动资产, 跳过 (不影响构建)" >&2
  fi

  # 环境变量: anland 走 KGSL 三件套, X11 走 kgsl + TU_DEBUG=noconform
  if [ "$ANLAND" = "true" ]; then
    MESA_ENV="MESA_LOADER_DRIVER_OVERRIDE=kgsl
GALLIUM_DRIVER=kgsl
FD_FORCE_KGSL=1"
  else
    MESA_ENV="MESA_LOADER_DRIVER_OVERRIDE=kgsl
TU_DEBUG=noconform"
  fi
  printf '%s\n' "$MESA_ENV" | sudo tee -a "$WORKDIR/rootfs/etc/environment" >/dev/null
fi

# ---------- Anland 配置 ----------
if [ "$ANLAND" = "true" ]; then
  echo "==> 配置 Anland (Wayland 输出到 Android)"
  if [ "$ARCH" != "arm64" ] || { [ "$DISTRO" != "debian" ] && [ "$DISTRO" != "ubuntu" ]; }; then
    echo "警告: Anland 仅支持 debian/ubuntu 的 arm64, 仍会写入环境配置(不安装 patched KWin)" >&2
  fi

  # 1. 环境变量
  {
    echo "WAYLAND_DISPLAY=wayland-0"
    echo "DISPLAY=:0"
    echo "QT_QPA_PLATFORM=wayland"
    echo "ANLAND=1"
    echo "ANLAND_SOCKET=/run/display.sock"
    echo "ANLAND_DRM_DEVICE=/dev/dri/renderD128"
    echo "XCURSOR_SIZE=48"
  } | sudo tee -a "$WORKDIR/rootfs/etc/environment" >/dev/null

  # 2. patched KWin/Xwayland 预编译包 (来自 Droidspaces-rootfs-KDE-builder)
  if [ "$ARCH" = "arm64" ] && { [ "$DISTRO" = "debian" ] || [ "$DISTRO" = "ubuntu" ]; }; then
    PKGDIR=""
    [ "$DISTRO" = "debian" ] && PKGDIR="Debian13"
    [ "$DISTRO" = "ubuntu" ] && PKGDIR="ubuntu2604"
    if [ -n "$PKGDIR" ]; then
      BASE_URL="https://github.com/Goldzxcbug/Droidspaces-rootfs-KDE-builder/raw/main/anland-build/$PKGDIR"
      echo "==> 下载 patched KWin/Xwayland 包 ($PKGDIR)"
      mkdir -p "$WORKDIR/pkgs"
      FILES=$(curl -s "https://api.github.com/repos/Goldzxcbug/Droidspaces-rootfs-KDE-builder/contents/anland-build/$PKGDIR" \
        | grep -oE '"name": "[^"]*\.(deb|rpm)"' | sed 's/"name": "//;s/"$//')
      for f in $FILES; do
        curl -sfL "$BASE_URL/$f" -o "$WORKDIR/pkgs/$f" || echo "警告: 下载 $f 失败" >&2
      done
      if ls "$WORKDIR/pkgs/"*.deb >/dev/null 2>&1; then
        sudo cp "$WORKDIR/pkgs/"*.deb "$WORKDIR/rootfs/tmp/"
        echo "==> 安装 patched 包并锁定版本"
        CHROOT_SH "cd /tmp && dpkg -i kwin-*.deb libkwin6*.deb xwayland*.deb || true; \
          apt-get -f install -y --no-install-recommends || true; \
          apt-mark hold kwin-common kwin-data kwin-wayland libkwin6 xwayland || true; rm -f /tmp/*.deb" || true
      fi
    fi
  fi

  # 3. Plasma Wayland 自启动服务 (直接落文件 + 软链接, chroot 内无法运行 systemctl)
  sudo tee "$WORKDIR/rootfs/etc/systemd/system/plasma-wayland.service" >/dev/null <<'EOF'
[Unit]
Description=Start Plasma Wayland (Anland)
After=network.target display-manager.service
StartLimitIntervalSec=60
StartLimitBurst=5

[Service]
Type=simple
User=1000
PAMName=login
EnvironmentFile=-/etc/environment
ExecStart=/bin/bash -lc 'startplasma-wayland'
Restart=on-failure
RestartSec=2s

[Install]
WantedBy=multi-user.target
EOF
  sudo ln -sf /etc/systemd/system/plasma-wayland.service \
    "$WORKDIR/rootfs/etc/systemd/system/multi-user.target.wants/plasma-wayland.service"
fi

# ---------- X11 启动服务 (KDE 非 Anland 模式) ----------
if [ "$KDE" != "none" ] && [ "$ANLAND" != "true" ]; then
  echo "==> 配置 X11 自启动 (DISPLAY=:5)"
  echo "DISPLAY=:5" | sudo tee -a "$WORKDIR/rootfs/etc/environment" >/dev/null
  sudo tee "$WORKDIR/rootfs/etc/systemd/system/plasma-x11.service" >/dev/null <<'EOF'
[Unit]
Description=Start Plasma X11
After=network.target display-manager.service
StartLimitIntervalSec=60
StartLimitBurst=5

[Service]
Type=simple
User=1000
PAMName=login
EnvironmentFile=-/etc/environment
ExecStart=/bin/bash -lc 'DISPLAY=:5 startplasma-x11'
Restart=on-failure
RestartSec=2s

[Install]
WantedBy=multi-user.target
EOF
  sudo ln -sf /etc/systemd/system/plasma-x11.service \
    "$WORKDIR/rootfs/etc/systemd/system/multi-user.target.wants/plasma-x11.service"
fi

# ---------- 清理并重新打包 ----------
for m in proc dev sys; do sudo umount -R "$WORKDIR/rootfs/$m" >/dev/null 2>&1 || true; done
sudo umount -R "$WORKDIR/rootfs" >/dev/null 2>&1 || true
sudo rm -f "$WORKDIR/rootfs/etc/resolv.conf"

echo "==> 重新打包 $OUT_TAR"
sudo tar -C "$WORKDIR/rootfs" -cJf "$OUT_TAR" .
sudo chown "$(id -u):$(id -g)" "$OUT_TAR"
echo "==> 完成"

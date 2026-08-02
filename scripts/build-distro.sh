#!/usr/bin/env bash
# 使用 distrobuilder 构建 LXC rootfs 包 (Debian / Ubuntu / ArchLinux / Kali)
#
# 用法: build-distro.sh <yaml文件> <release> <arch> <variant> <compression> <输出目录>
# 示例: build-distro.sh images/ubuntu.yaml noble arm64 default xz ./output
set -euo pipefail

YAML=$1
RELEASE=$2
ARCH=$3
VARIANT=$4
COMPRESSION=$5
OUTDIR=$6

if [ ! -f "$YAML" ]; then
  echo "错误: 找不到 yaml 文件 $YAML" >&2
  exit 1
fi

DISTRO=$(basename "$YAML" .yaml)
mkdir -p "$OUTDIR"

WORKDIR=$(mktemp -d)
trap 'sudo rm -rf "$WORKDIR"' EXIT

echo "==> 构建 $DISTRO  (release=$RELEASE arch=$ARCH variant=$VARIANT compression=$COMPRESSION)"

ARGS=(-o "image.architecture=$ARCH" -o "image.variant=$VARIANT")
[ -n "$RELEASE" ] && ARGS+=(-o "image.release=$RELEASE")

# 非 amd64 的 Ubuntu 包在 ports.ubuntu.com
if [ "$DISTRO" = "ubuntu" ] && [ "$ARCH" != "amd64" ]; then
  ARGS+=(-o "source.url=http://ports.ubuntu.com/ubuntu-ports")
fi

# arm64 的 Arch 使用 Arch Linux ARM 源
if [ "$DISTRO" = "archlinux" ] && [ "$ARCH" = "arm64" ]; then
  ARGS+=(-o "source.url=https://fl.us.mirror.archlinuxarm.org")
fi

cd "$WORKDIR"
sudo distrobuilder build-lxc "$YAML" "${ARGS[@]}" --compression "$COMPRESSION"

ROOTFS_FILE=$(ls rootfs.tar.* 2>/dev/null | head -1)
if [ -z "$ROOTFS_FILE" ]; then
  echo "错误: 未找到构建产物 rootfs.tar.*" >&2
  exit 1
fi

PREFIX="$OUTDIR/${DISTRO}-${RELEASE}-${ARCH}-${VARIANT}"
sudo mv "$ROOTFS_FILE" "$PREFIX-rootfs.${ROOTFS_FILE#rootfs.}"
[ -f meta.tar.xz ] && sudo mv meta.tar.xz "$PREFIX-meta.tar.xz"

sudo chown "$(id -u):$(id -g)" "$OUTDIR"/* 2>/dev/null || true
echo "==> 完成: $PREFIX-rootfs.${ROOTFS_FILE#rootfs.}"

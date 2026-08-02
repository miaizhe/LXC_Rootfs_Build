#!/usr/bin/env bash
# 构建 NixOS LXC rootfs 包
#
# NixOS 无法像传统发行版一样 debootstrap/降级安装, 官方 images.linuxcontainers.org
# 的做法是从 Hydra CI 获取预构建的容器 rootfs (squashfs), 此处保持一致:
# 下载后解包并重新打成 tar.xz。
#
# 用法: build-nixos.sh <release> <arch> <输出目录>
# 示例: build-nixos.sh 26.05 arm64 ./output
#       build-nixos.sh unstable amd64 ./output
set -euo pipefail

RELEASE=$1
ARCH=$2
OUTDIR=$3

mkdir -p "$OUTDIR"

case "$RELEASE" in
  unstable) JOBSET="unstable" ;;
  *) JOBSET="release-${RELEASE}" ;;
esac

case "$ARCH" in
  arm64) NIXARCH="aarch64" ;;
  amd64) NIXARCH="x86_64" ;;
  *) echo "错误: 不支持的架构 $ARCH" >&2; exit 1 ;;
esac

BASE="https://hydra.nixos.org/job/nixos/${JOBSET}/nixos.incusContainerImage.${NIXARCH}-linux/latest/download-by-type/file"

WORKDIR=$(mktemp -d)
trap 'sudo rm -rf "$WORKDIR"' EXIT

echo "==> 下载 NixOS 容器 rootfs (release=$RELEASE arch=$ARCH)"
curl -fL "$BASE/squashfs-image" -o "$WORKDIR/rootfs.squashfs"

echo "==> 解包并重新打包为 tar.xz"
sudo unsquashfs -d "$WORKDIR/rootfs" "$WORKDIR/rootfs.squashfs" >/dev/null

OUT="$OUTDIR/nixos-${RELEASE}-${ARCH}-default-rootfs.tar.xz"
sudo tar -C "$WORKDIR/rootfs" -cJf "$OUT" .
sudo chown "$(id -u):$(id -g)" "$OUT"

echo "==> 完成: $OUT"

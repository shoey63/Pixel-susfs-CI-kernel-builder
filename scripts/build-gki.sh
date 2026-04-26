#!/bin/bash
set -e

WORKSPACE="workspace"
DIST_DIR="out/dist"

cd "${WORKSPACE}"

echo "=== Applying ABI Fixes ==="
echo "Neutralizing ABI protected exports for Pixel compatibility..."
> common/android/abi_gki_protected_exports_aarch64
> common/android/abi_gki_protected_exports_x86_64

echo "=== Integrating KernelSU-Next ==="
echo "Cloning shoey63/KernelSU-Next (branch: pixel9-susfs-gki-android14-6.1)..."
git clone https://github.com/shoey63/KernelSU-Next.git -b pixel9-susfs-gki-android14-6.1 KernelSU-Next

echo "Running KernelSU-Next setup..."
bash KernelSU-Next/kernel/setup.sh

echo "Restoring the custom pixel9-susfs branch..."
cd KernelSU-Next
git checkout pixel9-susfs-gki-android14-6.1
cd ..

echo "=== Integrating susfs4ksu ==="
echo "Cloning shoey63/susfs4ksu (branch: gki-android14-6.1-dev)..."
git clone https://gitlab.com/shoey63/susfs4ksu.git -b gki-android14-6.1-dev susfs4ksu

echo "Copying susfs source files..."
# Copies the susfs drivers and headers into the kernel tree
cp -r susfs4ksu/kernel_patches/fs/* common/fs/
cp -r susfs4ksu/kernel_patches/include/linux/* common/include/linux/

echo "Applying susfs kernel patches..."
cd common
# Grab the kernel-side patch and apply it
# Using a wildcard dynamically targets the '50_add_susfs_in_...' patch for your specific branch
cp ../susfs4ksu/kernel_patches/50_add_susfs_in_*.patch .
patch -p1 < 50_add_susfs_in_*.patch
cd ..

echo "=== Building GKI via Kleaf (Bazel) ==="
tools/bazel run --color=no --curses=no //common:kernel_aarch64_dist -- --dist_dir="${DIST_DIR}" 2>&1 | tee build.log

echo "=== Preparing Artifacts ==="
mv "${DIST_DIR}/Image" ./Image

echo "=== Build Complete ==="

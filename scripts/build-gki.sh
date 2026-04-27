#!/bin/bash
set -e

WORKSPACE="workspace"
DIST_DIR="out/dist"

cd "${WORKSPACE}"

echo "=== Applying ABI Fixes ==="
> common/android/abi_gki_protected_exports_aarch64
> common/android/abi_gki_protected_exports_x86_64

echo "=== Integrating KernelSU-Next ==="
git clone https://github.com/shoey63/KernelSU-Next.git -b pixel9-susfs-gki-android14-6.1 KernelSU-Next

bash KernelSU-Next/kernel/setup.sh

echo "Restoring the custom pixel9-susfs branch..."
cd KernelSU-Next
git checkout pixel9-susfs-gki-android14-6.1

echo "=== Grabbing Git info for KSU manager ==="
KSU_TAG=$(git describe --abbrev=0 --tags 2>/dev/null || echo "v1.0.0")
KSU_HASH=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
cd ..

echo "Replacing KSU symlink with a hard copy for the Bazel sandbox..."
rm -f common/drivers/kernelsu
cp -r KernelSU-Next/kernel common/drivers/kernelsu

echo "Hunting down missing uapi headers..."
UAPI_DIR=$(find KernelSU-Next -type d -name "uapi" | head -n 1)
if [ -n "$UAPI_DIR" ]; then
    echo "Found uapi at $UAPI_DIR, injecting into sandbox sightlines..."
    cp -r "$UAPI_DIR" common/drivers/kernelsu/
    cp -r "$UAPI_DIR" common/drivers/
else
    echo "WARNING: Could not find uapi folder in KernelSU-Next!"
fi

# Strip config constraints
sed -i '/default [yn]/d' common/drivers/kernelsu/Kconfig || true
sed -i 's/^config .*/&\n\tdefault y/g' common/drivers/kernelsu/Kconfig || true

echo "=== Integrating susfs4ksu ==="
# Pointing to the stable branch!
git clone https://gitlab.com/shoey63/susfs4ksu.git -b gki-android14-6.1-dev susfs4ksu

cp -r susfs4ksu/kernel_patches/fs/* common/fs/
cp -r susfs4ksu/kernel_patches/include/linux/* common/include/linux/

echo "Applying susfs kernel patches..."
cd common
cp ../susfs4ksu/kernel_patches/50_add_susfs_in_*.patch .
# We use '|| true' so the build doesn't die when Pixel trace hooks reject a hunk
patch -p1 < 50_add_susfs_in_*.patch || true

echo "=== Dynamically injecting rejected patch hunks ==="

# Fix 1: fs/namespace.c (Missing includes)
sed -i '/#include <linux\/mnt_idmapping.h>/a \
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\
#include <linux\/susfs_def.h>\n\
#endif \/\/ #ifdef CONFIG_KSU_SUSFS_SUS_MOUNT' fs/namespace.c

# Fix 2: fs/namespace.c (Missing declarations)
sed -i '/static unsigned int sysctl_mount_max/i \
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n\
extern bool susfs_is_current_ksu_domain(void);\n\
extern struct static_key_false susfs_set_sdcard_android_data_decrypted_key_false;\n\
#define CL_COPY_MNT_NS BIT(25) \/* used by copy_mnt_ns() *\/\n\
static DEFINE_IDA(susfs_mnt_id_ida);\n\
static DEFINE_IDA(susfs_mnt_group_ida);\n\
#endif \/\/ #ifdef CONFIG_KSU_SUSFS_SUS_MOUNT\n' fs/namespace.c

# Fix 3: fs/devpts/inode.c (Missing extern)
sed -i '/devpts_get_priv -- get private data for a slave/i \
#ifdef CONFIG_KSU_SUSFS\n\
extern int ksu_handle_devpts(struct inode*);\n\
#endif\n' fs/devpts/inode.c

# Fix 4: fs/devpts/inode.c (Missing devpts hook)
sed -i '/if (dentry->d_sb->s_magic != DEVPTS_SUPER_MAGIC)/i \
#ifdef CONFIG_KSU_SUSFS\n\
\tif (likely(susfs_is_current_proc_umounted())) {\n\
\t\tgoto orig_flow;\n\
\t}\n\
\tksu_handle_devpts(dentry->d_inode);\n\
orig_flow:\n\
#endif\n' fs/devpts/inode.c

cd ..

echo "=== Building GKI via Kleaf (Bazel) ==="
# Passing the KSU variables directly into the Bazel sandbox
tools/bazel run --color=no --curses=no \
  --action_env=KSU_VERSION_TAG="$KSU_TAG" \
  --action_env=KSU_GIT_VERSION="$KSU_HASH" \
  //common:kernel_aarch64_dist -- --dist_dir="${DIST_DIR}" 2>&1 | tee build.log

echo "=== Preparing Artifacts ==="
mv "${DIST_DIR}/Image" ./Image

echo "=== Fetching Stock Boot Image ==="
python3 scripts/ota_pull.py \
  --source "https://dl.google.com/dl/android/aosp/komodo-ota-cp1a.260405.005-62a6d5ce.zip" \
  --partition boot \
  --outdir ./stock_boot

echo "=== Repacking Custom Boot Image ==="
chmod +x tools/magiskboot
chmod +x scripts/boot_swap.sh

scripts/boot_swap.sh \
  --boot ./stock_boot/boot-*.img \
  --image ./Image \
  --magiskboot tools/magiskboot \
  --outdir ./ \
  --outname "pixel9-susfs-patched-boot.img"

echo "=== Assembly Complete ==="

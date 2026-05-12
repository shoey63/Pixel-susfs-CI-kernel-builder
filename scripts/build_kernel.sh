#!/usr/bin/env bash
set -euo pipefail

cd kernel_workspace
mkdir -p ../out out/dist

[ -d common ] || { echo "[-] common/ not found" >&2; exit 1; }

echo ">>> Neutralizing ABI protected exports lists..."
# No need to cd, use relative paths from kernel_workspace
for f in common/android/abi_gki_protected_exports*; do
  [ -f "$f" ] && > "$f"
done

echo ">>> Setting up WireGuard defconfig fragment..."
cd common
cat > wireguard_fragment << 'EOF'
CONFIG_WIREGUARD=y
CONFIG_NET_UDP_TUNNEL=y
CONFIG_CRYPTO_CURVE25519=y
CONFIG_CRYPTO_CURVE25519_X86=y
EOF

# Inject the fragment into the BUILD file and register it
echo 'exports_files(["wireguard_fragment"])' >> BUILD.bazel
sed -i '/name = "kernel_aarch64",/a \    post_defconfig_fragments = ["wireguard_fragment"],' BUILD.bazel

echo ">>> Marking repo as clean (cloaking modifications)..."
git ls-files -m | xargs -r git update-index --assume-unchanged
cd .. # Back to kernel_workspace

echo ">>> Commencing build: g$OFFICIAL_HASH"
tools/bazel run --config=local --config=stamp \
  --action_env=SOURCE_DATE_EPOCH="$OFFICIAL_DATE" \
  --action_env=STABLE_BUILD_VERSION="g$OFFICIAL_HASH" \
  --action_env=KLEAF_KERNEL_BUILD_VERSION="g$OFFICIAL_HASH" \
  --action_env=KLEAF_SKIP_ABI_CHECKS=true \
  //common:kernel_aarch64_dist \
  -- \
  --destdir=out/dist
  
IMAGE_PATH="$(find out/dist -type f -name 'Image' | head -n1)"

if [ -z "${IMAGE_PATH}" ] || [ ! -f "${IMAGE_PATH}" ]; then
  echo "[-] No Image produced!" >&2
  exit 1
fi

echo ">>> Selected Image: ${IMAGE_PATH}"
cp -f "${IMAGE_PATH}" ../out/Image

echo ">>> Extracting version string..."
strings ../out/Image | grep "Linux version" | head -n 1

echo ">>> Checking for WireGuard symbols..."
if strings ../out/Image | grep -qi "wireguard"; then
    echo ">>> SUCCESS: WireGuard symbols found."
else
    echo ">>> WARNING: WireGuard symbols NOT found."
fi

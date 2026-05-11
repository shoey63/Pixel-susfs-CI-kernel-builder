#!/usr/bin/env bash
# Move into the workspace where the kernel source actually lives
cd kernel_workspace/common || { echo ">>> ERROR: kernel_workspace/common not found"; exit 1; }

echo ">>> Injecting WireGuard into gki_defconfig..."

GKI_CONF="arch/arm64/configs/gki_defconfig"

echo ">>> Forcing WireGuard + Tunneling Dependencies..."

GKI_CONF="arch/arm64/configs/gki_defconfig"

# 1. Clean up any existing instances to avoid duplicates
sed -i '/CONFIG_WIREGUARD/d' "$GKI_CONF"
sed -i '/CONFIG_NET_UDP_TUNNEL/d' "$GKI_CONF"

# 2. Append the clean targets
{
  echo "CONFIG_WIREGUARD=y"
  echo "CONFIG_NET_UDP_TUNNEL=y"
  echo "CONFIG_CRYPTO_CURVE25519=y"
} >> "$GKI_CONF"

echo ">>> Verification:"
grep -E "WIREGUARD|NET_UDP_TUNNEL" "$GKI_CONF"

cd ..

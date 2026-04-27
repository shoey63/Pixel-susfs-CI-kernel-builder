#!/usr/bin/env bash
set -euo pipefail

cd kernel_workspace
mkdir -p ../out out/dist

die() {
  echo "[-] $*" >&2
  exit 1
}

info() {
  echo "[+] $*"
}

[ -d common ] || die "common/ not found in kernel_workspace"
[ -x tools/bazel ] || die "tools/bazel not found or not executable"

info "Workspace: $(pwd)"
info "Building pure common Android 14 6.1 arm64 kernel"
info "Using Kleaf target: //common:kernel_aarch64_dist"
info "Dist dir: $(pwd)/out/dist"

rm -f ../out/build_common_kernel.log \
      ../out/image_paths.txt \
      ../out/image_hashes.txt \
      ../out/image_fileinfo.txt \
      ../out/image_strings.txt \
      ../out/dist_file_list.txt \
      ../out/abi_exports_status.txt

rm -rf ../out/abi_exports_backup
mkdir -p ../out/abi_exports_backup

info "Neutralizing ABI protected exports lists if present"
for f in \
  common/android/abi_gki_protected_exports \
  common/android/abi_gki_protected_exports_aarch64 \
  common/android/abi_gki_protected_exports_x86_64
do
  if [ -f "$f" ]; then
    info "Backing up and emptying $f"
    cp -f "$f" "../out/abi_exports_backup/$(basename "$f")"
    : > "$f"
    ls -lh "$f"
  else
    info "Not present: $f"
  fi
done

{
  echo "=== ABI protected exports after neutralizing ==="
  for f in \
    common/android/abi_gki_protected_exports \
    common/android/abi_gki_protected_exports_aarch64 \
    common/android/abi_gki_protected_exports_x86_64
  do
    if [ -f "$f" ]; then
      echo "--- $f"
      ls -lh "$f"
      wc -c "$f"
    else
      echo "--- missing: $f"
    fi
  done
} > ../out/abi_exports_status.txt

tools/bazel run \
  --config=local \
  //common:kernel_aarch64_dist \
  -- \
  --destdir=out/dist 2>&1 | tee ../out/build_common_kernel.log

info "Listing dist contents"
find out/dist -maxdepth 3 -type f | sort | tee ../out/dist_file_list.txt

IMAGE_PATH="$(find out/dist -type f -name 'Image' | head -n1 || true)"

if [ -z "${IMAGE_PATH}" ] || [ ! -f "${IMAGE_PATH}" ]; then
  echo ">>> Could not find Image in out/dist" >&2
  find out -type f -name 'Image' | sort >&2 || true
  die "No Image produced by common kernel build"
fi

info "Selected Image: ${IMAGE_PATH}"

cp -f "${IMAGE_PATH}" ../out/Image

{
  echo "IMAGE_PATH=${IMAGE_PATH}"
} > ../out/image_paths.txt

sha256sum ../out/Image > ../out/image_hashes.txt
file ../out/Image > ../out/image_fileinfo.txt
strings ../out/Image | grep -Ei 'Linux version|KernelSU|SUSFS' > ../out/image_strings.txt || true

info "Done"
ls -lh ../out/Image
cat ../out/image_paths.txt
cat ../out/image_hashes.txt

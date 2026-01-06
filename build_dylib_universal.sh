#!/usr/bin/env bash
set -euo pipefail

# build_dylib_universal.sh
# Build a universal (arm64 + x86_64) macOS dylib for shaderc
# Usage:
#   ./build_dylib_universal.sh [--build-type Release] [--archs "arm64 x86_64"]

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_TYPE="${BUILD_TYPE:-Release}"
ARCHS="${ARCHS:-arm64 x86_64}"
JOBS="${JOBS:-$(sysctl -n hw.logicalcpu)}"

# Prefer Ninja when available for faster builds
if command -v ninja >/dev/null 2>&1; then
  GENERATOR="Ninja"
else
  GENERATOR="Unix Makefiles"
fi

echo "Repository root: ${REPO_ROOT}"
echo "Build type: ${BUILD_TYPE}"
echo "Architectures: ${ARCHS}"
echo "CMake generator: ${GENERATOR}"

for arch in ${ARCHS}; do
  BUILD_DIR="${REPO_ROOT}/build-macos-${arch}"
  echo "\n=== Configuring for ${arch} in ${BUILD_DIR} ==="
  mkdir -p "${BUILD_DIR}"
  pushd "${BUILD_DIR}" >/dev/null

  cmake_args=(
    -DCMAKE_BUILD_TYPE=${BUILD_TYPE}
    -DCMAKE_OSX_ARCHITECTURES=${arch}
    -DSHADERC_SKIP_TESTS=ON
    -DSHADERC_SKIP_EXAMPLES=ON
    -DSHADERC_SKIP_INSTALL=ON
    -DSHADERC_SKIP_COPYRIGHT_CHECK=ON
    -DCMAKE_SKIP_INSTALL_RULES=ON
  )

  if [ -n "${GENERATOR}" ]; then
    cmake -G "${GENERATOR}" "${cmake_args[@]}" "${REPO_ROOT}"
  else
    cmake "${cmake_args[@]}" "${REPO_ROOT}"
  fi

  cmake --build . --config "${BUILD_TYPE}" -- -j "${JOBS}"
  popd >/dev/null
done

echo "\n=== Locating built dylibs ==="
OUT_DIR="${REPO_ROOT}/build-universal/lib"
mkdir -p "${OUT_DIR}"

# Function to create universal dylib
create_universal_dylib() {
  local lib_name=$1
  local search_pattern=$2
  local output_name=$3
  local rpath_id=$4
  
  echo "\n=== Creating universal dylib: ${output_name} ==="
  local dylib_paths=()
  
  for arch in ${ARCHS}; do
    local search_dir="${REPO_ROOT}/build-macos-${arch}"
    # Find actual files (not symlinks) matching the pattern
    # Use -type f to get only regular files, not symlinks
    local found=$(find "${search_dir}" -type f -name "${search_pattern}" 2>/dev/null | head -n1 || true)
    if [ -z "${found}" ]; then
      echo "ERROR: No ${lib_name} dylib found under ${search_dir} for arch ${arch}" >&2
      return 1
    fi
    echo "Found for ${arch}: ${found}"
    dylib_paths+=("${found}")
  done
  
  if [ ${#dylib_paths[@]} -lt 2 ]; then
    echo "ERROR: need at least two arch builds to create a universal dylib" >&2
    return 1
  fi
  
  lipo -create "${dylib_paths[@]}" -output "${output_name}"
  
  if [ -n "${rpath_id}" ]; then
    install_name_tool -id "${rpath_id}" "${output_name}"
  fi
  
  file "${output_name}" || true
  otool -L "${output_name}" || true
  echo "Universal dylib created at: ${output_name}"
}

# Create libshaderc_shared.dylib
create_universal_dylib \
  "libshaderc_shared" \
  "libshaderc_shared*.dylib" \
  "${OUT_DIR}/libshaderc_shared.dylib" \
  "@rpath/libshaderc_shared.dylib"

# Create libglslang.dylib (find the versioned file, not symlinks)
# Look for files like libglslang.16.1.0.dylib in third_party/glslang/glslang/
echo "\n=== Creating universal dylib: ${OUT_DIR}/libglslang.dylib ==="
glslang_dylib_paths=()

for arch in ${ARCHS}; do
  search_dir="${REPO_ROOT}/build-macos-${arch}/third_party/glslang/glslang"
  # Find actual files (not symlinks) with version numbers like libglslang.16.1.0.dylib
  found=$(find "${search_dir}" -type f -name "libglslang.*.dylib" 2>/dev/null | grep -E "libglslang\.[0-9]+\.[0-9]+\.[0-9]+\.dylib$" | head -n1 || true)
  if [ -z "${found}" ]; then
    echo "ERROR: No libglslang dylib found under ${search_dir} for arch ${arch}" >&2
    exit 1
  fi
  echo "Found for ${arch}: ${found}"
  glslang_dylib_paths+=("${found}")
done

if [ ${#glslang_dylib_paths[@]} -lt 2 ]; then
  echo "ERROR: need at least two arch builds to create a universal dylib" >&2
  exit 1
fi

lipo -create "${glslang_dylib_paths[@]}" -output "${OUT_DIR}/libglslang.dylib"
install_name_tool -id "@rpath/libglslang.dylib" "${OUT_DIR}/libglslang.dylib"
file "${OUT_DIR}/libglslang.dylib" || true
otool -L "${OUT_DIR}/libglslang.dylib" || true
echo "Universal dylib created at: ${OUT_DIR}/libglslang.dylib"

# Fix libshaderc_shared.dylib to reference libglslang.dylib (without version) instead of libglslang.16.dylib
echo "\n=== Fixing libshaderc_shared.dylib dependencies ==="
install_name_tool -change "@rpath/libglslang.16.dylib" "@rpath/libglslang.dylib" "${OUT_DIR}/libshaderc_shared.dylib"
echo "Updated libshaderc_shared.dylib to reference libglslang.dylib"
otool -L "${OUT_DIR}/libshaderc_shared.dylib" || true

echo "\n=== All universal dylibs created successfully ==="

exit 0

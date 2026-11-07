#!/bin/bash
set -e

# ===== KONFIGURASI =====
export ANDROID_NDK_HOME=/home/sandi/sdk-17/ndk/30.0.16248370
export TOOLCHAIN=$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64
export CC=$TOOLCHAIN/bin/clang
export CXX=$TOOLCHAIN/bin/clang++

PROJECT_ROOT=/home/sandi/BOTWRecompAndroid
cd "$PROJECT_ROOT"

# ===== LANGKAH 1: GENERATE KODE C =====
echo "=== Generating C code ==="
cd tools
python3 gen.py main ../full_mia/main.nso 0x7100000000 ../android/out/gen \
    --hle ../runtime/hle/hle_symbols.txt --dyn-base
cd ..

# ===== LANGKAH 2: COMPILE =====
echo "=== Compiling ==="
cd android/out/gen
mkdir -p obj

# SEMUA INCLUDE PATHS yang dibutuhkan
CFLAGS="-target aarch64-none-linux-android30 \
        --sysroot=$TOOLCHAIN/sysroot \
        -DANDROID \
        -DLARECOMP_NO_FFMPEG \
        -DIMGUI_IMPL_VULKAN_USE_VOLK \
        -DVK_NO_PROTOTYPES \
        -DVK_USE_PLATFORM_ANDROID_KHR \
        -DVMA_DYNAMIC_VULKAN_FUNCTIONS=1 \
        -DVMA_STATIC_VULKAN_FUNCTIONS=0 \
        -I$PROJECT_ROOT/runtime \
        -I$PROJECT_ROOT/runtime/nvn \
        -I$PROJECT_ROOT/third_party/imgui \
        -I$PROJECT_ROOT/third_party/imgui/backends \
        -I$PROJECT_ROOT/android/deps/out/include \
        -I$PROJECT_ROOT/android/deps/out/volk \
        -I$PROJECT_ROOT/third_party/smaa/Textures \
        -I$PROJECT_ROOT/android/common \
        -I$PROJECT_ROOT/third_party/libadrenotools/include \
        -I$PROJECT_ROOT/third_party/libadrenotools/lib/linkernsbypass/. \
        -fPIC -O2 -g -fno-strict-aliasing \
        -Wall -Wno-unused-function -Wno-format"

# Compile semua file .c hasil gen.py dengan parallel
echo "Compiling with $(nproc) cores..."
find . -name 'main_*.c' | xargs -P$(nproc) -I{} sh -c \
    '$CC $CFLAGS -c "{}" -o "obj/$(basename {} .c).o" 2>&1 | grep -v "^$" || true'

# ===== LANGKAH 3: LINK =====
echo "=== Linking ==="
$CC -shared \
    -target aarch64-none-linux-android30 \
    --sysroot=$TOOLCHAIN/sysroot \
    -Wl,--build-id=sha1 \
    -Wl,--no-undefined \
    -Wl,-soname,botwgame.so \
    obj/*.o \
    -o ../botwgame.so \
    -llog -landroid -lz -lm

echo "=== Done! ==="
ls -lh ../botwgame.so

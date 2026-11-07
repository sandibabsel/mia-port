#!/bin/bash
# build_full.sh: builds the app, regenerates the game code, and builds botwgame.so (+ .id) and romfs.bin for Made in Abyss.
# Stops at the first failing step (set -e). Skip steps with env vars:
#   SKIP_APP=1  SKIP_GEN=1 (keeps generated-android-dyn)  SKIP_LIB=1  SKIP_ROMFS=1      HEAVY=4000 (labels per function -> -O0)
set -euo pipefail

PROJECT_ROOT=${PROJECT_ROOT:-/home/sandi/BOTWRecompAndroid}
export ANDROID_HOME=${ANDROID_HOME:-/home/sandi/sdk-17}
NDK=${NDK:-$ANDROID_HOME/ndk/30.0.16248370}
CM=$ANDROID_HOME/cmake/3.30.4/bin
HEAVY=${HEAVY:-4000}
EXEFS=$PROJECT_ROOT/mia_exefs

cd "$PROJECT_ROOT"                       # (everything below is relative to the repository)
GEN=$PROJECT_ROOT/generated-android-dyn
W=$PROJECT_ROOT/android/out/gamelib-build

# 1. the app (libmain.so). Its GAMELIB_ID must be the library's, so it comes before the library and must be installed on the phone
if [ "${SKIP_APP:-0}" != 1 ]; then
    (cd android/botwrecompandroid
     if adb get-state >/dev/null 2>&1; then ./gradlew installDebug
     else ./gradlew assembleDebug; echo "NO PHONE CONNECTED: the app was built, not installed. Install app/build/outputs/apk/debug/app-debug.apk (adb install -r) before running."; fi)
fi

# libmain.so is looked up AFTER the app build, and the script stops if it is not there
LIBMAIN=$(ls -t "$PROJECT_ROOT"/android/botwrecompandroid/app/build/intermediates/cxx/*/*/obj/arm64-v8a/libmain.so 2>/dev/null | head -1 || true)
[ -n "$LIBMAIN" ] || { echo "libmain.so not found: the app build failed or never ran (see its errors above)"; exit 1; }
echo "libmain.so: $LIBMAIN"

# 2. the game code (a fresh folder: a stale chunk from an older run would be compiled too)
if [ "${SKIP_GEN:-0}" != 1 ]; then
    rm -rf "$GEN"
    (cd tools
     ../tools/venv/bin/python -u gen.py sdk "$EXEFS/sdk" 0x7010000000 ../generated-android-dyn/sdk --hle ../runtime/hle/hle_symbols.txt --simd asm --dyn-base
     ../tools/venv/bin/python -u gen.py main "$EXEFS/main" 0x7000000000 ../generated-android-dyn/main --simd asm --dyn-base)
fi

# 3. botwgame.so and botwgame.so.id
if [ "${SKIP_LIB:-0}" != 1 ]; then
    # files with a function of more than $HEAVY labels are compiled at -O0
    (cd "$GEN" && for f in main/*.c sdk/*.c; do
        awk -v f="$f" -v h="$HEAVY" '/^[a-zA-Z].* f_[0-9a-f]+\(.*\) \{$/ {n = 0} /^L_[0-9a-f]+:/ {if (++n > h) {print f; exit}}' "$f"
    done) > "$GEN/heavy.txt"
    echo "heavy (at -O0): $(tr '\n' ' ' < "$GEN/heavy.txt")"

    "$CM/cmake" -S android/gamelib -B "$W" -G Ninja -DCMAKE_MAKE_PROGRAM="$CM/ninja" \
        -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-30 \
        -DCMAKE_BUILD_TYPE=Release -DLAS_GEN="$GEN" -DLAS_LIBMAIN="$LIBMAIN"
    "$CM/cmake" --build "$W" -j3

    mkdir -p android/out
    cp "$W/botwgame.so" "$W/botwgame.so.id" android/out/
    "$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/llvm-strip" --strip-debug android/out/botwgame.so
    ls -la android/out/botwgame.so android/out/botwgame.so.id
fi

# 4. romfs.bin (only when the romfs folder changed: it is slow and the file is big)
if [ "${SKIP_ROMFS:-0}" != 1 ]; then
    [ -x ./romfs_tool ] || gcc -O2 -D_FILE_OFFSET_BITS=64 -Iruntime android/tools/romfs_tool.c runtime/romfs_build.c -o romfs_tool
    ./romfs_tool mia_game/romfs mia_game/romfs.bin
fi

echo "done. Next: adb push android/out/botwgame.so android/out/botwgame.so.id /sdcard/Botw-mia/extracted/  (and romfs.bin), then bash android/run_mia.sh 120"

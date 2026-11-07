#!/bin/bash
# [MIA-PATCH] delivery: 2026-11-07 09:20 WIB
# BANGUN-PC-3N: rebuild botwgame.so DI PC dengan boundary ekstra 3n, lalu push ke HP dan boot.
# Pakai:  ./BANGUN-PC-3N.sh <folder-exefs-mia> [daftar-alamat] [folder-repo]
#   <folder-exefs-mia> : main, sdk, multimedia, main.npdm (seperti PANDUAN 3b)
#   [daftar-alamat]    : alamat FATAL "no function at", default 0x100bf7608 (boot 08:32).
#                        Kumulatif, pisah koma, contoh:  ./BANGUN-PC-3N.sh exefs_mia 0x100bf7608,0x100d12345
#   [folder-repo]      : default dicari dari folder sekarang/atasnya
# Syarat (PC yang pernah build): tools/venv ada, libmain.so pernah dibangun (gradlew assembleDebug), NDK ada.
# Cara kerja: gen.py 3n dipasang ke tools/ repo (idempoten), HANYA main di-generate ulang dengan
#   LARECOMP_EXTRA_BOUNDS (sdk & multimedia tidak disentuh), lalu build_gamelib.sh - chunk yang
#   isinya tidak berubah dipertahankan (write_if_changed) sehingga ninja hanya compile ulang yang
#   berubah: jauh lebih cepat dari build pertama yang berjam-jam. JANGAN hapus folder generated.
set -euo pipefail

BND="$(cd "$(dirname "$0")" && pwd)"
EXEFS="${1:?pakai: $0 <folder-exefs-mia> [alamat1,alamat2] [folder-repo]}"
BOUNDS="${2:-0x100bf7608}"
REPO="${3:-}"
if [ -z "$REPO" ]; then
    for d in "$PWD" "$PWD/.." "$PWD/../.." "$HOME/BOTWRecompAndroid" "$HOME/botw" "$HOME/botwrecompandroid"; do
        if [ -d "$d/runtime/hle" ] && [ -d "$d/android/botwrecompandroid" ]; then REPO="$(cd "$d" && pwd)"; break; fi
    done
fi
if [ -z "$REPO" ] || [ ! -d "$REPO/runtime/hle" ]; then
    echo "ERROR: repo tidak ketemu. Jalankan:  $0 /path/exefs_mia <alamat> /path/repo"; exit 1
fi
[ -f "$EXEFS/main" ] || { echo "ERROR: $EXEFS/main tidak ada (folder exefs MiA: main, sdk, multimedia, main.npdm)"; exit 1; }
[ -x "$REPO/tools/venv/bin/python" ] || { echo "ERROR: $REPO/tools/venv/bin/python tidak ada - venv generator PC belum dibuat"; exit 1; }
echo "== repo: $REPO"
echo "== exefs: $EXEFS"

# ---- 1. pasang gen.py + dispatch.c 3n ke repo (idempoten) ------------------
grep -qs "LARECOMP_EXTRA_BOUNDS" "$REPO/tools/gen.py" \
    || cp -v "$BND/runtime_patch_3n/gen.py" "$REPO/tools/gen.py"
grep -qs "LARECOMP_EXTRA_BOUNDS lalu bangun ulang" "$REPO/runtime/dispatch.c" \
    || cp -v "$BND/runtime_patch_3n/dispatch.c" "$REPO/runtime/dispatch.c"
echo "== gen.py + dispatch.c 3n dipastikan di repo"

# ---- 2. gen ulang HANYA main dengan boundary ekstra ------------------------
export LARECOMP_EXTRA_BOUNDS="$BOUNDS"
GEN="${GAMELIB_GEN:-$REPO/generated-android-dyn-mia}"
mkdir -p "$REPO/android/out"
GLOG="$REPO/android/out/gen-main-3n.log"
echo "== gen.py main dgn LARECOMP_EXTRA_BOUNDS=$BOUNDS (log: $GLOG)"
( cd "$REPO/tools" && ./venv/bin/python gen.py main "$EXEFS/main" 0x7000000000 "$GEN/main" \
    --simd asm --dyn-base ) 2>&1 | tee "$GLOG"
if ! grep -q "extra boundary" "$GLOG"; then
    echo "PERINGATAN: tidak ada baris 'extra boundary' di log - cek penulisan alamat (contoh benar: 0x100bf7608)."
    echo "  Alamat persis seperti dicetak FATAL boleh dipakai apa adanya (gen.py menggesernya ke basis modul)."
fi

# ---- 3. build botwgame.so (hanya chunk yang berubah) -----------------------
echo "== build botwgame.so (ninja incremental, sabar)..."
GAMELIB_GEN="$GEN" bash "$REPO/android/build_gamelib.sh" "$EXEFS"

# ---- 4. push ke HP: files/mia/botwgame.so + .id ----------------------------
OUT="${GAMELIB_OUT:-$REPO/android/out}"
[ -f "$OUT/botwgame.so" ] || { echo "ERROR: $OUT/botwgame.so tidak ada - build gagal?"; exit 1; }
adb get-state >/dev/null 2>&1 || { echo "ERROR: tidak ada perangkat adb (adb devices)"; exit 1; }
adb push "$OUT/botwgame.so" /sdcard/Botw-mia/botwgame.so
adb push "$OUT/botwgame.so.id" /sdcard/Botw-mia/botwgame.so.id
adb shell "run-as com.botwrecomp.android cp /sdcard/Botw-mia/botwgame.so files/mia/botwgame.so"
adb shell "run-as com.botwrecomp.android cp /sdcard/Botw-mia/botwgame.so.id files/mia/botwgame.so.id"
echo "== botwgame.so + .id terpasang di files/mia/"

# ---- 5. boot uji 180 dtk ----------------------------------------------------
if [ "${SKIP_BOOT:-0}" = 1 ]; then
    echo "== SKIP_BOOT=1 - boot dilewati. Nanti manual: cd $REPO && ./android/run_boot.sh 180"
else
    cd "$REPO"
    ./android/run_boot.sh 180
fi

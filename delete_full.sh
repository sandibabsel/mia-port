echo "hapus app .cxx"
rm -rf android/botwrecompandroid/app/.cxx

echo "hapus app /build"
rm -rf android/botwrecompandroid/app/build

echo "hapus apk"
rm -rf android/botwrecompandroid/app/build/outputs/apk/debug/app-debug.apk

echo "hapus generated-android-dyn"
rm -rf generated-android-dyn

echo "hapus botwgame.so dan botwgame.so.id"

rm android/out/botwgame.so
rm android/out/botwgame.so.id

echo "hapus romfs.bin"
rm mia_game/romfs.bin


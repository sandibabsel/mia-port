#!/usr/bin/env python3
"""Pemeriksa layout memori untuk porting Made in Abyss (MiA) ke BOTWRecompAndroid.

Dijalankan di PC, pada folder exefs hasil dump: file `main`, `sdk` (nnSdk.nss), dan
`multimedia` (subsdk0, multimedia.nss - jadi modul ketiga). Memakai loader NSO yang
sama dengan recompiler.

Pakai:
    python3 mia_layout_check.py <folder_exefs>

Keluaran: ukuran decompressed tiap modul, validasi layout, dan nilai persis yang
harus ditulis ke runtime/rt.h, runtime/loader.c, runtime/dispatch.c, runtime/gamelib.h,
tools/gamelib_entry.c, android/build_gamelib.sh dan android/gamelib/CMakeLists.txt.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
_candidates = [
    os.environ.get('BOTW_REPO'),                       # set BOTW_REPO=<path repo>
    os.path.join(HERE, '..', '..', 'botw', 'tools'),   # di samping folder ini (sandbox)
    os.path.join(HERE, '..', 'tools'),                 # <repo>/download/mia_port/
    os.path.join(HERE, 'tools'),                       # <repo>/tools/ kalau disalin ke root
    HERE,                                              # diletakkan langsung di tools/
]
for c in _candidates:
    if c and os.path.isfile(os.path.join(c, 'nso.py')):
        sys.path.insert(0, c)
        break
else:
    sys.exit('nso.py tidak ketemu: set BOTW_REPO=<folder repo BOTWRecompAndroid>')
from nso import Nso

# Layout untuk MiA (offset dari GUEST_LO; jendela tetap 12.5 GB):
LAYOUT = [
    ('MAIN_BASE',  0x0000000000, 'main        (118.6 MB: 0x7692000)'),
    ('SDK_BASE',   0x0008000000, 'sdk         (13.7 MB; main 118.6 MB -> 64 MB lama PASTI tabrakan)'),
    ('MUL_BASE',   0x010000000, 'multimedia  (6.6 MB; modul ketiga baru)'),
    ('HLE_BASE',   0x040000000, 'stub HLE    (sebelumnya +0x0080000000, kini wilayah sdk)'),
    ('TLS_BASE',   0x041000000, 'TLS guest   (sebelumnya +0x0090000000)'),
    ('HLE_HEAP',   0x042000000, 'heap HLE 0xE000000 (berakhir +0x50000000)'),
    ('ALIAS_BASE', 0x100000000, 'alias svcMapMemory (tetap)'),
    ('HEAP_BASE',  0x240000000, 'heap guest (tetap)'),
]
WINDOW = 0x320000000  # 12.5 GB, rt.h GUEST_HI - GUEST_LO (tidak berubah)
CANON = 0x7000000000


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    exefs = sys.argv[1]
    mods = []
    for name in ('main', 'sdk', 'multimedia'):
        p = os.path.join(exefs, name)
        if not os.path.isfile(p):
            if name == 'main':
                sys.exit(f'tidak ada {p}')
            print(f'!! file "{name}" tidak ada di exefs'
                  + (' (rename nnSdk.nss / subsdk0 menjadi "sdk")' if name == 'sdk'
                     else ' (rename subsdk0 / multimedia.nss menjadi "multimedia") - ukuran tidak bisa dicek'))
            mods.append((name, None))
            continue
        n = Nso(p)
        mods.append((name, n))
        print(f'== {name} ==')
        print(f'  build_id : {n.build_id}')
        print(f'  image    : {n.size:>12,} B ({n.size/1048576:.1f} MB)')
        if name == 'main':
            print(f'  detail   : text {n.text[1]/1048576:.1f} / rodata {n.rodata[1]/1048576:.1f} / '
                  f'data+bss {(n.data[1]+n.bss_size)/1048576:.1f} MB -> berakhir +{n.size:#x}')
        print('  needed   :', n.needed)

    print('\n== validasi layout (offset dari GUEST_LO) ==')
    ok = True
    ends = {}
    for i, (name, off, desc) in enumerate(LAYOUT):
        n = dict(mods).get(name)
        end = (off + n.size) if n else None
        if end is not None:
            ends[name] = end
        nxt = LAYOUT[i + 1][1] if i + 1 < len(LAYOUT) else WINDOW
        status = 'OK '
        if end is not None and end > nxt:
            status = 'TABRAKAN'
            ok = False
        if off > WINDOW:
            status = 'DI LUAR WINDOW'
            ok = False
        se = f'(+{end:#x})' if end is not None else '?'
        print(f'  {name:<11} +{off:<11x} {se:<14} {status} {desc}')
    print(f'  WINDOW      +{WINDOW:x}  ({WINDOW/1048576:.0f} MB, tidak berubah)')
    if not ok:
        sys.exit('\nLayout tidak muat: geser base yang bertabrakan lalu jalankan lagi.')

    b = lambda i: CANON + LAYOUT[i][1]
    print('\n== nilai persis untuk repo ==')
    print('\n1) runtime/rt.h - cabang __ANDROID__ (offset dari GUEST_LO):')
    print(f'   #define SDK_BASE     (GUEST_LO + 0x{LAYOUT[1][1]:010x}ull)   // tadinya +0x0004000000')
    print(f'   #define MUL_BASE     (GUEST_LO + 0x{LAYOUT[2][1]:010x}ull)   // BARU (modul ketiga)')
    print(f'   #define HLE_BASE     (GUEST_LO + 0x{LAYOUT[3][1]:010x}ull)   // tadinya +0x0080000000')
    print(f'   #define TLS_BASE     (GUEST_LO + 0x{LAYOUT[4][1]:010x}ull)   // tadinya +0x0090000000')
    print(f'   #define HLE_HEAP     (GUEST_LO + 0x{LAYOUT[5][1]:010x}ull)   // tadinya +0x0092000000')
    print('\n2) runtime/rt.h - cabang desktop:')
    print(f'   #define SDK_BASE     {b(1):#x}ull   // tadinya 0x7004000000')
    print(f'   #define MUL_BASE     {b(2):#x}ull   // BARU')
    print(f'   #define HLE_BASE     {b(3):#x}ull   // tadinya 0x7080000000')
    print(f'   #define TLS_BASE     {b(4):#x}ull')
    print(f'   #define HLE_HEAP     {b(5):#x}ull')
    print('\n3) runtime/loader.c (loader_load, ~baris 253):')
    print(f'   mods[] = {{"main", MAIN_BASE}}, {{"sdk", SDK_BASE}}, {{"multimedia", MUL_BASE}}}};')
    print('\n4) runtime/dispatch.c: tables[2] -> tables[3]; semua loop "t < 2" -> "t < 3";')
    print('   dispatch_init: tambahkan tabel [2] = multimedia (pola sama dengan sdk);')
    print('   runtime/gamelib.h GameLibTables: tambah mul_addrs/mul_fns/mul_count + GAMELIB_ABI 2;')
    print('   tools/gamelib_entry.c: extern + isi multimedia_fn_addrs/ptrs/count.')
    print('\n5) android/build_gamelib.sh - baris gen.py:')
    print(f'   gen.py sdk        "$EXEFS/sdk"        {b(1):#x} "$GEN/sdk"        --hle ../runtime/hle/hle_symbols.txt --simd asm --dyn-base')
    print( '   gen.py main       "$EXEFS/main"       0x7000000000 "$GEN/main"       --simd asm --dyn-base')
    print(f'   gen.py multimedia "$EXEFS/multimedia" {b(2):#x} "$GEN/multimedia" --simd asm --dyn-base')
    print('   + cek keberadaan multimedia_table.c, + glob "multimedia/*.c" di loop heavy.txt')
    print('\n6) android/gamelib/CMakeLists.txt baris 13:')
    print('   file(GLOB GEN_SRC ${LAS_GEN}/main/*.c ${LAS_GEN}/sdk/*.c ${LAS_GEN}/multimedia/*.c)')
    print('\nLayout OK.')


if __name__ == '__main__':
    main()

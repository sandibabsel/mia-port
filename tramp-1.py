from nso import Nso
import capstone
n = Nso('../mia_exefs/main')
img = bytes(n.image)
md = capstone.Cs(capstone.CS_ARCH_ARM64, capstone.CS_MODE_ARM)
for base in (0x3a60650, 0x3a60660, 0x3a606a0, 0x3a606b0, 0x3a606c0):
    print(f'\n--- {base:#x} ---')
    for ins in md.disasm(img[base:base+0x20], base):
        print(f'{ins.address:8x}:  {ins.mnemonic:<7} {ins.op_str}')

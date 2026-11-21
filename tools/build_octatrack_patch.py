#!/usr/bin/env python3
"""Build minimal KeyStep Pro 2.5.20 firmware with only Octatrack channel banks and lower octave."""
from __future__ import annotations
import argparse, struct, subprocess, tempfile, zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE = 0x08008000
FLASH_LIMIT = 0x08080000
KSPF = ROOT / "firmware/keystep-pro_Firmware_Update_2.5.20.0.kspf"
RAW_ENTRY = "keysteppro_main__fw2_5_20_2085__2024_03_04.bin"
PRESS_CALL, RELEASE_CALL, KEY_REC_CALL = 0x08012708, 0x080126EA, 0x08015EE0
STOCK_PRESS, STOCK_RELEASE, STOCK_KEY_REC = 0x080500D8, 0x0804E700, 0x080108A4
LED_FLUSH = 0x08054C2C
LED_FLUSH_CALLS = (0x0800E328, 0x0800E84A, 0x0801696A, 0x0801F7BE, 0x0802A88C, 0x0802B876, 0x08030BD6)
ID_BUILD_IMM, ID_PATCH_IMM = 0x080181D2, 0x080181D8
VERSION_TEXT_PTR, STOCK_VERSION_TEXT = 0x080589A4, 0x0805AF3C
PATCH_VERSION, PATCH_BUILD = 99, 17


def thumb_branch(source: int, target: int) -> bytes:
    delta = target - (source + 4)
    if delta & 1 or not -(1 << 24) <= delta < (1 << 24): raise ValueError("branch out of range")
    imm=delta & 0x01ffffff; s=(imm>>24)&1; i1=(imm>>23)&1; i2=(imm>>22)&1
    j1=1^(i1^s); j2=1^(i2^s)
    return struct.pack("<HH",0xf000|(s<<10)|((imm>>12)&0x3ff),0xd000|(j1<<13)|(j2<<11)|((imm>>1)&0x7ff))


def decode_thumb_bl(source: int, code: bytes) -> int:
    h1,h2=struct.unpack_from("<HH",code)
    if h1&0xf800!=0xf000 or h2&0xd000!=0xd000: raise ValueError(f"expected BL at {source:#x}")
    s=(h1>>10)&1; j1=(h2>>13)&1; j2=(h2>>11)&1
    i1=1^(j1^s); i2=1^(j2^s)
    imm=(s<<24)|(i1<<23)|(i2<<22)|((h1&0x3ff)<<12)|((h2&0x7ff)<<1)
    if s: imm-=1<<25
    return source+4+imm


def elf_text_and_symbols(path: Path):
    data=path.read_bytes()
    shoff=struct.unpack_from("<I",data,32)[0]; entsize,num,stridx=struct.unpack_from("<HHH",data,46)
    sections=[struct.unpack_from("<IIIIIIIIII",data,shoff+i*entsize) for i in range(num)]
    names_sec=sections[stridx]; names=data[names_sec[4]:names_sec[4]+names_sec[5]]
    text=None; symbols={}
    for sec in sections:
        end=names.find(b"\0",sec[0]); name=names[sec[0]:end]
        if name==b".text": text=data[sec[4]:sec[4]+sec[5]]
        if sec[1] in (4,9) and sec[5] and name==b".rel.text": raise SystemExit("unresolved hook reference")
        if sec[1]==2:
            strings=sections[sec[6]]; string_data=data[strings[4]:strings[4]+strings[5]]
            for off in range(sec[4],sec[4]+sec[5],sec[9]):
                name_off,value,_size,_info,_other,_shndx=struct.unpack_from("<IIIBBH",data,off)
                e=string_data.find(b"\0",name_off); sym=string_data[name_off:e].decode("ascii")
                if sym: symbols[sym]=value
    if text is None: raise SystemExit("assembler output has no .text")
    return text,symbols


def build(stock: bytes):
    if len(stock)<64 or stock[:4]!=struct.pack("<I",0x02181C75): raise SystemExit("stock model header mismatch")
    if sum(stock[:64])&255 or (sum(stock[64:])+stock[9])&255: raise SystemExit("stock checksum mismatch")
    raw=stock[64:]; length=struct.unpack_from("<I",stock,4)[0]
    if length>>8!=len(raw) or len(raw)!=0x551AC: raise SystemExit("unexpected Arturia 2.5.20 image size")
    hook=(BASE+len(raw)+3)&~3
    with tempfile.TemporaryDirectory(prefix="ot-build-") as d:
        asm=Path(d)/"hooks.S"; obj=Path(d)/"hooks.o"
        asm.write_text((f".equ HOOK_IMAGE_ADDRESS,{hook:#x}\n")+(ROOT/"tools/octatrack_hooks.S").read_text())
        subprocess.run(["clang","--target=arm-none-eabi","-mcpu=cortex-m7","-mthumb","-c",str(asm),"-o",str(obj)],check=True)
        hooks,symbols=elf_text_and_symbols(obj)
    if hook+len(hooks)>FLASH_LIMIT: raise SystemExit("hook block exceeds internal flash")
    site=lambda a:raw[a-BASE:a-BASE+4]
    for call,target in ((PRESS_CALL,STOCK_PRESS),(RELEASE_CALL,STOCK_RELEASE),(KEY_REC_CALL,STOCK_KEY_REC),*((c,LED_FLUSH) for c in LED_FLUSH_CALLS)):
        if decode_thumb_bl(call,site(call))!=target: raise SystemExit(f"stock call at {call:#x} changed")
    if raw[ID_BUILD_IMM-BASE:ID_BUILD_IMM-BASE+2]!=bytes((0x25,0x23)) or raw[ID_PATCH_IMM-BASE:ID_PATCH_IMM-BASE+2]!=bytes((0x14,0x23)): raise SystemExit("identity bytes changed")
    if struct.unpack_from("<I",raw,VERSION_TEXT_PTR-BASE)[0]!=STOCK_VERSION_TEXT: raise SystemExit("version pointer changed")
    at=lambda name:(hook+symbols[name])&~1
    patched=bytearray(raw)
    calls=[(PRESS_CALL,at("pad_press")),(RELEASE_CALL,at("pad_release")),(KEY_REC_CALL,at("key_rec"))]+[(c,at("led_flush")) for c in LED_FLUSH_CALLS]
    for call,target in calls:
        patched[call-BASE:call-BASE+4]=thumb_branch(call,target)
        if decode_thumb_bl(call,patched[call-BASE:call-BASE+4])!=target: raise SystemExit("hook branch check failed")
    patched[ID_BUILD_IMM-BASE]=PATCH_BUILD; patched[ID_PATCH_IMM-BASE]=PATCH_VERSION
    patched.extend(b"\xff"*(hook-BASE-len(patched))); patched.extend(hooks)
    while len(patched)%4: patched.append(0)
    version=f"Firmware version :\nKSCON 2.5.{PATCH_VERSION} b{PATCH_BUILD}\nbased on 2.5.20"
    text_addr=BASE+len(patched); patched.extend(version.encode("ascii")+b"\0")
    while len(patched)%4: patched.append(0)
    if BASE+len(patched)>FLASH_LIMIT: raise SystemExit("firmware exceeds internal flash")
    struct.pack_into("<I",patched,VERSION_TEXT_PTR-BASE,text_addr)
    out=bytearray(stock[:64])+patched
    struct.pack_into("<I",out,4,(len(patched)<<8)|(length&255)); out[9]=-sum(out[64:])&255; out[63]=-sum(out[:63])&255
    if sum(out[:64])&255 or (sum(out[64:])+out[9])&255: raise SystemExit("patched checksum mismatch")
    return bytes(out),hook,version


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir",type=Path,default=ROOT/"firmware/patched")
    args=parser.parse_args()
    with zipfile.ZipFile(KSPF) as z: stock=z.read(RAW_ENTRY); entries=[(i,z.read(i.filename)) for i in z.infolist()]
    out,hook,version=build(stock); args.output_dir.mkdir(parents=True,exist_ok=True)
    dest=args.output_dir/f"KSCON_2.5.{PATCH_VERSION}_build{PATCH_BUILD}.kspf"
    with zipfile.ZipFile(dest,"w") as z:
        for info,data in entries:
            if info.filename=="info.json": data=data.replace(b'"version_number": "2.5.20"',f'"version_number": "2.5.{PATCH_VERSION}"'.encode())
            z.writestr(info,out if info.filename==RAW_ENTRY else data)
    with zipfile.ZipFile(dest) as z:
        if z.testzip() is not None or z.read(RAW_ENTRY)!=out: raise SystemExit("package check failed")
    print(f"Built minimal {version!r}: {dest}; only Octatrack mode hooks included at {hook:#x}.")

if __name__=="__main__": main()

#!/usr/bin/env python3
"""Convert little-endian RV32 load segments to a complete 128 KiB RAM image."""
import argparse
from pathlib import Path
import struct

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("elf", type=Path)
parser.add_argument("output", type=Path)
args = parser.parse_args()
data = args.elf.read_bytes()
if len(data) < 52 or data[:6] != b"\x7fELF\x01\x01":
    parser.error("expected a little-endian ELF32 file")
u16 = lambda offset: struct.unpack_from("<H", data, offset)[0]
u32 = lambda offset: struct.unpack_from("<I", data, offset)[0]
if u16(18) != 243 or u32(24) != 0x80000000 or u32(36) & 1:
    parser.error("expected an uncompressed RISC-V image with entry 0x80000000")
image = bytearray(128 * 1024)
table, size, count = u32(28), u16(42), u16(44)
if size < 32 or table + size * count > len(data):
    parser.error("invalid program header table")
for index in range(count):
    entry = table + index * size
    if u32(entry) != 1:
        continue
    offset, address = u32(entry + 4), u32(entry + 12)
    file_size, memory_size = u32(entry + 16), u32(entry + 20)
    start = address - 0x80000000
    if start < 0 or start + memory_size > len(image) or file_size > memory_size or offset + file_size > len(data):
        parser.error("invalid load segment or image exceeds 128 KiB")
    image[start:start + file_size] = data[offset:offset + file_size]
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text("".join(f"{word[0]:08x}\n" for word in struct.iter_unpack("<I", image)))

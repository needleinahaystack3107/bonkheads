"""Minimal, read-only PE32 resource reader.

Only parses bytes; it never loads or executes the image. Enough to walk the
resource directory (type -> name -> language) and pull payloads out, which is
all the Bonkheads analysis needs. Cross-checked against REA's
inspect_pe_resources (see docs/findings.md, "Resource inventory").
"""
from __future__ import annotations

import struct
from dataclasses import dataclass
from pathlib import Path

# Standard Win32 resource type IDs we care about, for readable output.
RT_NAMES = {1: "CURSOR", 2: "BITMAP", 3: "ICON", 4: "MENU", 5: "DIALOG",
            6: "STRING", 10: "RCDATA", 14: "GROUP_ICON", 16: "VERSION"}


@dataclass(frozen=True)
class Section:
    name: str
    vaddr: int
    vsize: int
    raw_ptr: int
    raw_size: int


@dataclass(frozen=True)
class Resource:
    type: int | str   # numeric ID or custom name like "BKMP"
    name: int | str
    lang: int
    data: bytes

    @property
    def type_label(self) -> str:
        return RT_NAMES.get(self.type, str(self.type)) if isinstance(self.type, int) else self.type


class PEImage:
    def __init__(self, path: str | Path):
        self.path = Path(path)
        self.raw = self.path.read_bytes()
        pe = struct.unpack_from("<I", self.raw, 0x3C)[0]
        if self.raw[pe:pe + 4] != b"PE\0\0":
            raise ValueError(f"{path}: not a PE image")
        _, nsect, _, _, _, opt_size, _ = struct.unpack_from("<HHIIIHH", self.raw, pe + 4)
        opt = pe + 24
        if struct.unpack_from("<H", self.raw, opt)[0] != 0x10B:
            raise ValueError("only PE32 is supported")
        self.image_base = struct.unpack_from("<I", self.raw, opt + 28)[0]
        # Data directory 2 is the resource table.
        self.rsrc_rva, self.rsrc_size = struct.unpack_from("<II", self.raw, opt + 96 + 2 * 8)
        self.sections = []
        for i in range(nsect):
            off = opt + opt_size + i * 40
            name = self.raw[off:off + 8].rstrip(b"\0").decode("latin-1")
            vsize, vaddr, rsize, rptr = struct.unpack_from("<IIII", self.raw, off + 8)
            self.sections.append(Section(name, vaddr, vsize, rptr, rsize))

    # -- address helpers -------------------------------------------------
    def rva_to_offset(self, rva: int) -> int:
        for s in self.sections:
            if s.vaddr <= rva < s.vaddr + max(s.vsize, s.raw_size):
                return rva - s.vaddr + s.raw_ptr
        raise ValueError(f"RVA {rva:#x} not in any section")

    def va_to_offset(self, va: int) -> int:
        return self.rva_to_offset(va - self.image_base)

    def read_va(self, va: int, size: int) -> bytes:
        off = self.va_to_offset(va)
        return self.raw[off:off + size]

    # -- resources -------------------------------------------------------
    def resources(self) -> list[Resource]:
        if not self.rsrc_rva:
            return []
        base = self.rva_to_offset(self.rsrc_rva)
        out: list[Resource] = []
        for type_key, type_dir in self._entries(base, base):
            for name_key, name_dir in self._entries(base, base + type_dir):
                for lang, leaf in self._entries(base, base + name_dir):
                    rva, size = struct.unpack_from("<II", self.raw, base + leaf)
                    off = self.rva_to_offset(rva)
                    out.append(Resource(type_key, name_key, lang, self.raw[off:off + size]))
        return out

    def resource(self, rtype: int | str, name: int | str) -> bytes:
        for r in self.resources():
            if r.type == rtype and r.name == name:
                return r.data
        raise KeyError((rtype, name))

    def resources_of(self, rtype: int | str) -> dict[int | str, bytes]:
        return {r.name: r.data for r in self.resources() if r.type == rtype}

    def _entries(self, base: int, dir_off: int):
        """Yield (key, child_offset_relative_to_base) for one directory table."""
        n_named, n_id = struct.unpack_from("<HH", self.raw, dir_off + 12)
        for i in range(n_named + n_id):
            key_raw, child = struct.unpack_from("<II", self.raw, dir_off + 16 + i * 8)
            if key_raw & 0x80000000:  # name string: u16 length + UTF-16LE
                p = base + (key_raw & 0x7FFFFFFF)
                ln = struct.unpack_from("<H", self.raw, p)[0]
                key: int | str = self.raw[p + 2:p + 2 + ln * 2].decode("utf-16le")
            else:
                key = key_raw
            yield key, child & 0x7FFFFFFF


def string_table(img: PEImage) -> dict[int, str]:
    """Decode RT_STRING blocks: block N holds string IDs (N-1)*16 .. +15."""
    out = {}
    for block, data in img.resources_of(6).items():
        p = 0
        for i in range(16):
            ln = struct.unpack_from("<H", data, p)[0]
            p += 2
            if ln:
                out[(block - 1) * 16 + i] = data[p:p + ln * 2].decode("utf-16le")
            p += ln * 2
    return out

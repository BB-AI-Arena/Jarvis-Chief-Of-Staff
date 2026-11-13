"""Signing metadata normalization must never hide a code/data change."""
import importlib.util
from pathlib import Path
import struct
s=importlib.util.spec_from_file_location('audit',Path(__file__).with_name('check_installed_build.py'))
a=importlib.util.module_from_spec(s);s.loader.exec_module(a)
raw=bytearray(1024)
struct.pack_into('<IIIIIIII',raw,0,0xfeedfacf,0x100000c,0,2,1,72,0,0)
struct.pack_into('<II16sQQQQIIII',raw,32,0x19,72,b'__LINKEDIT',0,16384,512,512,1,1,0,0)
other=bytearray(raw);struct.pack_into('<Q',other,64,32768)
assert a.canonical_unsigned_bytes(raw)==a.canonical_unsigned_bytes(other)
other[300]=1
assert a.canonical_unsigned_bytes(raw)!=a.canonical_unsigned_bytes(other)
struct.pack_into('<Q',other,80,511)
try:a.canonical_unsigned_bytes(other)
except AssertionError:pass
else:raise AssertionError('Malformed extent accepted')
root=Path(__file__).resolve().parents[1]
assert a.unsigned_sha(root/'dist/Jarvis.app/Contents/MacOS/Jarvis')==a.unsigned_sha(root/'.build/release/Jarvis')
print('PASS: signing-only VM padding normalized; changed bytes and malformed extents remain detectable; actual package matches release')

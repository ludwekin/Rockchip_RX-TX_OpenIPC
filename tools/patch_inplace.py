#!/usr/bin/env python3
"""Replace the fdt payload inside the ORIGINAL boot.img FIT, keeping every
data-position / data-size identical. New DTB must be <= original fdt size.
Recomputes the fdt sha256 hash in place.

usage: patch_inplace.py <orig_boot.img> <new.dtb> <out.itb>
"""
import struct, sys, hashlib

SRC, DTB, OUT = sys.argv[1], sys.argv[2], sys.argv[3]
FDT_BEGIN_NODE, FDT_END_NODE, FDT_PROP, FDT_NOP, FDT_END = 1, 2, 3, 4, 9

d = bytearray(open(SRC, 'rb').read())
magic, totalsize, off_struct, off_strings, off_rsvmap = struct.unpack('>IIIII', d[:20])
assert magic == 0xd00dfeed

def align4(x): return (x + 3) & ~3

pos = off_struct
stack = []
props = {}      # (node_path, prop_name) -> (offset, length)
cur_img = None
while True:
    tok, = struct.unpack('>I', d[pos:pos+4])
    pos += 4
    if tok == FDT_BEGIN_NODE:
        end = d.index(b'\0', pos)
        stack.append(d[pos:end].decode())
        pos = align4(end + 1)
    elif tok == FDT_END_NODE:
        stack.pop()
    elif tok == FDT_PROP:
        ln, nameoff = struct.unpack('>II', d[pos:pos+8])
        pos += 8
        nend = d.index(b'\0', off_strings + nameoff)
        pname = d[off_strings + nameoff:nend].decode()
        props[('/'.join(stack), pname)] = (pos, ln)
        pos = align4(pos + ln)
    elif tok == FDT_NOP:
        continue
    elif tok == FDT_END:
        break
    else:
        raise SystemExit('bad token')

def get(path, name):
    key = (path, name)
    if key not in props:
        raise SystemExit('missing %s %s' % (path, name))
    off, ln = props[key]
    return off, ln

fp, fl = get('/images/fdt', 'data-position')
fdt_pos = struct.unpack('>I', d[fp:fp+4])[0]
sp, sl = get('/images/fdt', 'data-size')
fdt_size = struct.unpack('>I', d[sp:sp+4])[0]
hp, hl = get('/images/fdt/hash', 'value')
assert hl == 32

new = open(DTB, 'rb').read()
print('fdt slot: pos=%#x size=%d ; new dtb=%d' % (fdt_pos, fdt_size, len(new)))
if len(new) > fdt_size:
    raise SystemExit('new DTB larger than original slot (%d > %d)' % (len(new), fdt_size))

payload = new + b'\0' * (fdt_size - len(new))
d[fdt_pos:fdt_pos+fdt_size] = payload
newhash = hashlib.sha256(payload).digest()
d[hp:hp+32] = newhash

open(OUT, 'wb').write(d)
print('hash', newhash.hex()[:32], '-> wrote', OUT, len(d))

#!/usr/bin/python3
"""List the enabled users of the RPMh power domains and of the interconnect that no driver of a kernel matches.

Until every enabled user of such a provider has its driver bound, the provider never reaches sync_state and Linux
keeps its boot-time maximum votes on every rail and bus it touched, sleep votes included. Fedora's kernel neither
forces nor reports that (DRIVER_DEFERRED_PROBE_TIMEOUT=-1), and under the held rail votes the Surface Pro 11's CDSP
never wakes from its first sleep. Step 20 runs this on the built packages.

Usage: sync-state-drivers.py DTB VMLINUZ ALIAS_FILE...
  DTB         the device tree the machine boots with
  VMLINUZ     the kernel's EFI zboot image: a built-in driver may record no module alias, so the compatible strings
              of built-in drivers are searched in the decompressed kernel image
  ALIAS_FILE  modules.alias (from depmod) and modules.builtin.modinfo
Prints one line per user without a driver (node, compatibles, providers) and exits 1 if there is one.
"""
import re
import struct
import subprocess
import sys

dtb = open(sys.argv[1], 'rb').read()
zboot = open(sys.argv[2], 'rb').read()
if zboot[:2] != b'MZ' or zboot[4:8] != b'zimg':
    sys.exit(f'{sys.argv[2]}: not an EFI zboot image')
zoff, zsize = struct.unpack_from('<II', zboot, 8)
tool = {b'zstd': ['zstd', '-dc'], b'gzip': ['gzip', '-dc']}[zboot[24:32].split(b'\0')[0]]
image = subprocess.run(tool, input=zboot[zoff:zoff + zsize], capture_output=True, check=True).stdout

# The flattened device tree: tokens BEGIN_NODE (1, name), END_NODE (2), PROP (3, length, name offset, value),
# NOP (4), END (9), each padded to 4 bytes.
magic, _, off_struct, off_strings = struct.unpack_from('>IIII', dtb)
if magic != 0xd00dfeed:
    sys.exit(f'{sys.argv[1]}: not a DTB')
nodes, stack, pos = {}, [], off_struct
while True:
    token, = struct.unpack_from('>I', dtb, pos)
    pos += 4
    if token == 1:
        end = dtb.index(b'\0', pos)
        stack.append(dtb[pos:end].decode())
        nodes['/' + '/'.join(stack[1:])] = {}
        pos = (end + 4) & ~3
    elif token == 2:
        stack.pop()
    elif token == 3:
        length, nameoff = struct.unpack_from('>II', dtb, pos)
        pos += 8
        name = dtb[off_strings + nameoff:dtb.index(b'\0', off_strings + nameoff)].decode()
        nodes['/' + '/'.join(stack[1:])][name] = dtb[pos:pos + length]
        pos = (pos + length + 3) & ~3
    elif token == 9:
        break
    elif token != 4:
        sys.exit(f'{sys.argv[1]}: bad token {token}')


def u32s(value):
    return list(struct.unpack(f'>{len(value) // 4}I', value))


def strings(value):
    return [s.decode() for s in value.split(b'\0') if s]


phandles = {u32s(props['phandle'])[0]: path for path, props in nodes.items() if 'phandle' in props}


def enabled(path):
    parts = path.split('/')
    return all(strings(nodes['/' + '/'.join(parts[1:i])].get('status', b'okay'))[0] in ('okay', 'ok')
               for i in range(2, len(parts) + 1))


def targets(value, cells):
    """The nodes a phandle-with-arguments list points at; each provider's #cells gives its argument count."""
    out, cellv = [], u32s(value)
    while cellv:
        target = phandles[cellv[0]]
        out.append(target)
        cellv = cellv[1 + u32s(nodes[target][cells])[0]:]
    return out


def provider(path):
    props = nodes[path]
    return '#interconnect-cells' in props or any(c.endswith('-rpmhpd') for c in strings(props.get('compatible', b'')))


aliases = set()
for name in sys.argv[3:]:
    text = open(name, errors='replace').read()
    aliases.update(re.findall(r'of:N[^T\s\0]*T[^C\s\0]*C([^\s\0]*?)(?:C\*)?(?=[\s\0]|$)', text))

missing = 0
for path, props in sorted(nodes.items()):
    if path.startswith('/cpus/') or not enabled(path):
        continue
    used = sorted({t for prop, cells in (('power-domains', '#power-domain-cells'),
                                         ('interconnects', '#interconnect-cells'))
                   if prop in props for t in targets(props[prop], cells) if provider(t)})
    compatibles = strings(props.get('compatible', b''))
    if used and not (set(compatibles) & aliases or any(c.encode() + b'\0' in image for c in compatibles)):
        print(f"{path} ({', '.join(compatibles)}) -> {', '.join(used)}")
        missing += 1
sys.exit(1 if missing else 0)

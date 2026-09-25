#!/usr/bin/python3
# Ask a DSP's QMI test service for a ping over QRTR. Any reply shows the DSP is awake and answering; a DSP that
# cannot wake up answers nothing. Usage: python3 sp11-dsp-ping.py [node] [port]
#   CDSP: node 10, port 1 (the default); ADSP: node 5, port 1 (`qrtr-lookup`: service 15 "Test service").
# The request is the kernel's samples/qmi test ping: message 0x20 with the 4-byte "ping" in TLV 0x01.
import socket
import struct
import sys
import time

node = int(sys.argv[1]) if len(sys.argv) > 1 else 10
port = int(sys.argv[2]) if len(sys.argv) > 2 else 1
QMI_REQUEST, PING_MSG_ID, TXN = 0, 0x20, 1

tlv = struct.pack('<BH4s', 0x01, 4, b'ping')
request = struct.pack('<BHHH', QMI_REQUEST, TXN, PING_MSG_ID, len(tlv)) + tlv

try:
    sock = socket.socket(getattr(socket, 'AF_QIPCRTR', 42), socket.SOCK_DGRAM)
    sock.settimeout(3)
    start = time.monotonic()
    sock.sendto(request, (node, port))
    reply, sender = sock.recvfrom(4096)
except socket.timeout:
    print(f'node {node} port {port}: no answer within 3 s')
    sys.exit(1)
except OSError as err:
    print(f'node {node} port {port}: {err}')
    sys.exit(2)

msg_type, txn, msg_id, length = struct.unpack_from('<BHHH', reply)
result = ''
offset = 7
while offset + 3 <= len(reply):                     # TLVs: type (1), length (2), value
    t, n = struct.unpack_from('<BH', reply, offset)
    value = reply[offset + 3:offset + 3 + n]
    if t == 0x02 and n >= 4:
        res, err = struct.unpack_from('<HH', value)
        result += f' result {res} error {err}'
    elif t == 0x10:
        result += f' pong {value!r}'
    offset += 3 + n
print(f'node {node} port {port}: answered in {(time.monotonic() - start) * 1000:.0f} ms '
      f'(type {msg_type}, message 0x{msg_id:02x}{result})')

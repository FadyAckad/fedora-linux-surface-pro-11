#!/usr/bin/python3
# Fake media-ctl / v4l2-ctl for testing sp11-camera-probe on the host (run it through probe-fake.sh, which links both
# names to this file). State in $FAKE_STATE (JSON), the calls in $FAKE_STATE.log. Sensors, controls and entity names
# as on the tested unit with kernel revision 8; a frame is uniform: the scene's level per channel, no noise.
# FAKE_FRONT: rev7 (driver writes 0x0340, ignored: the sensor keeps 3554 lines of 9.378 us and stretches the frame
#             for a longer exposure), rev8 (the sensor takes the frame length), rev8-ignored (rev 8's ranges, frame
#             length ignored as on rev 7). FAKE_GAIN_STOP: none | 15.5 (rear). FAKE_SCENE: DN per ms at 1x (green).
import json
import os
import sys

state_path = os.environ['FAKE_STATE']
FRONT = os.environ.get('FAKE_FRONT', 'rev8')
GAIN_STOP = os.environ.get('FAKE_GAIN_STOP', 'none')
SCENE = float(os.environ.get('FAKE_SCENE', '1.4'))
LINE_US_FRONT = 6752 / 720.0          # the IMX681's true line
if FRONT == 'rev7':
    front_ctrls = {'exposure': [8, 2660, 1600, 1600], 'analogue_gain': [0, 960, 0, 0],
                   'digital_gain': [256, 4095, 256, 256], 'vertical_blanking': [48, 65535 - 2640, 68, 68]}
    front_margin = 48
else:
    front_ctrls = {'exposure': [8, 3546, 1600, 1600], 'analogue_gain': [0, 960, 0, 0],
                   'digital_gain': [256, 4095, 256, 256], 'vertical_blanking': [914, 65535 - 2640, 914, 914]}
    front_margin = 8
SENS = {
    'imx681': dict(w=3840, h=2640, stride=4800, order='RGGB', margin=front_margin, ctrls=front_ctrls,
                   gain=lambda c: 1024 / (1024 - c), subdev='/dev/v4l-subdev11', entity='imx681 7-001a'),
    'ov13858': dict(w=2112, h=1188, stride=2640, order='GRBG', margin=8,
                    ctrls={'exposure': [4, 3206, 3206, 3206], 'analogue_gain': [0, 8191, 128, 128],
                           'digital_gain': [0, 16383, 1024, 1024], 'vertical_blanking': [26, 32767 - 1188, 2026, 2026]},
                    gain=lambda c: c / 128, subdev='/dev/v4l-subdev7', entity='ov13858 5-0010'),
}


def load():
    if os.path.exists(state_path):
        return json.load(open(state_path))
    return {'active': None, 'ctrls': {k: {n: list(v) for n, v in s['ctrls'].items()} for k, s in SENS.items()}}


def save(st):
    json.dump(st, open(state_path, 'w'))


def log(msg):
    with open(state_path + '.log', 'a') as f:
        f.write(msg + '\n')


st = load()
tool = os.path.basename(sys.argv[0])
args = sys.argv[1:]
log(tool + ' ' + ' '.join(args))
if tool == 'media-ctl':
    if '-p' in args:
        print('Media controller API version 7.2.7\n\nMedia device information\n------------------------\n'
              'driver          qcom-camss\nmodel           Qualcomm Camera Subsystem\n')
        print('- entity 400: ov13858 5-0010 (1 pad, 1 link, 0 routes)\n- entity 423: imx681 7-001a (1 pad, 1 link, 0 routes)')
    elif '-l' in args:
        link = args[args.index('-l') + 1]
        if 'msm_csiphy2' in link:
            st['active'] = 'imx681'
        elif 'msm_csiphy1' in link:
            st['active'] = 'ov13858'
    elif '-e' in args:
        e = args[args.index('-e') + 1]
        for k, s in SENS.items():
            if s['entity'] == e:
                print(s['subdev'])
        if e == 'msm_vfe0_video0':
            print('/dev/video0')
    save(st)
    sys.exit(0)

dev = args[args.index('-d') + 1]
sk = next((k for k, s in SENS.items() if s['subdev'] == dev), None)
if sk:
    s, c = SENS[sk], st['ctrls'][sk]
    for a in args:
        if a == '--list-ctrls':
            ids = {'exposure': '0x00980911', 'analogue_gain': '0x009e0903', 'digital_gain': '0x009f0905',
                   'vertical_blanking': '0x009e0901'}
            for n, (mn, mx, df, v) in c.items():
                print(f'{n:>35} {ids[n]} (int)    : min={mn} max={mx} step=1 default={df} value={v}')
        elif a.startswith('--set-ctrl='):
            for kv in a.split('=', 1)[1].split(','):
                n, v = kv.split('=')
                v = int(v)
                if v < c[n][0] or v > c[n][1]:
                    print(f'{n}: value {v} out of range', file=sys.stderr)
                    save(st)
                    sys.exit(1)
                c[n][3] = v
                if n == 'vertical_blanking':
                    emax = s['h'] + v - s['margin']
                    c['exposure'][1] = emax
                    c['exposure'][2] = min(SENS[sk]['ctrls']['exposure'][2], emax)
                    c['exposure'][3] = min(c['exposure'][3], emax)
    save(st)
    sys.exit(0)

sk = st['active']
s, c = SENS[sk], st['ctrls'][sk]
if any(a.startswith('--set-fmt-video') for a in args):
    print(f"Format Video Capture:\n\tWidth/Height      : {s['w']}/{s['h']}\n\tBytes per Line    : {s['stride']}\n"
          f"\tSize Image        : {s['stride'] * s['h']}")
    sys.exit(0)
count = int(next(a for a in args if a.startswith('--stream-count=')).split('=')[1])
to = next((a.split('=', 1)[1] for a in args if a.startswith('--stream-to=')), None)
vb, exp, gc = c['vertical_blanking'][3], c['exposure'][3], c['analogue_gain'][3]
fll = s['h'] + vb
if sk == 'imx681':
    line_us = LINE_US_FRONT
    frame = fll if FRONT == 'rev8' else 3554          # the frame length the sensor uses
    frame = max(frame, exp + 8)                       # stretched for a longer exposure
    fps = 1e6 / (frame * line_us)
else:
    line_us = 1e6 / (30 * 3214)
    fps = 1e6 / (max(fll, exp + 8) * line_us)
g = s['gain'](gc)
if sk == 'ov13858' and GAIN_STOP != 'none':
    g = min(g, float(GAIN_STOP))
t_ms = exp * line_us / 1000
G = SCENE * t_ms * g
lv = lambda k: max(0, min(1023, int(round(64 + k * G))))
R, Gv, B = lv(0.55), lv(1.0), lv(0.85)
if to:
    def row(a, b):
        grp = bytes([a >> 2, b >> 2, a >> 2, b >> 2, ((a & 3) | (b & 3) << 2 | (a & 3) << 4 | (b & 3) << 6)])
        r = grp * (s['w'] // 4)
        return r + bytes(s['stride'] - len(r))
    r0, r1 = (row(R, Gv), row(Gv, B)) if s['order'] == 'RGGB' else (row(Gv, R), row(B, Gv))
    data = (r0 + r1) * (s['h'] // 2)
    with open(to, 'wb') as f:
        for _ in range(count):
            f.write(data)
print(f'<<<<<<<<<<<<<<<<<<<<<<<<<<<<< {fps:.2f} fps, dropped buffers: 0')
log(f'  stream {sk}: vb={vb} fll={fll} exp={exp} gain={g:.2f} t={t_ms:.2f}ms G={Gv} fps={fps:.2f}')

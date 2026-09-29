#!/usr/bin/python3
"""Model of the software ISP's exposure control on synthetic scenes: how long it takes to settle and whether it
oscillates, for a tuning file's Agc values. The control law is a line-by-line port of Agc::updateExposure() and of
the MSV computation in Agc::process() (src/ipa/simple/algorithms/agc.cpp of libcamera 0.7.2 with payload/camera/
0004, 0005 and 0008), and of the gain code the IPA sets (0009: the nearest code); keep it in step with those
patches.

Usage: agc-model.py [--sensor imx681|ov13858] [--target 1.4] [--dgain-max 4] [--again-max 15.5] [--seeds 5]
                    [--lux L ...] [--contrast C ...] [--gain-codes nearest|truncate|exact]

Not a picture simulation. A scene is a log-normal spread of pixel brightness around a mean given in the light
sensor's lux, and a pixel's raw signal is about 0.5 steps (of 959 above the 10-bit black level) per lux at full
exposure (33 ms) and 1x, as sp11-camera-probe measured on the front camera of the tested unit; read and shot noise
are rough. Statistics run every fourth frame at 30 fps and the sensor delays (2 frames) are shorter than that, so
one statistics period sees the controls the previous one set. Compare variants of the algorithm or of a tuning
value against each other; the absolute times are indicative.
"""
import argparse
import math
import random

BINS = 5
OPTIMAL = BINS / 2.0
SATISFACTORY, PROP_GAIN, MAX_STEP, LARGE_ERROR, MAX_JUMP = 0.2, 0.04, 0.15, 0.5, 2.0
HIST_SIZE, BLACK8 = 64, 16                      # SwIspStats::kYHistogramSize; black level 64/1023 = 16/255
FPS, STATS_EVERY = 30.0, 4
SENSORS = {
    # exposure lines (min, max at 30 fps with kernel revision 8), analogue gain range and the IPA's minimum step
    # ((max - min) / 100), the driver's default exposure and gain the stream starts from, and the sensor's gain
    # codes (the helper's gainCode() before truncation, the gain of a code, the highest code): the IPA sets a code
    # and reads that code's gain back for the next frame. The top of the range is the highest code's gain exactly,
    # as in the IPA, or the gain read back never reaches it. The OV13858's stop at 15.5x is not simulated: run the
    # rear camera with --again-max 15.5, its tuning.
    'imx681': dict(exp=(8, 3546), again=(1.0, 16.0), start=(1600, 1.0),
                   code=lambda g: 1024 - 1024 / g, gain=lambda c: 1024.0 / (1024 - c), cmax=960),
    'ov13858': dict(exp=(4, 3206), again=(0.0, 8191 / 128.0), start=(3206, 1.0),
                    code=lambda g: 128 * g, gain=lambda c: c / 128.0, cmax=8191),
}


def applied_gain(s, g, mode):
    """The gain the sensor applies for a requested one: IPASoftSimple::gainCode() since 0009 ('nearest'), the
    helper's truncated code before it ('truncate'), or no quantisation at all ('exact')."""
    if mode == 'exact':
        return g
    c = min(int(s['code'](g)), s['cmax'])
    if mode == 'nearest' and c < s['cmax'] and s['gain'](c + 1) - g < g - s['gain'](c):
        c += 1
    return s['gain'](c)
DN_PER_LUX = 0.5                                 # raw steps per lux at full exposure and 1x


class Agc:
    def __init__(self, sensor, target, dgain_max, again_max, gain_codes='nearest'):
        s = SENSORS[sensor]
        self.exp_min, self.exp_max = s['exp']
        self.again_min, self.again_max = s['again']
        self.again_step = (self.again_max - self.again_min) / 100.0
        if again_max is not None and again_max < self.again_max:          # 0005: maxAnalogueGain
            limit = max(again_max, self.again_min)
            self.again_step *= (limit - self.again_min) / (self.again_max - self.again_min)
            self.again_max = limit
        self.again10 = max(self.again_min, 1.0)
        self.target, self.dgain_max = target, dgain_max
        self.exposure, self.again = s['start']
        self.dgain = 1.0
        self.applied = lambda g: applied_gain(s, g, gain_codes)

    def msv(self, hist):
        """Agc::process(): the 64-bin histogram above the black level in five bins, scaled by the digital gain."""
        black_idx = BLACK8 // (256 // HIST_SIZE)
        size = HIST_SIZE - black_idx
        per_bin, per_bin_mod = size // BINS, size // (size % BINS + 1)
        bins = [0] * BINS
        for i in range(size):
            scaled = min(int(i * self.dgain), size - 1)
            bins[(scaled - scaled // per_bin_mod) // per_bin] += hist[black_idx + i]
        denom = sum(bins)
        return sum(b * (i + 1) for i, b in enumerate(bins)) / denom if denom else 0.0

    def update(self, msv):
        """Agc::updateExposure() with 0004 (jumps, digital gain) and 0008 (target, scaled thresholds)."""
        error = self.target - msv
        scale = self.target / OPTIMAL
        if abs(error) <= SATISFACTORY * scale:
            return False
        if abs(error) > LARGE_ERROR * scale:
            ratio = self.target / max(msv, 0.1)
            if ratio > 1.0:
                ratio *= ratio
            factor = min(max(ratio, 1.0 / MAX_JUMP), MAX_JUMP)
        else:
            factor = 1.0 + min(max(error / scale * PROP_GAIN, -MAX_STEP), MAX_STEP)
        if factor > 1.0:
            if self.exposure < self.exp_max:
                self.exposure = max(int(self.exposure * factor), self.exposure + 1)
            elif self.again < self.again_max:
                nxt = self.again * factor
                self.again = self.again + self.again_step if nxt - self.again < self.again_step else nxt
            else:
                self.dgain = min(self.dgain * factor, self.dgain_max)
        else:
            if self.dgain > 1.0:
                self.dgain = max(self.dgain * factor, 1.0)
            elif self.again > self.again10:
                nxt = self.again * factor
                self.again = self.again - self.again_step if self.again - nxt < self.again_step else nxt
            else:
                self.exposure = min(int(self.exposure * factor), self.exposure - 1)
        self.exposure = min(max(self.exposure, self.exp_min), self.exp_max)
        self.again = self.applied(min(max(self.again, self.again_min), self.again_max))
        self.dgain = min(max(self.dgain, 1.0), self.dgain_max)
        return True


def histogram(agc, pixels, rng):
    """The statistics' luminance histogram of one frame: raw signal per pixel, noise, the 8-bit high byte."""
    hist = [0] * HIST_SIZE
    t = agc.exposure / agc.exp_max
    g = max(agc.again, 0.01)
    for lux in pixels:
        signal = lux * DN_PER_LUX * t * g
        noise = math.sqrt((0.8 * g) ** 2 + max(signal, 0.0) * g * 0.05)
        raw = min(max(64 + signal + rng.gauss(0.0, noise), 0.0), 1023.0)
        hist[min(int(raw) >> 2, 255) * HIST_SIZE // 256] += 1
    return hist


def run(args, lux, contrast, seed, periods=150):
    rng = random.Random(seed)
    pixels = [lux * math.exp(contrast * rng.gauss(0.0, 1.0) - contrast * contrast / 2) for _ in range(4000)]
    agc = Agc(args.sensor, args.target, args.dgain_max, args.again_max, args.gain_codes)
    msvs, reached, later = [], None, 0
    for n in range(periods):
        m = agc.msv(histogram(agc, pixels, rng))
        msvs.append(m)
        changed = agc.update(m)
        if reached is None and not changed:
            reached = n * STATS_EVERY / FPS            # the first statistics period inside the satisfactory band
        elif reached is not None and changed:
            later += 1
    tail = msvs[-20:]
    return dict(reached=reached, later=later, msv=sum(tail) / len(tail),
                wobble=(max(tail) - min(tail)) / max(sum(tail) / len(tail), 1e-9),
                exp=agc.exposure, again=agc.again, dgain=agc.dgain)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--sensor', choices=sorted(SENSORS), default='imx681')
    ap.add_argument('--target', type=float, default=1.4, help='Agc exposureTarget (default 1.4)')
    ap.add_argument('--dgain-max', type=float, default=4.0, help='Agc maxDigitalGain (default 4)')
    ap.add_argument('--again-max', type=float, default=None, help='Agc maxAnalogueGain (the OV13858 tuning: 15.5)')
    ap.add_argument('--seeds', type=int, default=5)
    ap.add_argument('--lux', type=float, nargs='*', help='scenes to run instead of the standard four')
    ap.add_argument('--contrast', type=float, nargs='*',
                    help='spreads instead of 0.3, 0.7 and 1.0 (0.1 or less: a flat scene, like a blank wall)')
    ap.add_argument('--gain-codes', choices=('nearest', 'truncate', 'exact'), default='nearest',
                    help='the gain code the IPA sets: nearest (0009, default), truncate (before 0009), exact')
    args = ap.parse_args()
    print(f'{args.sensor}: target {args.target}, maxDigitalGain {args.dgain_max}, maxAnalogueGain {args.again_max}, '
          f'gain codes {args.gain_codes}')
    # reached: the slowest seed's time to the satisfactory band ('never': at the limits, too dark for the target, or
    # jumping across the band, as flat scenes do); later: corrections after that in 20 s (noise at the band's edge);
    # wobble: the MSV's spread over the last 2.7 s.
    print(f'{"scene":>16} {"contrast":>8} {"reached":>8} {"later":>6} {"MSV":>5} {"wobble":>7}   exposure / gain / digital')
    scenes = [(f'{x:g} lux', x) for x in args.lux] if args.lux else \
        [('dark spot 1 lux', 1), ('dim 10 lux', 10), ('room 100 lux', 100), ('daylight 2000', 2000)]
    for name, lux in scenes:
        for contrast in args.contrast or (0.3, 0.7, 1.0):
            rs = [run(args, lux, contrast, seed) for seed in range(args.seeds)]
            got = [r['reached'] for r in rs if r['reached'] is not None]
            st = f'{max(got):.1f} s' if len(got) == len(rs) else 'never'
            r = rs[0]
            print(f'{name:>16} {contrast:>8} {st:>8} {max(x["later"] for x in rs):>6} '
                  f'{sum(x["msv"] for x in rs) / len(rs):5.2f} {max(x["wobble"] for x in rs):7.1%}   '
                  f'{r["exp"]} / {r["again"]:.2f} / {r["dgain"]:.2f}')


if __name__ == '__main__':
    main()

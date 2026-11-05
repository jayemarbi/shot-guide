"""An original 133 BPM backing track for the concept reel (a stand-in for the real song).

Built on the same beat grid as the edit: hook (beats 0-8), groove (8-16), build (16-24),
drop (24-40), breakdown (40-44), freeze and tail (44-48.75). Writes out/music.wav.
"""
import os
import numpy as np
from scipy.signal import butter, sosfilt, fftconvolve
import wave

SR = 48000
BPM = 133
SPB = 60 / BPM
END_BEAT = 48.75
DUR = END_BEAT * SPB
N = int(DUR * SR) + 1
rng = np.random.default_rng(7)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'out')


def T(beat):
    return int(round(beat * SPB * SR))


def bus():
    return np.zeros((2, N))


def add(b, sig, beat, gain=1.0, pan=0.0):
    i = T(beat)
    if i >= N:
        return
    if sig.ndim == 1:
        l, r = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
        sig = np.vstack([sig * l * 1.414, sig * r * 1.414])
    n = min(sig.shape[1], N - i)
    b[:, i:i + n] += sig[:, :n] * gain


def note(n):
    names = {'C': 0, 'Db': 1, 'D': 2, 'Eb': 3, 'E': 4, 'F': 5, 'Gb': 6, 'G': 7, 'Ab': 8, 'A': 9, 'Bb': 10, 'B': 11}
    name, octave = n[:-1], int(n[-1])
    return 440.0 * 2 ** ((names[name] + 12 * (octave + 1) - 69) / 12)


def saw(freq, n, phase0=0.0):
    f = np.full(n, freq) if np.isscalar(freq) else freq
    dt = f / SR
    ph = (phase0 + np.cumsum(dt)) % 1.0
    y = 2 * ph - 1
    m1 = ph < dt
    t1 = ph[m1] / dt[m1]
    y[m1] -= t1 + t1 - t1 * t1 - 1
    m2 = ph > 1 - dt
    t2 = (ph[m2] - 1) / dt[m2]
    y[m2] -= t2 * t2 + t2 + t2 + 1
    return y


def lp(x, f, order=2):
    return sosfilt(butter(order, min(f, SR * 0.45), 'low', fs=SR, output='sos'), x, axis=-1)


def hp(x, f, order=2):
    return sosfilt(butter(order, f, 'high', fs=SR, output='sos'), x, axis=-1)


def bp(x, f0, f1, order=2):
    return sosfilt(butter(order, [f0, min(f1, SR * 0.45)], 'band', fs=SR, output='sos'), x, axis=-1)


def env(n, a=0.002, d=0.2, s=0.0, r=0.05, hold=None):
    t = np.arange(n) / SR
    e = np.minimum(1, t / max(a, 1e-4))
    dec = s + (1 - s) * np.exp(-np.maximum(0, t - a) / d)
    e = e * dec
    if hold is not None:
        rel = np.clip(1 - (t - hold) / r, 0, 1)
        e *= np.where(t > hold, rel, 1)
    return e


# ---------------------------------------------------------------- instruments
def kick(level=1.0):
    n = int(0.45 * SR)
    t = np.arange(n) / SR
    f = 46 + 120 * np.exp(-t / 0.032)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.3)
    click = hp(rng.standard_normal(n), 3000) * np.exp(-t / 0.004) * 0.35
    return np.tanh((body + click) * 1.6) * level


def clap():
    n = int(0.5 * SR)
    t = np.arange(n) / SR
    noise = rng.standard_normal(n)
    e = np.zeros(n)
    for k, off in enumerate([0, 0.009, 0.019, 0.03]):
        tt = np.maximum(0, t - off)
        e += (t >= off) * np.exp(-tt / (0.007 if k < 3 else 0.11))
    return bp(noise, 900, 3200) * e * 0.9


def snare():
    n = int(0.3 * SR)
    t = np.arange(n) / SR
    return bp(rng.standard_normal(n), 1200, 7000) * np.exp(-t / 0.06) * 0.8 + np.sin(2 * np.pi * 190 * t) * np.exp(-t / 0.04) * 0.5


def hat(open_=False):
    n = int((0.35 if open_ else 0.08) * SR)
    t = np.arange(n) / SR
    return hp(rng.standard_normal(n), 7500, 4) * np.exp(-t / (0.11 if open_ else 0.022)) * 0.5


def crash():
    n = int(2.2 * SR)
    t = np.arange(n) / SR
    x = hp(rng.standard_normal((2, n)), 4000, 2) * np.exp(-t / 0.7)
    return x * 0.35


def pluck(freq, dur):
    n = int((dur + 0.5) * SR)
    t = np.arange(n) / SR
    raw = saw(freq * 1.003, n) * 0.6 + saw(freq * 0.997, n, 0.3) * 0.6 + np.sign(np.sin(2 * np.pi * freq * t)) * 0.25
    bright, dark = lp(raw, 5200), lp(raw, 900)
    y = bright * np.exp(-t / 0.07) + dark * np.exp(-t / 0.28)
    return y * env(n, 0.003, 0.5, 0.0, 0.08, hold=dur) * 0.5


def supersaw(freqs, dur, cutoff=2600, a=0.005, d=0.4, s=0.6):
    n = int((dur + 0.25) * SR)
    out = np.zeros((2, n))
    for f in freqs:
        for k, det in enumerate([-0.18, -0.09, 0, 0.09, 0.18]):
            ff = f * 2 ** (det / 12 * 0.6)
            v = saw(ff, n, rng.random())
            pan = det / 0.18 * 0.7
            out[0] += v * np.cos((pan + 1) * np.pi / 4)
            out[1] += v * np.sin((pan + 1) * np.pi / 4)
    out = lp(out, cutoff) / (len(freqs) * 3)
    return out * env(n, a, d, s, 0.12, hold=dur)


def bassnote(freq, dur, sub=1.0, mid=0.5):
    n = int((dur + 0.08) * SR)
    t = np.arange(n) / SR
    y = np.sin(2 * np.pi * freq * t) * sub + lp(saw(freq, n), 520) * mid
    return np.tanh(y * 1.4) * env(n, 0.004, 0.6, 0.7, 0.05, hold=dur) * 0.55


def pad(freqs, dur, cutoff=1400):
    n = int((dur + 1.5) * SR)
    out = np.zeros((2, n))
    for f in freqs:
        for det in (-0.12, 0.0, 0.12):
            v = saw(f * 2 ** (det / 12), n, rng.random())
            out[0] += v * (0.6 if det <= 0 else 0.4)
            out[1] += v * (0.4 if det <= 0 else 0.6)
    out = lp(out, cutoff, 2) / (len(freqs) * 3)
    return out * env(n, 0.35, 2.0, 0.8, 1.2, hold=dur)


def bell(freq, dur=1.6):
    n = int(dur * SR)
    t = np.arange(n) / SR
    y = np.sin(2 * np.pi * freq * t + 0.8 * np.sin(2 * np.pi * freq * 3.5 * t) * np.exp(-t / 0.4))
    return y * np.exp(-t / 0.7) * 0.25


def riser(beats):
    n = T(beats)
    t = np.arange(n) / SR
    noise = rng.standard_normal(n)
    out = np.zeros(n)
    blk = 1024
    for i in range(0, n, blk):
        p = i / n
        f = 300 * (9000 / 300) ** p
        seg = noise[max(0, i - 2048):i + blk]
        out[i:i + blk] = bp(seg, f * 0.7, f * 1.4)[-min(blk, n - i):]
    amp = (t / t[-1]) ** 2.2
    tone = saw(180 * (1600 / 180) ** (t / t[-1]), n) * 0.12
    return (out * 0.9 + lp(tone, 4000)) * amp * 0.6


def impact():
    n = int(2.5 * SR)
    t = np.arange(n) / SR
    f = 38 + 70 * np.exp(-t / 0.12)
    boom = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.9)
    nz = lp(rng.standard_normal(n), 2500) * np.exp(-t / 0.35) * 0.5
    return np.tanh((boom + nz) * 1.5) * 0.8


def whoosh(length, up=False):
    n = int(length * SR)
    t = np.arange(n) / SR
    noise = rng.standard_normal(n)
    out = np.zeros(n)
    blk = 512
    for i in range(0, n, blk):
        p = i / n
        f = (600 * (5000 / 600) ** p) if up else (5000 * (500 / 5000) ** p)
        seg = noise[max(0, i - 2048):i + blk]
        out[i:i + blk] = bp(seg, f * 0.6, f * 1.6)[-min(blk, n - i):]
    shape = np.sin(np.pi * t / t[-1]) ** 1.5
    return out * shape * 0.7


def reverse_cymbal(beats):
    x = crash()[:, :T(beats)]
    return x[:, ::-1] * 1.4


# ---------------------------------------------------------------- arrangement
CHORDS = [('F', ['F4', 'Ab4', 'C5'], 'F2'), ('Db', ['Db4', 'F4', 'Ab4'], 'Db2'), ('Ab', ['Ab3', 'C4', 'Eb4'], 'Ab2'), ('Eb', ['Eb4', 'G4', 'Bb4'], 'Eb2')]
RIFF = [  # (16th step within a 4-bar phrase, note, length in 16ths)
    (0, 'C5', 2), (3, 'Ab4', 2), (6, 'C5', 2), (8, 'Eb5', 3), (11, 'C5', 2), (14, 'Bb4', 2),
    (16, 'Ab4', 2), (19, 'F4', 2), (22, 'Ab4', 2), (24, 'C5', 2), (26, 'Bb4', 2), (28, 'Ab4', 3),
    (32, 'C5', 2), (35, 'Eb5', 2), (38, 'C5', 2), (40, 'Ab5', 3), (43, 'G5', 2), (46, 'Eb5', 2),
    (48, 'Bb4', 2), (51, 'G4', 2), (54, 'Bb4', 2), (56, 'Eb5', 4), (60, 'F5', 3),
]

drums, bass, chords, lead, fxb, padb = bus(), bus(), bus(), bus(), bus(), bus()
kicks = []


def chord_at(beat):
    return CHORDS[int(beat // 4) % 4]


def put_riff(b0, b1, gain=1.0, octave=0):
    for step, nm, ln in RIFF:
        for rep in range(0, 64, 64):
            beat = b0 + (step + rep) / 4
            if beat >= b1:
                continue
            f = note(nm) * 2 ** octave
            add(lead, pluck(f, ln * SPB / 4), beat, gain, pan=0.15 if step % 8 < 4 else -0.15)


# hook + groove (0-16)
for b in range(0, 16):
    kicks.append(b)
    add(drums, kick(), b, 0.95)
    if b % 2 == 1:
        add(drums, clap(), b, 0.6, 0.05)
    add(drums, hat(), b + 0.5, 0.35, 0.3)
    if b >= 8:
        add(drums, hat(True), b + 0.5, 0.18, -0.3)
        add(drums, hat(), b + 0.25, 0.15, 0.4)
        add(drums, hat(), b + 0.75, 0.15, 0.4)
    _, notes, root = chord_at(b)
    add(bass, bassnote(note(root), SPB * 0.42, 0.9, 0.6), b + 0.5, 0.9)
    if b % 4 in (1, 3) or b % 4 == 2:
        add(chords, supersaw([note(x) for x in notes], SPB * 0.3, 2200, d=0.12, s=0.0), b + 0.5, 0.55)
put_riff(0, 16, 0.75)
add(fxb, crash(), 8, 0.5)

# build (16-24)
for b in range(16, 24, 2):
    add(drums, kick(0.8), b, 0.8)
    kicks.append(b)
roll = [(16 + k, 1.0) for k in range(4)] + [(20 + k * 0.5, 1.0) for k in range(4)] + [(22 + k * 0.25, 1.0) for k in range(4)] + [(23 + k * 0.125, 1.0) for k in range(6)]
for i, (b, _) in enumerate(roll):
    add(drums, snare(), b, 0.25 + 0.5 * i / len(roll), (-1) ** i * 0.1)
for b in range(16, 23):
    _, notes, root = chord_at(b)
    cut = 600 + 2600 * (b - 16) / 7
    add(chords, supersaw([note(x) for x in notes], SPB * 0.95, cut, a=0.01, d=0.5, s=0.5), b, 0.4)
add(padb, pad([note('F3'), note('Ab3'), note('C4'), note('Eb4')], 7 * SPB, 1600), 16, 0.5)
add(fxb, riser(7.75), 16, 0.8)
add(fxb, reverse_cymbal(1.0), 23, 0.9)
add(fxb, whoosh(0.32), 23.3, 0.9)

# drop (24-40)
add(fxb, impact(), 24, 1.0)
add(fxb, crash(), 24, 0.8)
add(fxb, crash(), 32, 0.55)
for b in range(24, 40):
    kicks.append(b)
    add(drums, kick(1.05), b, 1.0)
    if b % 2 == 1:
        add(drums, clap(), b, 0.75, 0.0)
        add(drums, snare(), b, 0.35, 0.0)
    for k in range(4):
        add(drums, hat(k == 2), b + k / 4, 0.3 if k % 2 else 0.18, 0.35 if k % 2 else -0.25)
    _, notes, root = chord_at(b)
    add(bass, bassnote(note(root), SPB * 0.9, 1.0, 0.7), b, 1.0)
    add(chords, supersaw([note(x) for x in notes] + [note(notes[0]) * 2], SPB * 0.45, 3800, d=0.25, s=0.3), b + 0.5, 0.7)
put_riff(24, 40, 0.95)
put_riff(24, 40, 0.35, octave=1)
for b in (36, 37, 38, 39):
    add(fxb, whoosh(0.16, up=True), b - 0.18, 0.55)

# breakdown (40-44): soft, then the freeze at 44
add(drums, kick(0.9), 40, 0.9)
kicks.append(40)
add(padb, pad([note('F3'), note('Ab3'), note('C4'), note('G4')], 4 * SPB, 1800), 40, 0.75)
for b in np.arange(40, 44, 0.5):
    _, notes, root = chord_at(b)
    add(lead, pluck(note(notes[int(b * 2) % 3]) * 2, SPB * 0.4), b, 0.5, pan=0.4 if int(b * 2) % 2 else -0.4)
for b in (40, 41, 42, 43):
    add(drums, hat(), b + 0.5, 0.2, 0.3)
add(fxb, reverse_cymbal(1.0), 43, 0.7)

# sidechain pump from the kicks
duck = np.ones(N)
t_all = np.arange(N) / SR
for kb in kicks:
    i = T(kb)
    seg = np.arange(N - i) / SR
    seg = seg[: int(0.45 * SR)]
    duck[i:i + len(seg)] = np.minimum(duck[i:i + len(seg)], 1 - 0.72 * np.exp(-seg / 0.11))
for b_ in (bass, chords, padb):
    b_ *= duck

# reverb send
ir_n = int(1.9 * SR)
it = np.arange(ir_n) / SR
ir = rng.standard_normal((2, ir_n)) * np.exp(-it / 0.45)
ir = lp(ir, 6000)
ir[:, :int(0.012 * SR)] = 0
ir /= np.sqrt((ir ** 2).sum(axis=1, keepdims=True))
send = lead * 0.35 + chords * 0.25 + drums * 0.06 + padb * 0.4 + fxb * 0.2
wet = np.vstack([fftconvolve(send[0], ir[0])[:N], fftconvolve(send[1], ir[1])[:N]]) * 0.9

# dotted-eighth delay on the lead
dl = T(0.75)
delayed = np.zeros_like(lead)
fb = lead.copy()
for k in range(1, 4):
    sh = dl * k
    g = 0.38 ** k
    if k % 2:
        delayed[0, sh:] += fb[1, :-sh] * g
        delayed[1, sh:] += fb[0, :-sh] * g
    else:
        delayed[:, sh:] += fb[:, :-sh] * g
lead_mix = lead + lp(delayed, 4500)

main = drums * 0.9 + bass * 0.85 + chords * 0.75 + lead_mix * 0.6 + padb * 0.6 + fxb * 0.7 + wet

# freeze at beat 44: tape-stop the music, then a tail of pad and bells
i44 = T(44)
stop_len = int(0.42 * SR)
rate = np.linspace(1, 0, stop_len) ** 1.2
pos = i44 + np.cumsum(rate)
stopped = np.vstack([np.interp(pos, np.arange(N), main[c]) for c in range(2)]) * np.linspace(1, 0, stop_len) ** 0.6
out = main.copy()
out[:, i44:] = 0
out[:, i44:i44 + stop_len] += stopped
tail = bus()
add(tail, impact(), 44, 0.5)
add(tail, pad([note('F3'), note('C4'), note('Ab4'), note('G4'), note('C5')], 4.5 * SPB, 2400), 44, 0.9)
for k, nm in enumerate(['C6', 'Ab5', 'F5', 'G5', 'Eb5', 'C5']):
    add(tail, bell(note(nm)), 44.25 + k * 0.6, 0.55, pan=(-1) ** k * 0.45)
tail_wet = np.vstack([fftconvolve(tail[0], ir[0])[:N], fftconvolve(tail[1], ir[1])[:N]])
out += tail * 0.8 + tail_wet * 0.7
# also keep a little reverb from before the stop ringing out
out[:, i44:] += wet[:, i44:] * 0.3

# fade the very end
fade = int(0.6 * SR)
out[:, -fade:] *= np.linspace(1, 0, fade) ** 1.5

# master: gentle glue + soft clip, then normalise to -1 dBFS
out = hp(out, 28)
out = np.tanh(out * 0.9) / np.tanh(0.9)
out *= 10 ** (-1 / 20) / np.abs(out).max()

os.makedirs(OUT, exist_ok=True)
pcm = (out.T * 32767).astype(np.int16)
with wave.open(os.path.join(OUT, 'music.wav'), 'wb') as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(pcm.tobytes())
print(f'wrote music.wav, {DUR:.2f} s, rms {20 * np.log10(np.sqrt((out ** 2).mean())):.1f} dBFS')

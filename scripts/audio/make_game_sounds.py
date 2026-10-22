#!/usr/bin/env python3
"""ゲームの効果音と BGM を合成で作る（issue #155）。

外部の音源は使わない。矩形波・三角波・ノイズだけで 8bit 風に鳴らす（`RestChime.wav` と同じく合成）。
旋律はすべてこのスクリプトのオリジナル。

    python3 scripts/audio/make_game_sounds.py Gymnee/Resources/Sounds

効果音は 44.1kHz / 16bit / モノラルの WAV、BGM はループ用に IMA4 の CAF（afconvert が要る＝macOS）で書き出す。
"""
import math
import os
import random
import struct
import subprocess
import sys
import wave

RATE = 44100
NOTE_NAMES = {'C': 0, 'D': 2, 'E': 4, 'F': 5, 'G': 7, 'A': 9, 'B': 11}


def freq(note):
    """'A4' / 'C#5' → 周波数。"""
    name, octave = note[:-1], int(note[-1])
    semis = NOTE_NAMES[name[0]] + (1 if name.endswith('#') else 0) - (1 if name.endswith('b') and len(name) > 1 else 0)
    midi = 12 * (octave + 1) + semis
    return 440.0 * 2 ** ((midi - 69) / 12)


def square(f, t, duty=0.5):
    return 1.0 if (f * t) % 1.0 < duty else -1.0


def triangle(f, t):
    p = (f * t) % 1.0
    return 4 * p - 1 if p < 0.5 else 3 - 4 * p


class Track:
    def __init__(self, seconds):
        self.buf = [0.0] * int(RATE * seconds)

    def add(self, start, dur, gen, vol=0.3, attack=0.004, release=0.04):
        """gen(t, i) を start 秒から dur 秒鳴らす。端はプチノイズが出ないよう短くフェードする。"""
        s = int(start * RATE)
        n = int(dur * RATE)
        for i in range(n):
            j = s + i
            if j >= len(self.buf):
                break
            t = i / RATE
            env = 1.0
            if t < attack:
                env = t / attack
            rem = dur - t
            if rem < release:
                env *= max(0.0, rem / release)
            self.buf[j] += gen(t, i) * vol * env

    def tone(self, start, dur, note, wave_='sq', duty=0.5, vol=0.25, slide_to=None, vibrato=0.0, decay=None):
        f0 = freq(note) if isinstance(note, str) else note
        f1 = (freq(slide_to) if isinstance(slide_to, str) else slide_to) if slide_to else f0
        phase = [0.0]

        def gen(t, i):
            k = t / dur if dur > 0 else 0
            f = f0 + (f1 - f0) * k
            if vibrato:
                f *= 1 + vibrato * math.sin(2 * math.pi * 6 * t)
            phase[0] += f / RATE
            p = phase[0] % 1.0
            if wave_ == 'tri':
                v = 4 * p - 1 if p < 0.5 else 3 - 4 * p
            else:
                v = 1.0 if p < duty else -1.0
            if decay:
                v *= math.exp(-t / decay)
            return v

        self.add(start, dur, gen, vol)

    def noise(self, start, dur, vol=0.3, decay=0.05, period=1, seed=1):
        rnd = random.Random(seed)
        state = [0.0, 0]

        def gen(t, i):
            if state[1] % period == 0:
                state[0] = rnd.uniform(-1, 1)
            state[1] += 1
            return state[0] * math.exp(-t / decay)

        self.add(start, dur, gen, vol, release=0.01)

    def write_wav(self, path, peak=0.85):
        top = max(1e-9, max(abs(v) for v in self.buf))
        scale = min(1.0, peak / top)
        with wave.open(path, 'wb') as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, v * scale)) * 32767)) for v in self.buf))


def arp(tr, start, notes, step, **kw):
    for i, n in enumerate(notes):
        tr.tone(start + i * step, step * 0.95, n, **kw)
    return start + len(notes) * step


# ---------------------------------------------------------------- 効果音

def sfx_hit():
    """セットを記録した＝攻撃が当たった。短い打撃音と、下がる矩形波。"""
    tr = Track(0.22)
    tr.noise(0, 0.12, vol=0.55, decay=0.03, period=3, seed=7)
    tr.tone(0.0, 0.14, 'A5', duty=0.25, vol=0.22, slide_to='A3', decay=0.08)
    return tr


def sfx_critical():
    """自己ベスト＝会心の一撃。鋭い打撃のあと、駆け上がる音。"""
    tr = Track(0.75)
    tr.noise(0, 0.16, vol=0.6, decay=0.05, period=2, seed=3)
    tr.tone(0.0, 0.1, 'E6', duty=0.125, vol=0.2, slide_to='E4')
    arp(tr, 0.12, ['E5', 'G#5', 'B5', 'E6'], 0.06, duty=0.25, vol=0.2)
    tr.tone(0.36, 0.36, 'E6', duty=0.25, vol=0.18, vibrato=0.01)
    tr.tone(0.36, 0.36, 'B5', duty=0.5, vol=0.08)
    return tr


def sfx_finish():
    """とどめ・撃破。爆発のノイズと、短い勝ちの節。"""
    tr = Track(1.5)
    tr.noise(0, 0.6, vol=0.65, decay=0.18, period=6, seed=11)
    tr.tone(0.0, 0.35, 'C5', duty=0.5, vol=0.18, slide_to='C2')
    t = 0.5
    for n, d in [('C5', 0.1), ('C5', 0.1), ('C5', 0.1), ('G5', 0.3), ('E5', 0.1), ('G5', 0.4)]:
        tr.tone(t, d * 0.92, n, duty=0.25, vol=0.2)
        t += d
    tr.tone(0.5, 0.9, 'C3', wave_='tri', vol=0.25)
    return tr


def sfx_levelup():
    """レベルアップ。上がっていく和音の節。"""
    tr = Track(1.25)
    t = 0
    for n, d in [('G4', 0.09), ('C5', 0.09), ('E5', 0.09), ('G5', 0.09), ('F5', 0.12), ('A5', 0.12), ('C6', 0.5)]:
        tr.tone(t, d * 0.9, n, duty=0.25, vol=0.2, vibrato=0.006 if d > 0.3 else 0)
        t += d
    tr.tone(0, 0.36, 'C3', wave_='tri', vol=0.25)
    tr.tone(0.36, 0.24, 'F3', wave_='tri', vol=0.25)
    tr.tone(0.6, 0.55, 'C3', wave_='tri', vol=0.25)
    return tr


def sfx_evolve():
    """進化。きらめく分散和音を重ねて、最後に長い和音。"""
    tr = Track(2.2)
    t = 0
    for chord in (['C5', 'E5', 'G5'], ['D5', 'F5', 'A5'], ['E5', 'G5', 'B5'], ['F5', 'A5', 'C6']):
        t = arp(tr, t, chord + [chord[1]], 0.07, duty=0.125, vol=0.16)
    for n in ('C5', 'E5', 'G5', 'C6'):
        tr.tone(t, 0.9, n, duty=0.25, vol=0.1, vibrato=0.008)
    tr.tone(0, t, 'C3', wave_='tri', vol=0.2)
    tr.tone(t, 0.9, 'C3', wave_='tri', vol=0.25)
    return tr


def sfx_chest():
    """宝箱を開けた。きしむ音のあと、もらえた節。"""
    tr = Track(1.1)
    tr.tone(0, 0.12, 'D4', duty=0.5, vol=0.12, slide_to='A4')
    t = 0.18
    for n, d in [('A5', 0.08), ('B5', 0.08), ('C#6', 0.08), ('D6', 0.08), ('A6', 0.5)]:
        tr.tone(t, d * 0.9, n, duty=0.125, vol=0.16, vibrato=0.01 if d > 0.3 else 0)
        t += d
    tr.tone(0.18, 0.82, 'D3', wave_='tri', vol=0.22)
    return tr


def sfx_learn():
    """新しい技を覚えた。3 音の短い合図。"""
    tr = Track(0.55)
    arp(tr, 0, ['E5', 'A5', 'C#6'], 0.08, duty=0.25, vol=0.18)
    tr.tone(0.24, 0.28, 'E6', duty=0.25, vol=0.16, vibrato=0.01)
    return tr


def sfx_select():
    """コマンドを選んだ（issue #161）。RPG のカーソルの短い 1 音。"""
    tr = Track(0.07)
    tr.tone(0, 0.05, 'B5', duty=0.5, vol=0.14)
    return tr


# ---------------------------------------------------------------- BGM（ボス部屋）

def bgm_boss():
    """ボス部屋の BGM。150bpm・8 小節のループ（イ短調、Am-F-G-E）。"""
    bpm = 150
    eighth = 60 / bpm / 2
    bars = 8
    total = bars * 8 * eighth
    tr = Track(total)
    melody = (
        'A4 - C5 - E5 - D5 C5 '
        'B4 - C5 - A4 - - - '
        'F4 - A4 - C5 - D5 C5 '
        'A4 - G4 - F4 - - - '
        'G4 - B4 - D5 - E5 D5 '
        'B4 - A4 - G4 - B4 - '
        'E5 - D5 - C5 - B4 - '
        'G#4 - B4 - E5 - - - '
    ).split()
    i = 0
    while i < len(melody):
        n = melody[i]
        length = 1
        while i + length < len(melody) and melody[i + length] == '-':
            length += 1
        tr.tone(i * eighth, length * eighth * 0.92, n, duty=0.25, vol=0.13)
        i += length
    roots = ['A2', 'A2', 'F2', 'F2', 'G2', 'G2', 'E2', 'E2']
    for b, root in enumerate(roots):
        octave_up = root[:-1] + str(int(root[-1]) + 1)
        for k in range(8):
            tr.tone((b * 8 + k) * eighth, eighth * 0.8, octave_up if k % 2 else root, wave_='tri', vol=0.22)
    for step in range(bars * 8):
        t = step * eighth
        if step % 4 == 0:
            tr.tone(t, 0.09, 110, wave_='tri', vol=0.35, slide_to=40)
        elif step % 4 == 2:
            tr.noise(t, 0.12, vol=0.22, decay=0.04, period=1, seed=step)
        tr.noise(t, 0.03, vol=0.05, decay=0.01, period=1, seed=1000 + step)
    return tr


SOUNDS = {
    'sfx_hit': sfx_hit,
    'sfx_critical': sfx_critical,
    'sfx_finish': sfx_finish,
    'sfx_levelup': sfx_levelup,
    'sfx_evolve': sfx_evolve,
    'sfx_chest': sfx_chest,
    'sfx_learn': sfx_learn,
    'sfx_select': sfx_select,
}


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else 'Gymnee/Resources/Sounds'
    os.makedirs(out, exist_ok=True)
    for name, make in SOUNDS.items():
        make().write_wav(os.path.join(out, f'{name}.wav'))
        print('wrote', name)
    tmp = os.path.join(out, 'bgm_boss.tmp.wav')
    bgm_boss().write_wav(tmp, peak=0.7)
    caf = os.path.join(out, 'bgm_boss.caf')
    subprocess.run(['afconvert', '-f', 'caff', '-d', 'ima4', tmp, caf], check=True)
    os.remove(tmp)
    print('wrote bgm_boss')


if __name__ == '__main__':
    main()

#!/usr/bin/env python3
"""
KanMon GO — Sound Effect Generator
Menghasilkan semua SFX yang dibutuhkan sebagai WAV 44100Hz 16-bit mono.
"""

import wave, struct, math, os

RATE   = 44100
OUT    = "assets/sounds"
os.makedirs(OUT, exist_ok=True)

def write_wav(filename, samples):
    path = os.path.join(OUT, filename)
    with wave.open(path, 'w') as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        data = struct.pack(f'<{len(samples)}h', *[max(-32768, min(32767, int(s))) for s in samples])
        f.writeframes(data)
    print(f"  ✅ {filename}  ({len(samples)/RATE*1000:.0f}ms)")

def silence(dur): return [0] * int(RATE * dur)

def sine(freq, dur, amp=0.7, phase=0.0):
    n = int(RATE * dur)
    return [int(amp * 32767 * math.sin(2*math.pi*freq*i/RATE + phase)) for i in range(n)]

def envelope(samples, attack=0.005, decay=0.05, sustain=0.7, release=0.1):
    n = len(samples)
    a_n = int(RATE * attack)
    d_n = int(RATE * decay)
    r_n = int(RATE * release)
    s_n = max(0, n - a_n - d_n - r_n)
    out = []
    for i, s in enumerate(samples):
        if   i < a_n:                        gain = i / a_n
        elif i < a_n + d_n:                  gain = 1.0 - (1.0 - sustain) * (i - a_n) / d_n
        elif i < a_n + d_n + s_n:            gain = sustain
        else:                                gain = sustain * (1.0 - (i - a_n - d_n - s_n) / max(1, r_n))
        out.append(int(s * gain))
    return out

def mix(*tracks):
    n = max(len(t) for t in tracks)
    result = []
    for i in range(n):
        v = sum(t[i] if i < len(t) else 0 for t in tracks)
        result.append(max(-32768, min(32767, int(v / len(tracks) * 1.8))))
    return result

def chord(freqs, dur, amp=0.6):
    tracks = [sine(f, dur, amp/len(freqs)) for f in freqs]
    return mix(*tracks)

def noise(dur, amp=0.3):
    import random
    n = int(RATE * dur)
    return [int(amp * 32767 * (random.random()*2-1)) for _ in range(n)]

def lowpass(samples, cutoff=800):
    rc = 1.0 / (2 * math.pi * cutoff)
    dt = 1.0 / RATE
    alpha = dt / (rc + dt)
    out, prev = [], 0
    for s in samples:
        prev = prev + alpha * (s - prev)
        out.append(int(prev))
    return out

# ─────────────────────────────────────────────────────────────────────────────
# 1. CORRECT — jawaban benar
#    Dua nada naik cepat, cerah dan menyenangkan
# ─────────────────────────────────────────────────────────────────────────────
def make_correct():
    n1 = envelope(sine(523, 0.10, 0.65), attack=0.005, decay=0.02, sustain=0.8, release=0.07)
    n2 = envelope(sine(784, 0.14, 0.65), attack=0.005, decay=0.02, sustain=0.8, release=0.09)
    gap = silence(0.03)
    samples = n1 + gap + n2
    write_wav("correct.wav", samples)

# ─────────────────────────────────────────────────────────────────────────────
# 2. WRONG — jawaban salah
#    Satu nada rendah singkat, menurun
# ─────────────────────────────────────────────────────────────────────────────
def make_wrong():
    # Descending buzz
    n = int(RATE * 0.25)
    samples = []
    for i in range(n):
        t = i / RATE
        freq = 220 - 80 * (i / n)          # menurun 220→140 Hz
        v = 0.55 * 32767 * math.sin(2*math.pi*freq*t)
        # apply envelope
        if i < n * 0.05:   gain = i / (n * 0.05)
        elif i < n * 0.85: gain = 1.0 - 0.3 * (i - n*0.05) / (n * 0.80)
        else:               gain = 0.7 * (1.0 - (i - n*0.85) / (n * 0.15))
        samples.append(int(v * gain))
    write_wav("wrong.wav", samples)

# ─────────────────────────────────────────────────────────────────────────────
# 3. PERFECT / QUIZ COMPLETE — selesai dengan score tinggi
#    Arpeggio naik 4 nada + chord akhir
# ─────────────────────────────────────────────────────────────────────────────
def make_perfect():
    freqs = [523, 659, 784, 1047]
    parts = []
    for i, f in enumerate(freqs):
        n = envelope(sine(f, 0.10, 0.55), attack=0.004, decay=0.02, sustain=0.75, release=0.06)
        parts.extend(n)
        if i < len(freqs)-1:
            parts.extend(silence(0.02))
    # Final chord
    parts.extend(silence(0.04))
    c = envelope(chord(freqs, 0.45, 0.5), attack=0.01, decay=0.05, sustain=0.7, release=0.28)
    parts.extend(c)
    write_wav("perfect.wav", parts)

# ─────────────────────────────────────────────────────────────────────────────
# 4. TAP / UI CLICK — ketuk tombol umum
#    Klik ringan dan bersih
# ─────────────────────────────────────────────────────────────────────────────
def make_tap():
    n = int(RATE * 0.07)
    samples = []
    for i in range(n):
        t = i / RATE
        freq = 1200 - 600 * (i/n)          # descending click
        v = 0.40 * 32767 * math.sin(2*math.pi*freq*t)
        gain = math.exp(-30 * t)
        samples.append(int(v * gain))
    write_wav("tap.wav", samples)

# ─────────────────────────────────────────────────────────────────────────────
# 5. FLIP — balik kartu flashcard
#    Whoosh tipis singkat
# ─────────────────────────────────────────────────────────────────────────────
def make_flip():
    n = int(RATE * 0.12)
    samples = []
    for i in range(n):
        t = i / RATE
        freq = 800 + 1200 * (i / n)        # sweep up
        v = 0.30 * 32767 * math.sin(2*math.pi*freq*t)
        # bell envelope
        if i < n * 0.1:  gain = i / (n * 0.1)
        else:             gain = math.exp(-8 * (i/n - 0.1))
        samples.append(int(v * gain))
    write_wav("flip.wav", samples)

# ─────────────────────────────────────────────────────────────────────────────
# 6. SWIPE_NEXT — swipe ke soal berikutnya
#    Whoosh singkat ke kanan
# ─────────────────────────────────────────────────────────────────────────────
def make_swipe_next():
    n = int(RATE * 0.10)
    samples = []
    for i in range(n):
        freq = 600 + 800 * (i/n)
        v = 0.25 * 32767 * math.sin(2*math.pi*freq*i/RATE)
        gain = math.exp(-10 * (i/n))
        samples.append(int(v * gain))
    write_wav("swipe_next.wav", samples)

# ─────────────────────────────────────────────────────────────────────────────
# 7. STROKE_OK — goresan menulis berhasil di-snap
#    Ting kecil
# ─────────────────────────────────────────────────────────────────────────────
def make_stroke_ok():
    n = int(RATE * 0.15)
    samples = []
    for i in range(n):
        t = i / RATE
        v = 0.45 * 32767 * math.sin(2*math.pi*880*t)
        gain = math.exp(-18 * t)
        samples.append(int(v * gain))
    write_wav("stroke_ok.wav", samples)

# ─────────────────────────────────────────────────────────────────────────────
# 8. STREAK — streak / combo berhasil (setiap 3 benar berturut)
#    Ascending 3 nada cepat
# ─────────────────────────────────────────────────────────────────────────────
def make_streak():
    freqs = [659, 784, 988]
    parts = []
    for f in freqs:
        n = envelope(sine(f, 0.07, 0.55), attack=0.003, decay=0.01, sustain=0.8, release=0.05)
        parts.extend(n)
        parts.extend(silence(0.015))
    write_wav("streak.wav", parts)

# ─────────────────────────────────────────────────────────────────────────────
# 9. LEVEL_UP — naik level / unlock fitur
#    Fanfare kecil 5 nada
# ─────────────────────────────────────────────────────────────────────────────
def make_level_up():
    # C4 E4 G4 C5 — ascending triumphant
    seq = [(261, 0.08), (329, 0.08), (392, 0.08), (523, 0.08), (659, 0.22)]
    parts = []
    for f, dur in seq:
        n = envelope(sine(f, dur, 0.60), attack=0.005, decay=0.02, sustain=0.75, release=dur*0.5)
        parts.extend(n)
        parts.extend(silence(0.01))
    write_wav("level_up.wav", parts)

# ─────────────────────────────────────────────────────────────────────────────
# 10. OPEN_SCREEN — buka screen/menu baru
#     Lembut, pop ascending
# ─────────────────────────────────────────────────────────────────────────────
def make_open_screen():
    n = int(RATE * 0.12)
    samples = []
    for i in range(n):
        t = i / RATE
        freq = 400 + 500 * math.sqrt(i/n)  # sqrt sweep up
        v = 0.28 * 32767 * math.sin(2*math.pi*freq*t)
        if i < n*0.1:   gain = i/(n*0.1)
        else:            gain = math.exp(-6*(i/n - 0.1))
        samples.append(int(v * gain))
    write_wav("open_screen.wav", samples)

# ─────────────────────────────────────────────────────────────────────────────
# 11. BACK / CLOSE — tutup screen
#     Pop menurun singkat
# ─────────────────────────────────────────────────────────────────────────────
def make_back():
    n = int(RATE * 0.10)
    samples = []
    for i in range(n):
        t = i / RATE
        freq = 600 - 300 * (i/n)
        v = 0.25 * 32767 * math.sin(2*math.pi*freq*t)
        gain = math.exp(-12 * t)
        samples.append(int(v * gain))
    write_wav("back.wav", samples)

# ─────────────────────────────────────────────────────────────────────────────
# 12. TIMER_TICK — tiap detik timer exam
#     Tick metronom ringan
# ─────────────────────────────────────────────────────────────────────────────
def make_timer_tick():
    n = int(RATE * 0.06)
    samples = []
    for i in range(n):
        t = i / RATE
        v = 0.20 * 32767 * math.sin(2*math.pi*1400*t)
        gain = math.exp(-45 * t)
        samples.append(int(v * gain))
    write_wav("timer_tick.wav", samples)

# ─────────────────────────────────────────────────────────────────────────────
# 13. TIMER_WARNING — waktu tersisa sedikit
#     Tick lebih keras, nada berbeda
# ─────────────────────────────────────────────────────────────────────────────
def make_timer_warning():
    n = int(RATE * 0.09)
    samples = []
    for i in range(n):
        t = i / RATE
        v = 0.45 * 32767 * math.sin(2*math.pi*880*t)
        gain = math.exp(-22 * t)
        samples.append(int(v * gain))
    write_wav("timer_warning.wav", samples)

# ─────────────────────────────────────────────────────────────────────────────
# 14. BOOKMARK — tambah/hapus bookmark
#     Pop manis 2 nada
# ─────────────────────────────────────────────────────────────────────────────
def make_bookmark():
    n1 = envelope(sine(880, 0.07, 0.45), attack=0.004, decay=0.01, sustain=0.7, release=0.04)
    n2 = envelope(sine(1108, 0.10, 0.45), attack=0.004, decay=0.01, sustain=0.7, release=0.07)
    write_wav("bookmark.wav", n1 + silence(0.02) + n2)

# ─────────────────────────────────────────────────────────────────────────────
# 15. NOTIFICATION — informasi/toast muncul
#     Dua nada lembut
# ─────────────────────────────────────────────────────────────────────────────
def make_notification():
    n1 = envelope(sine(698, 0.09, 0.35), attack=0.01, decay=0.02, sustain=0.6, release=0.05)
    n2 = envelope(sine(880, 0.13, 0.35), attack=0.01, decay=0.02, sustain=0.6, release=0.08)
    write_wav("notification.wav", n1 + silence(0.03) + n2)

# ─────────────────────────────────────────────────────────────────────────────
# 16. APP_START — splash screen / pertama buka app
#     Intro lembut 3 nada + chord
# ─────────────────────────────────────────────────────────────────────────────
def make_app_start():
    parts = []
    for f in [392, 523, 659]:
        n = envelope(sine(f, 0.12, 0.40), attack=0.01, decay=0.03, sustain=0.65, release=0.07)
        parts.extend(n)
        parts.extend(silence(0.04))
    c = envelope(chord([392, 523, 659, 784], 0.55, 0.35), attack=0.02, decay=0.05, sustain=0.65, release=0.35)
    parts.extend(c)
    write_wav("app_start.wav", parts)

# ─────────────────────────────────────────────────────────────────────────────
# Run semua
# ─────────────────────────────────────────────────────────────────────────────
print("\n🎵 Generating KanMon GO Sound Effects...\n")
make_correct()
make_wrong()
make_perfect()
make_tap()
make_flip()
make_swipe_next()
make_stroke_ok()
make_streak()
make_level_up()
make_open_screen()
make_back()
make_timer_tick()
make_timer_warning()
make_bookmark()
make_notification()
make_app_start()

files = os.listdir(OUT)
total_kb = sum(os.path.getsize(os.path.join(OUT,f)) for f in files) // 1024
print(f"\n✅ {len(files)} sound effects generated → {total_kb} KB total")
print(f"   📁 {OUT}")

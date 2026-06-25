# 🎮 Tutorial Demoscene Art - MASM32 Assembly

> Program demoscene visual + musik 4 layer menggunakan Windows API murni.  
> Ditulis dalam MASM32 (x86 32-bit Assembly) untuk Windows oleh Moh Rizal HP (MRHPx / mrhpx@yahoo.com).


---

![Alt text](Screenshot.jpg?raw=true "MRHPx Demoscene Art - MASM32")


## 📋 Daftar Isi

1. [Apa Itu Demoscene?](#1-apa-itu-demoscene)
2. [Prasyarat & Tools](#2-prasyarat--tools)
3. [Struktur Program Secara Keseluruhan](#3-struktur-program-secara-keseluruhan)
4. [Sistem Audio — waveOut API](#4-sistem-audio--waveout-api)
5. [Synthesizer — Membuat Suara dari Nol](#5-synthesizer--membuat-suara-dari-nol)
6. [Sequencer — Memainkan Lagu](#6-sequencer--memainkan-lagu)
7. [Efek Plasma — Visual Psychedelic](#7-efek-plasma--visual-psychedelic)
8. [Rendering Frame & Teks Scrolling](#8-rendering-frame--teks-scrolling)
9. [Message Loop & Arsitektur Window](#9-message-loop--arsitektur-window)
10. [Cara Kompilasi & Menjalankan](#10-cara-kompilasi--menjalankan)
11. [Ringkasan Konsep Kunci](#11-ringkasan-konsep-kunci)

---

## 1. Apa Itu Demoscene?

**Demoscene** adalah budaya seni komputer di mana programmer membuat program kecil yang menampilkan efek visual dan musik yang imersif — biasanya dengan ukuran file yang sangat kecil (64KB, 4KB, bahkan 256 byte).

Program ini adalah contoh mini demoscene yang menggabungkan:

| Komponen | Teknologi |
|---|---|
| 🎵 Musik 4 layer | Synthesis langsung (triangle, saw, square, drum) |
| 🌈 Visual plasma | Algoritma interferensi gelombang |
| 📜 Teks scrolling | GDI Windows API |
| 🔊 Audio real-time | waveOut polling (double buffer) |

---

## 2. Prasyarat & Tools

### Yang Dibutuhkan

- **MASM32 SDK** — assembler dan library Windows untuk x86  
  Unduh di: http://www.masm32.com/
- **Windows 32-bit** atau Windows 64-bit dengan dukungan WOW64
- Text editor apa saja (Notepad++, VS Code, dll.)

### Struktur File

```
project/
├── demoscene.asm     ← source code utama
└── (output)
    └── demoscene.exe ← hasil kompilasi
```

### Cara Kompilasi

```bat
\masm32\bin\ml.exe /c /coff demoscene.asm
\masm32\bin\link.exe /subsystem:windows demoscene.obj \
    \masm32\lib\user32.lib \
    \masm32\lib\kernel32.lib \
    \masm32\lib\gdi32.lib \
    \masm32\lib\winmm.lib
```

---

## 3. Struktur Program Secara Keseluruhan

```
┌─────────────────────────────────────────────────┐
│                  WinMain / start                │
│   RegisterClass → CreateWindow → Message Loop  │
└──────────────────────┬──────────────────────────┘
                       │ WM_CREATE
                       ▼
              ┌────────────────┐
              │  InitAudio     │  ← Buka waveOut, isi buffer awal
              └────────────────┘
                       │ WM_TIMER (setiap 33ms)
                       ▼
         ┌─────────────────────────────┐
         │         UpdateAudio         │
         │  Cek buffer selesai?        │
         │  → FillAudioBuffer          │
         │    → AdvanceSequencer       │
         │    → SynthTriangle (melodi) │
         │    → SynthSaw (bass)        │
         │    → SynthSquareSoft (arp)  │
         │    → GetNextSample_Drum     │
         └────────────┬────────────────┘
                      │
                      ▼
         ┌─────────────────────────────┐
         │         RenderFrame         │
         │  → RenderPlasma (320×240)   │
         │  → StretchBlt ke window     │
         │  → TextOut (scroller)       │
         └─────────────────────────────┘
```

Program berjalan dalam **loop event Windows standar**. Timer setiap ~33ms (≈30 FPS) memicu update audio dan visual secara bersamaan.

---

## 4. Sistem Audio — waveOut API

### Konsep Double Buffering

Masalah utama audio real-time: kita tidak bisa berhenti mengisi data saat audio sedang diputar. Solusinya adalah **double buffering**:

```
Buffer 1: [▶ sedang diputar]   Buffer 2: [✏ sedang diisi ulang]
         ↓ selesai
Buffer 1: [✏ sedang diisi ulang]   Buffer 2: [▶ sedang diputar]
```

Dua buffer bergantian — satu selalu diputar, satu selalu disiapkan.

### Deklarasi Manual WAVEHDR

Kode ini tidak menggunakan `mmsystem.inc`, jadi struktur `WAVEHDR` dideklarasikan manual di `.data`:

```asm
; WAVEHDR untuk AudioBuf1
WaveHdr1_lpData     dd offset AudioBuf1  ; pointer ke buffer data
WaveHdr1_dwBufLen   dd BUFFER_SIZE       ; panjang buffer (4410 byte)
WaveHdr1_dwBytesRec dd 0
WaveHdr1_dwUser     dd 0
WaveHdr1_dwFlags    dd 0                 ; flag WHDR_DONE diset driver saat selesai
WaveHdr1_dwLoops    dd 1
WaveHdr1_lpNext     dd 0
WaveHdr1_reserved   dd 0
```

> **Mengapa manual?** Karena MASM32 standar tidak selalu menyertakan `mmsystem.inc`. Dengan mendeklarsikan field satu per satu, kita tahu persis layout memorinya.

### Format Audio

```asm
SAMPLE_RATE  equ 44100  ; Hz — kualitas CD
BUFFER_SIZE  equ 4410   ; sampel = ~100ms per buffer
; 8-bit unsigned mono: nilai 0=minimum, 128=silence, 255=maximum
```

### Alur `InitAudio`

```asm
; 1. Buka device audio
invoke waveOutOpen, addr hWaveOut, WAVE_MAPPER, addr WaveFmt_Tag, 0, 0, CALLBACK_NULL

; 2. Isi kedua buffer dengan audio
mov esi, offset AudioBuf1
mov ecx, BUFFER_SIZE
call FillAudioBuffer          ; hasilkan 4410 sampel audio

; 3. Submit ke driver
invoke waveOutPrepareHeader, hWaveOut, addr WaveHdr1_lpData, WAVEHDR_SIZE
invoke waveOutWrite, hWaveOut, addr WaveHdr1_lpData, WAVEHDR_SIZE
; (ulangi untuk Buffer 2)
```

### Alur `UpdateAudio` (Polling)

```asm
; Cek apakah Buffer 1 sudah selesai diputar driver
mov eax, WaveHdr1_dwFlags
test eax, WHDR_DONE           ; driver set flag ini saat buffer selesai
jz  UA_chk2                   ; belum selesai? cek buffer 2

; Jika selesai: unregister → isi ulang → submit lagi
invoke waveOutUnprepareHeader, hWaveOut, addr WaveHdr1_lpData, WAVEHDR_SIZE
and  WaveHdr1_dwFlags, NOT WHDR_DONE  ; bersihkan flag
call FillAudioBuffer          ; hasilkan audio baru
invoke waveOutPrepareHeader, hWaveOut, addr WaveHdr1_lpData, WAVEHDR_SIZE
invoke waveOutWrite, hWaveOut, addr WaveHdr1_lpData, WAVEHDR_SIZE
```

---

## 5. Synthesizer — Membuat Suara dari Nol

Program menggunakan **tiga jenis gelombang** untuk tiga layer melodi, dan **envelope-based synthesis** untuk drum. Semuanya di-*mix* menjadi satu output audio.

### Konsep Phase Accumulator

Cara paling efisien membuat oscillator di assembly adalah **akumulator fase 16.16 fixed-point**:

```
phase_increment = frekuensi × 65536 / SAMPLE_RATE
fase += phase_increment  (setiap sampel)
bentuk_gelombang = f(fase >> 8)  ← ambil bit 8-15 sebagai "sudut" 0..255
```

Dengan `SAMPLE_RATE = 44100` Hz dan misalnya `freq = 440` Hz (nada A4):
```
increment = 440 × 65536 / 44100 = 654
```
Fase akan memutar penuh (0 → 65535) setiap 44100/440 = 100 sampel → 440 putaran per detik = 440 Hz. ✓

---

### 5.1 Triangle Wave — Layer Melodi

Triangle wave menghasilkan suara lembut karena hanya memiliki harmonik ganjil dengan amplitudo yang cepat menurun.

```
Bentuk gelombang:
    /\      /\      /\
   /  \    /  \    /  \
  /    \  /    \  /    \
 /      \/      \/      \
```

```asm
SynthTriangle proc
    ; Input: EAX = frekuensi, EDI = pointer ke variabel fase
    cmp eax, NOTE_REST
    jne ST_play
    mov al, 128         ; diam = nilai tengah unsigned
    ret

ST_play:
    ; Hitung dan akumulasi fase
    shl eax, 16         ; freq × 65536
    xor edx, edx
    mov ebx, SAMPLE_RATE
    div ebx             ; EAX = increment
    add [edi], eax      ; akumulasi fase
    mov eax, [edi]
    shr eax, 8          ; ambil bit 8-15 → fase 0..255

    ; Bentuk triangle: naik 0→127, turun 128→255
    cmp eax, 128
    jl  ST_rising
    neg eax
    add eax, 255        ; lipat balik: 255-eax → 127..0

ST_rising:
    ; Petakan 0..127 → 78..178 (amplitudo ±50, center 128)
    imul eax, 100
    xor edx, edx
    mov ebx, 127
    div ebx
    add eax, 78
    ret
SynthTriangle endp
```

**Kenapa output 78..178 bukan 0..255?**  
Karena kita akan me-*mix* beberapa layer. Jika tiap layer sudah menggunakan rentang penuh, hasilnya akan *clipping* saat dijumlahkan. Amplitudo yang lebih kecil memberi ruang untuk mixing.

---

### 5.2 Sawtooth Wave — Layer Bass

Sawtooth ("gigi gergaji") mengandung **semua harmonik** sehingga suaranya gemuk dan hangat — cocok untuk bass.

```
Bentuk gelombang:
    /|   /|   /|
   / |  / |  / |
  /  | /  | /  |
 /   |/   |/   |
```

```asm
SynthSaw proc
    ; Sama dengan triangle tapi mapping langsung (linear)
    ; fase 0..255 → output 68..188 (amplitudo ±60)
    imul eax, 120
    xor edx, edx
    mov ebx, 255
    div ebx
    add eax, 68
    ret
SynthSaw endp
```

---

### 5.3 Square Wave Soft — Layer Arpeggio

Square wave hanya punya dua nilai: *high* dan *low*. Versi "soft" ini dengan amplitudo kecil dipakai sebagai *chord shimmer* di latar belakang.

```asm
SynthSquareSoft proc
    ; Fase 0..127  → high (153 = 128+25)
    ; Fase 128..255 → low  (103 = 128-25)
    cmp eax, 128
    jl  SQS_hi
    mov al, 103     ; low
    ret
SQS_hi:
    mov al, 153     ; high
    ret
SynthSquareSoft endp
```

---

### 5.4 Drum Synthesis — Kick, Snare, Hi-Hat

Drum tidak menggunakan oscillator permanen. Setiap pukulan men-*trigger* sebuah **envelope** (nilai yang berkurang dari waktu ke waktu).

#### Kick Drum — Square Wave + Pitch Sweep

```
Amplitudo: 3000 ──────────────────→ 0   (berkurang 3/sampel)
Frekuensi: KickEnv/10 → turun dari ~300Hz ke 20Hz
```

```asm
; Frekuensi efektif kick = KickEnv / 10 (turun seiring waktu)
mov eax, KickEnv
mov ecx, 10
div ecx                 ; freq efektif saat ini

; Scale output dengan envelope:
imul eax, KickEnv
mov ecx, 3000
idiv ecx                ; semakin kecil KickEnv → semakin pelan suara

sub KickEnv, 3          ; decay: kurangi 3 per sampel
```

**Efek yang dihasilkan:** suara "boom" yang cepat turun pitch — ciri khas kick drum elektronik.

#### Snare Drum — White Noise + Envelope

```asm
; LCG (Linear Congruential Generator) untuk noise acak:
; state_baru = state_lama × 1664525 + 1013904223
mov eax, NoiseState
imul eax, 1664525
add eax, 1013904223
mov NoiseState, eax

; Ambil bit 16-21 sebagai noise -32..31
shr eax, 16
and eax, 63
sub eax, 32

; Scale dengan envelope (habis dalam ~250 sampel)
sub SnareEnv, 10
```

#### Hi-Hat — Noise Sangat Pendek

```asm
; Sama dengan snare tapi:
; - Envelope mulai dari 800 (bukan 2500)
; - Decay lebih cepat: -30/sampel (habis dalam ~27 sampel = 0.6ms)
; - Amplitudo lebih kecil
sub HihatEnv, 30
```

---

### 5.5 Mixing — Menggabungkan 4 Layer

```asm
; Bobot tiap layer:
; Melodi (triangle) × 5 — terdengar jelas
; Bass   (sawtooth) × 6 — sedikit lebih kuat
; Arpeggio (square) × 2 — sangat lembut, hanya shimmer
; Drum               × 7 — paling dominan untuk punch ritmis

imul ebx, 5     ; melodi
imul ecx, 6     ; bass
imul edx, 2     ; arpeggio
imul eax, 7     ; drum

add ebx, ecx
add ebx, edx
add ebx, eax

; Normalisasi: ×13/256 ≈ ÷20 (pendekatan bit-shift)
; Mengapa 13/256? karena 13/256 ≈ 1/19.7 ≈ 1/(5+6+2+7)
imul ebx, 13
sar ebx, 8      ; bagi 256 dengan arithmetic shift (lebih cepat dari div)

; Soft clamp -110..110 (cegah hard clipping)
cmp ebx, 110
jle MixOK_hi
mov ebx, 110

; Konversi signed → unsigned: tambah 128
add ebx, 128
mov [esi], bl   ; tulis ke buffer audio
```

---

## 6. Sequencer — Memainkan Lagu

### Format Data Sekuens

Setiap instrumen punya array pasangan `{frekuensi, durasi}`:

```asm
MelodyData  dd NOTE_F4,  BEAT        ; nada F4, durasi 1 ketukan
            dd NOTE_GS4, HALF_BEAT   ; nada G#4, durasi 1/2 ketukan
            dd NOTE_REST, BEAT       ; diam, durasi 1 ketukan
            dd 0FFFFFFFFh, 0         ; sentinel = ulangi dari awal
```

Konstanta durasi dalam sampel (BPM 120, 44100 Hz):
```
BEAT        = 22050  → 0.5 detik (1 ketukan pada 120 BPM)
HALF_BEAT   = 11025  → 0.25 detik
QTR_BEAT    = 5512   → 0.125 detik
EIGHTH_BEAT = 2756   → 0.0625 detik
```

### Cara `AdvanceSequencer` Bekerja

```asm
AdvMel:
    cmp MelSampLeft, 0      ; apakah note saat ini sudah habis?
    jne AdvMelDone          ; belum → lewati, kurangi hitungan saja

    ; Note habis: muat note berikutnya
    mov eax, MelIndex       ; indeks note saat ini
    shl eax, 3              ; × 8 (setiap entry = 2 DWORD = 8 byte)
    add eax, offset MelodyData
    
    mov ecx, [eax]          ; baca frekuensi
    cmp ecx, 0FFFFFFFFh     ; sentinel?
    jne AdvMelLoad
    mov MelIndex, 0         ; reset ke awal (loop)
    jmp AdvMel

AdvMelLoad:
    mov MelCurFreq, ecx     ; set frekuensi aktif
    mov ecx, [eax+4]        ; baca durasi
    mov MelSampLeft, ecx    ; set countdown
    inc MelIndex             ; maju ke note berikutnya

AdvMelDone:
    dec MelSampLeft         ; hitung mundur setiap sampel
```

Fungsi ini dipanggil **sekali per sampel** dari `FillAudioBuffer`, sehingga semua layer (melodi, bass, arp, drum) bergerak maju secara presisi bersamaan.

---

## 7. Efek Plasma — Visual Psychedelic

### Algoritma Interferensi Gelombang

Plasma demoscene klasik dibuat dengan **menjumlahkan beberapa gelombang sinus sederhana** dan mengambil nilai modulo-nya sebagai warna.

```asm
; Tiga gelombang dengan arah berbeda:
wave1 = px/2 + phase1          ; horizontal
wave2 = py/2 + phase2          ; vertikal
wave3 = (px + py)/4 + phase3   ; diagonal

; Interferensi:
val = (wave1 + wave2 + wave3) AND 255
```

**Kunci penting:** `AND 255` dilakukan **setelah** semua dijumlahkan — bukan di tengah. Ini menghasilkan pola interferensi yang benar-benar non-linear dan organik.

```
❌ Salah (striping tajam):
val = (wave1 AND 255) + (wave2 AND 255) + (wave3 AND 255)

✅ Benar (plasma organik):
val = (wave1 + wave2 + wave3) AND 255
```

### Pemetaan Warna

Satu nilai `val` (0..255) dipetakan ke tiga channel warna dengan offset 1/3 siklus:

```asm
; Merah: val mod 256
mov eax, val
and eax, 0FFh           ; sudah 0..255

; Hijau: (val + 85) mod 256  ← geser 1/3 siklus (255/3 ≈ 85)
mov ebx, val
add ebx, 85
and ebx, 0FFh
shl ebx, 8              ; pindah ke byte G (bit 8-15)

; Biru: (val + 170) mod 256  ← geser 2/3 siklus
mov ecx, val
add ecx, 170
and ecx, 0FFh
shl ecx, 16             ; pindah ke byte B (bit 16-23)

; Gabung jadi pixel 32-bit BGRA
or  eax, ebx
or  eax, ecx
mov [esi], eax          ; tulis pixel
add esi, 4              ; piksel 32-bit = 4 byte
```

Hasilnya: setiap daerah plasma punya warna berbeda dengan **transisi yang halus dan kontinu**.

### Animasi

Setiap frame, ketiga fase dinaikkan dengan kecepatan berbeda:

```asm
add phase1, 2   ; horizontal: kecepatan sedang
add phase2, 3   ; vertikal: lebih cepat → efek gerak diagonal
add phase3, 1   ; diagonal: paling lambat → efek "bernapas"
```

Karena ketiga gelombang bergerak dengan kecepatan berbeda, pola yang muncul tidak pernah benar-benar berulang dalam waktu singkat.

---

## 8. Rendering Frame & Teks Scrolling

### Alur Render Satu Frame

```
RenderFrame:
  1. GetClientRect → tahu ukuran window sekarang
  2. RenderPlasma → isi Buffer[] (320×240 pixel 32-bit)
  3. GetDC → ambil DC window
  4. CreateCompatibleDC + CreateCompatibleBitmap (320×240)
  5. SetDIBitsToDevice → upload Buffer ke memory DC
  6. CreateCompatibleDC + CreateCompatibleBitmap (full window)
  7. StretchBlt (HALFTONE) → stretch plasma ke ukuran window
  8. Gambar shadow teks (hitam, offset +3/-3)
  9. Gambar teks utama (emas 0xFFD700)
 10. Gambar teks highlight (kuning cerah 0xFFFF00)
 11. Cleanup semua DC dan bitmap sementara
 12. BitBlt ke window DC
 13. ReleaseDC
```

> **Penting:** Setiap bitmap dan DC yang dibuat **harus dihapus** di akhir frame. Lupa cleanup akan menyebabkan *resource leak* — program perlahan makan memori GDI hingga Windows kehabisan.

### Double DC: Mengapa Dua Memory DC?

| DC | Bitmap | Isi |
|---|---|---|
| `hDCMem` | 320×240 | Plasma mentah dari `Buffer[]` |
| `hDCMem2` | Window size | Output akhir (plasma + teks scrolling) |

Kita render plasma di resolusi kecil dulu (lebih cepat), lalu stretch ke window. Teks digambar di atas versi yang sudah di-stretch.

### Teks Scrolling — Logika Reset yang Benar

```asm
; Posisi teks saat ini:
; xPos = (WinWidth - txtW) / 2 + ScrollPos

; Teks keluar layar kiri saat ujung kanannya (xPos + txtW) < 0:
; xPos + txtW = (WinWidth - txtW)/2 + ScrollPos + txtW < 0

; Untuk reset, hitung xPos aktual:
mov eax, WinWidth
sub eax, txtW
sar eax, 1          ; (WinWidth - txtW) / 2  (signed division)
add eax, ScrollPos  ; xPos aktual
add eax, txtW       ; ujung kanan teks

cmp eax, 0
jg  RF_sc           ; masih terlihat → lanjut scroll

; Reset: agar teks mulai dari 50px di luar kanan layar
; xPos_baru = WinWidth + 50
; → ScrollPos = WinWidth + 50 - (WinWidth - txtW)/2
;             = (WinWidth + txtW)/2 + 50
mov eax, WinWidth
add eax, txtW
sar eax, 1
add eax, 50
mov ScrollPos, eax
```

---

## 9. Message Loop & Arsitektur Window

### WndProc — Handler Pesan Window

```asm
WndProc proc hWnd:DWORD, uMsg:DWORD, wParam:DWORD, lParam:DWORD

    WM_CREATE:
        SetTimer(33ms)    ; ~30 FPS
        InitAudio()

    WM_TIMER:
        UpdateAudio()     ; isi buffer audio yang sudah selesai
        RenderFrame()     ; gambar satu frame
        FrameCount++

    WM_PAINT:
        BeginPaint / EndPaint  ; validasi region saja
        ; rendering sebenarnya ada di WM_TIMER, bukan di sini

    WM_KEYDOWN (ESC):
        PostQuitMessage(0)

    WM_DESTROY:
        KillTimer()
        CleanupAudio()
        PostQuitMessage(0)
```

### Mengapa Rendering di WM_TIMER, bukan WM_PAINT?

`WM_PAINT` hanya dipanggil saat Windows memutuskan area perlu digambar ulang. Dengan `WM_TIMER`, kita mendapat **framerate yang konsisten** (~30 FPS) terlepas dari apakah Windows mengirim WM_PAINT atau tidak.

---

## 10. Cara Kompilasi & Menjalankan

### Langkah Kompilasi

```bat
REM Assembler: ubah .asm → .obj
\masm32\bin\ml.exe /c /coff /Zi demoscene.asm

REM Linker: ubah .obj → .exe
\masm32\bin\link.exe /subsystem:windows /debug demoscene.obj ^
    \masm32\lib\user32.lib ^
    \masm32\lib\kernel32.lib ^
    \masm32\lib\gdi32.lib ^
    \masm32\lib\winmm.lib
```

### Kontrol Program

| Tombol | Fungsi |
|---|---|
| **ESC** | Keluar dari program |
| Resize window | Plasma dan teks otomatis menyesuaikan ukuran |

---

## 11. Ringkasan Konsep Kunci

### Audio

| Konsep | Penjelasan |
|---|---|
| **8-bit unsigned PCM** | Sample 0..255, nilai 128 = silence |
| **Double buffering** | Dua buffer bergantian agar playback tidak putus |
| **Phase accumulator** | Cara efisien buat oscillator: `fase += frekuensi×65536/samplerate` |
| **LCG noise** | Pseudo-random number generator untuk snare/hihat: `state = state×1664525+1013904223` |
| **WHDR_DONE polling** | Cek flag ini untuk tahu kapan buffer selesai diputar |

### Visual

| Konsep | Penjelasan |
|---|---|
| **DIB (Device Independent Bitmap)** | Buffer pixel raw yang bisa diupload ke GDI dengan `SetDIBitsToDevice` |
| **StretchBlt + HALFTONE** | Stretch bitmap dengan anti-aliasing agar tidak terlihat kotak-kotak |
| **SetBkMode TRANSPARENT** | Teks tidak menutupi background dengan kotak putih |
| **Memory DC** | Off-screen canvas untuk menggambar sebelum ditampilkan ke layar |

### Assembly Tips

| Pola | Penjelasan |
|---|---|
| `shl eax, 16` lalu `div` | Ekuivalen operasi fixed-point 16.16 |
| `sar eax, 1` | Pembagian 2 yang benar untuk bilangan negatif (vs `shr`) |
| `imul` lalu `sar 8` | Perkalian fraksional: `× 13 / 256 ≈ / 20` |
| `cdq` sebelum `idiv` | Sign-extend EAX ke EDX:EAX wajib untuk division signed |

---

## 📚 Referensi Lanjutan

- [MASM32 Documentation](http://www.masm32.com/masmdoc.htm)
- [Windows waveOut API — MSDN](https://docs.microsoft.com/en-us/windows/win32/api/mmeapi/)
- [Plasma Effect — Lode's Computer Graphics Tutorial](https://lodev.org/cgtutor/plasma.html)
- [Demoscene History — Wikipedia](https://en.wikipedia.org/wiki/Demoscene)

---

*Tutorial ini dibuat untuk memahami teknik pemrograman low-level: synthesis audio dari nol, efek visual real-time, dan integrasi dengan Windows API menggunakan Assembly x86.*

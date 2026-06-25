; ============================================================
; Demoscene Art - Visual + Musik 4 Layer
; Layer: Melodi (triangle wave) + Bass (sawtooth) + Kick + Snare
; Target: MASM32, Windows 32-bit
; Audio : waveOut API polling (double buffer, 8-bit mono, 44100 Hz)
; Visual: plasma effect + scrolling text, GDI StretchBlt
; oleh Moh Rizal HP (MRHPx / mrhpx@yahoo.com).
; ============================================================

.386
.model flat, stdcall
option casemap:none

include \masm32\include\windows.inc
include \masm32\include\user32.inc
include \masm32\include\kernel32.inc
include \masm32\include\gdi32.inc

includelib \masm32\lib\user32.lib
includelib \masm32\lib\kernel32.lib
includelib \masm32\lib\gdi32.lib
includelib \masm32\lib\winmm.lib

; ============================================================
; waveOut API - dideklarasikan manual karena tidak pakai mmsystem.inc
; ============================================================
waveOutOpen             PROTO STDCALL :DWORD,:DWORD,:DWORD,:DWORD,:DWORD,:DWORD
waveOutClose            PROTO STDCALL :DWORD
waveOutPrepareHeader    PROTO STDCALL :DWORD,:DWORD,:DWORD
waveOutUnprepareHeader  PROTO STDCALL :DWORD,:DWORD,:DWORD
waveOutWrite            PROTO STDCALL :DWORD,:DWORD,:DWORD
waveOutReset            PROTO STDCALL :DWORD

; ============================================================
; Konstanta audio
; ============================================================
WAVE_MAPPER         equ 0FFFFFFFFh  ; biarkan sistem pilih device output
CALLBACK_NULL       equ 0           ; tidak pakai callback, pakai polling
MMSYSERR_NOERROR    equ 0
WHDR_DONE           equ 1           ; flag: buffer sudah selesai diputar
WAVE_FORMAT_PCM     equ 1

SAMPLE_RATE         equ 44100       ; Hz
BUFFER_SIZE         equ 4410        ; sampel per buffer = ~100ms
WAVEHDR_SIZE        equ 32          ; sizeof WAVEHDR (manual, tanpa struct)

; ----------------------------------------------------------
; Frekuensi not dalam Hz
; Penamaan: NOTE_<nama><oktaf>
; Oktaf rendah (1-2) untuk bass, menengah (3-4) untuk melodi/arp
; ----------------------------------------------------------
NOTE_REST equ 0     ; diam / tidak ada bunyi
NOTE_B2   equ 123
NOTE_C3   equ 131
NOTE_D3   equ 147
NOTE_E3   equ 165
NOTE_F3   equ 175
NOTE_G3   equ 196
NOTE_A3   equ 220
NOTE_B3   equ 247
NOTE_C4   equ 262
NOTE_D4   equ 294
NOTE_E4   equ 330
NOTE_F4   equ 349
NOTE_G4   equ 392
NOTE_A4   equ 440
NOTE_B4   equ 494
NOTE_C5   equ 523
NOTE_D5   equ 587
NOTE_E5   equ 659
NOTE_G5   equ 784
NOTE_A2   equ 110
NOTE_G2   equ 98
NOTE_E2   equ 82
NOTE_C1   equ 33
NOTE_CS1  equ 35
NOTE_DS1  equ 39
NOTE_F1   equ 44
NOTE_GS1  equ 52
NOTE_AS1  equ 58
NOTE_C2   equ 65
NOTE_CS2  equ 69
NOTE_DS2  equ 78
NOTE_F2   equ 87
NOTE_DS4  equ 311
NOTE_GS4  equ 415
NOTE_AS4  equ 466
NOTE_CS5  equ 554
NOTE_F5   equ 698

; ----------------------------------------------------------
; Durasi dalam satuan sampel (44100 Hz, BPM 120)
; 1 beat = 0.5 detik = 22050 sampel
; ----------------------------------------------------------
BEAT        equ 22050   ; 1 ketukan penuh
HALF_BEAT   equ 11025   ; 1/2 ketukan
QTR_BEAT    equ 5512    ; 1/4 ketukan
EIGHTH_BEAT equ 2756    ; 1/8 ketukan

; ----------------------------------------------------------
; Konstanta tipe drum untuk sequencer
; ----------------------------------------------------------
KICK_NOTE   equ 1   ; bass drum
SNARE_NOTE  equ 2   ; snare drum
HIHAT_NOTE  equ 3   ; hi-hat
KICK_SNARE  equ 4   ; kick + snare bersamaan (aksen kuat)

; ============================================================
; Data Section
; ============================================================
.data
    ; --- Window ---
    szClassName     db 'DemosceneClass',0
    szWindowName    db 'MRHPx Demoscene Art - MASM32',0
    szMessage       db 'WELCOME TO DEMOSCENE - PRESS ESC TO EXIT',0
    szFontName      db 'Arial',0

    hInst           dd 0
    hWndMain        dd 0
    hDCMem          dd 0    ; DC sementara untuk plasma buffer 320x240
    hDCMem2         dd 0    ; DC sementara untuk output akhir (full window size)
    hBitmap         dd 0    ; bitmap plasma 320x240
    hBitmap2        dd 0    ; bitmap output akhir
    hOldBitmap      dd 0    ; simpan bitmap lama hDCMem (untuk cleanup)
    hOldBitmap2     dd 0    ; simpan bitmap lama hDCMem2 (untuk cleanup)

    ; --- State rendering ---
    phase1          dd 0    ; fase horizontal plasma
    phase2          dd 0    ; fase vertikal plasma
    phase3          dd 0    ; fase cadangan (dipakai untuk efek tambahan)
    ScrollPos       dd 640  ; posisi X teks scrolling (mulai dari kanan)
    FrameCount      dd 0    ; penghitung frame, bisa dipakai untuk efek time-based
    TextHeight      dd 0    ; tinggi teks hasil GetTextExtentPoint32
    WinWidth        dd 640  ; lebar window saat ini
    WinHeight       dd 480  ; tinggi window saat ini

    ; --- GDI structs ---
    wc              WNDCLASSEX <>
    msg             MSG <>
    ps              PAINTSTRUCT <>
    rect            RECT <>

    ; --- Pixel buffer plasma (320x240 x 4 byte/pixel = 307200 byte) ---
    Buffer          db 307200 dup(0)

    ; --- Ukuran teks (lebar dan tinggi) dari GetTextExtentPoint32 ---
    ; Diakses sebagai szTextSize[0]=cx (lebar), szTextSize[4]=cy (tinggi)
    szTextSize      dd 0, 0

    ; ============================================================
    ; Audio - waveOut double buffer
    ; ============================================================
    hWaveOut            dd 0    ; handle device audio

    ; WAVEFORMATEX manual (8-bit, mono, 44100 Hz)
    WaveFmt_Tag         dw WAVE_FORMAT_PCM  ; format PCM
    WaveFmt_Ch          dw 1                ; mono
    WaveFmt_SPS         dd SAMPLE_RATE      ; samples per second
    WaveFmt_ABPS        dd SAMPLE_RATE      ; bytes per second (mono 8-bit = sama dengan SPS)
    WaveFmt_Align       dw 1                ; block align (mono 8-bit = 1 byte)
    WaveFmt_Bits        dw 8                ; bits per sample
    WaveFmt_cbSize      dw 0                ; tidak ada extra info

    ; --- Buffer audio (double buffering untuk playback seamless) ---
    AudioBuf1           db BUFFER_SIZE dup(128)  ; 128 = silence (unsigned 8-bit center)
    AudioBuf2           db BUFFER_SIZE dup(128)

    ; --- WAVEHDR untuk AudioBuf1 (manual layout, 8 field x 4 byte = 32 byte) ---
    WaveHdr1_lpData     dd offset AudioBuf1  ; pointer ke buffer data
    WaveHdr1_dwBufLen   dd BUFFER_SIZE       ; panjang buffer dalam byte
    WaveHdr1_dwBytesRec dd 0                 ; diisi driver saat recording (tidak dipakai)
    WaveHdr1_dwUser     dd 0                 ; user data bebas
    WaveHdr1_dwFlags    dd 0                 ; flags (WHDR_DONE diset driver saat selesai)
    WaveHdr1_dwLoops    dd 1                 ; loop count (1 = putar sekali)
    WaveHdr1_lpNext     dd 0                 ; pointer ke header berikutnya (tidak dipakai)
    WaveHdr1_reserved   dd 0                 ; reserved

    ; --- WAVEHDR untuk AudioBuf2 ---
    WaveHdr2_lpData     dd offset AudioBuf2
    WaveHdr2_dwBufLen   dd BUFFER_SIZE
    WaveHdr2_dwBytesRec dd 0
    WaveHdr2_dwUser     dd 0
    WaveHdr2_dwFlags    dd 0
    WaveHdr2_dwLoops    dd 1
    WaveHdr2_lpNext     dd 0
    WaveHdr2_reserved   dd 0

    ; ============================================================
    ; State tiap layer synthesizer
    ; ============================================================

    ; --- Melodi: triangle wave, lebih lembut dari square ---
    MelPhase        dd 0            ; akumulator fase (16.16 fixed-point, bit atas = fase)
    MelIndex        dd 0            ; indeks note saat ini di MelodyData
    MelSampLeft     dd 0            ; sisa sampel untuk note saat ini
    MelCurFreq      dd NOTE_REST    ; frekuensi note saat ini (Hz)

    ; --- Bass: sawtooth wave, hangat dan gemuk ---
    BassPhase       dd 0
    BassIndex       dd 0
    BassSampLeft    dd 0
    BassCurFreq     dd NOTE_REST

    ; --- Arpeggio: square wave volume rendah, sebagai "chord shimmer" ---
    ArpPhase        dd 0
    ArpIndex        dd 0
    ArpSampLeft     dd 0
    ArpCurFreq      dd NOTE_REST

    ; --- Drum: envelope-based synthesis (tidak ada phase oscillator permanen) ---
    DrumIndex       dd 0            ; indeks event saat ini di DrumData
    DrumSampLeft    dd 0            ; sisa sampel untuk event drum saat ini
    DrumCurType     dd 0            ; tipe drum saat ini (0=rest, 1=kick, dll)

    ; --- Envelope drum (countdown dari nilai awal, turun ke 0 = habis) ---
    KickEnv         dd 0    ; envelope kick (juga menentukan pitch sweep)
    SnareEnv        dd 0    ; envelope snare
    HihatEnv        dd 0    ; envelope hi-hat
    KickPhase       dd 0    ; akumulator fase oscillator kick (untuk pitch sweep)
    NoiseState      dd 12345h   ; state LCG random number generator (untuk snare/hihat)

    ; ============================================================
    ; SEKUENS MELODI
    ; Lagu bernuansa "Axel F" dalam minor scale, gaya demoscene
    ; Format pasangan: frekuensi (Hz), durasi (sampel)
    ; Sentinel: 0FFFFFFFFh -> loop kembali ke awal
    ; ============================================================
    MelodyData  dd NOTE_F4,  BEAT
                dd NOTE_GS4, HALF_BEAT
                dd NOTE_GS4, QTR_BEAT
                dd NOTE_F4,  HALF_BEAT
                dd NOTE_F4,  QTR_BEAT
                dd NOTE_AS4, HALF_BEAT
                dd NOTE_F4,  HALF_BEAT
                dd NOTE_DS4, HALF_BEAT
                dd NOTE_F4,  BEAT
                dd NOTE_C5,  HALF_BEAT
                dd NOTE_C5,  QTR_BEAT
                dd NOTE_F4,  HALF_BEAT
                dd NOTE_F4,  QTR_BEAT
                dd NOTE_CS5, HALF_BEAT
                dd NOTE_C5,  HALF_BEAT
                dd NOTE_GS4, HALF_BEAT
                dd NOTE_F4,  HALF_BEAT
                dd NOTE_C5,  HALF_BEAT
                dd NOTE_F5,  HALF_BEAT
                dd NOTE_F4,  QTR_BEAT
                dd NOTE_DS4, HALF_BEAT
                dd NOTE_DS4, QTR_BEAT
                dd NOTE_C4,  HALF_BEAT
                dd NOTE_G4,  HALF_BEAT
                dd NOTE_F4,  BEAT
                dd NOTE_F4,  BEAT
                dd NOTE_F4,  HALF_BEAT
                dd NOTE_REST, BEAT
                dd NOTE_REST, BEAT
                dd 0FFFFFFFFh, 0    ; sentinel: ulangi dari awal

    ; ============================================================
    ; SEKUENS BASS
    ; Root + fifth pattern, sinkron secara ritmis dengan melodi
    ; ============================================================
    BassData    dd NOTE_F2,  BEAT
                dd NOTE_F3,  HALF_BEAT
                dd NOTE_F3,  QTR_BEAT
                dd NOTE_DS1, HALF_BEAT
                dd NOTE_DS2, QTR_BEAT
                dd NOTE_C2,  HALF_BEAT
                dd NOTE_C3,  HALF_BEAT
                dd NOTE_DS2, HALF_BEAT
                dd NOTE_F2,  BEAT
                dd NOTE_F3,  BEAT
                dd NOTE_F3,  QTR_BEAT
                dd NOTE_C2,  QTR_BEAT
                dd NOTE_C3,  HALF_BEAT
                dd NOTE_DS2, HALF_BEAT
                dd NOTE_F3,  HALF_BEAT
                dd NOTE_CS1, BEAT
                dd NOTE_CS2, HALF_BEAT
                dd NOTE_CS2, QTR_BEAT
                dd NOTE_DS1, HALF_BEAT
                dd NOTE_DS2, QTR_BEAT
                dd NOTE_C2,  HALF_BEAT
                dd NOTE_DS1, HALF_BEAT
                dd NOTE_F2,  HALF_BEAT
                dd NOTE_F3,  BEAT
                dd NOTE_F3,  BEAT
                dd NOTE_F3,  QTR_BEAT
                dd NOTE_DS2, QTR_BEAT
                dd NOTE_C3,  HALF_BEAT
                dd NOTE_AS1, HALF_BEAT
                dd NOTE_GS1, HALF_BEAT
                dd 0FFFFFFFFh, 0    ; sentinel: ulangi dari awal

    ; ============================================================
    ; SEKUENS ARPEGGIO
    ; Chord shimmer Am - Dm - E - Am (satu oktaf di atas melodi)
    ; ============================================================
    ArpData     dd NOTE_F4,  BEAT
                dd NOTE_GS4, HALF_BEAT
                dd NOTE_GS4, QTR_BEAT
                dd NOTE_F4,  HALF_BEAT
                dd NOTE_F4,  QTR_BEAT
                dd NOTE_AS4, HALF_BEAT
                dd NOTE_F4,  HALF_BEAT
                dd NOTE_DS4, HALF_BEAT
                dd NOTE_F4,  BEAT
                dd NOTE_C5,  HALF_BEAT
                dd NOTE_C5,  QTR_BEAT
                dd NOTE_F4,  HALF_BEAT
                dd NOTE_F4,  QTR_BEAT
                dd NOTE_CS5, HALF_BEAT
                dd NOTE_C5,  HALF_BEAT
                dd NOTE_GS4, HALF_BEAT
                dd NOTE_F4,  HALF_BEAT
                dd NOTE_C5,  HALF_BEAT
                dd NOTE_F5,  HALF_BEAT
                dd NOTE_F4,  QTR_BEAT
                dd NOTE_DS4, HALF_BEAT
                dd NOTE_DS4, QTR_BEAT
                dd NOTE_C4,  HALF_BEAT
                dd NOTE_G4,  HALF_BEAT
                dd NOTE_F4,  BEAT
                dd NOTE_F4,  BEAT
                dd NOTE_F4,  HALF_BEAT
                dd NOTE_REST, BEAT
                dd NOTE_REST, BEAT
                dd 0FFFFFFFFh, 0    ; sentinel: ulangi dari awal

    ; ============================================================
    ; POLA DRUM
    ; Format pasangan: tipe_drum, durasi (sampel)
    ; Setiap event drum baru men-trigger envelope baru
    ; Sentinel: 0FFFFFFFFh -> loop kembali ke awal
    ; ============================================================
    DrumData    dd KICK_SNARE,  QTR_BEAT    ; aksen pembuka (kick+snare serentak)
                dd SNARE_NOTE,  QTR_BEAT
                dd SNARE_NOTE,  QTR_BEAT
                dd HIHAT_NOTE,  QTR_BEAT
                dd SNARE_NOTE,  QTR_BEAT
                dd HIHAT_NOTE,  QTR_BEAT
                dd HIHAT_NOTE,  QTR_BEAT
                dd HIHAT_NOTE,  QTR_BEAT
                dd HIHAT_NOTE,  QTR_BEAT
                dd KICK_NOTE,   QTR_BEAT
                dd KICK_NOTE,   QTR_BEAT
                dd HIHAT_NOTE,  QTR_BEAT
                dd KICK_SNARE,  QTR_BEAT
                dd HIHAT_NOTE,  QTR_BEAT
                dd KICK_NOTE,   QTR_BEAT
                dd HIHAT_NOTE,  HALF_BEAT   ; hihat lebih panjang = 1/2 beat
                dd HIHAT_NOTE,  QTR_BEAT
                dd HIHAT_NOTE,  QTR_BEAT
                dd HIHAT_NOTE,  QTR_BEAT
                dd SNARE_NOTE,  QTR_BEAT
                dd HIHAT_NOTE,  QTR_BEAT
                dd HIHAT_NOTE,  QTR_BEAT
                dd HIHAT_NOTE,  QTR_BEAT
                dd HIHAT_NOTE,  QTR_BEAT
                dd KICK_NOTE,   QTR_BEAT
                dd KICK_NOTE,   QTR_BEAT
                dd HIHAT_NOTE,  QTR_BEAT
                dd SNARE_NOTE,  QTR_BEAT
                dd HIHAT_NOTE,  QTR_BEAT
                dd HIHAT_NOTE,  QTR_BEAT
                dd HIHAT_NOTE,  QTR_BEAT
                dd KICK_NOTE,   QTR_BEAT
                dd HIHAT_NOTE,  QTR_BEAT
                dd HIHAT_NOTE,  QTR_BEAT
                dd HIHAT_NOTE,  QTR_BEAT
                dd SNARE_NOTE,  QTR_BEAT
                dd HIHAT_NOTE,  QTR_BEAT
                dd HIHAT_NOTE,  QTR_BEAT
                dd KICK_NOTE,   QTR_BEAT
                dd HIHAT_NOTE,  QTR_BEAT
                dd KICK_NOTE,   QTR_BEAT
                dd KICK_NOTE,   QTR_BEAT
                dd HIHAT_NOTE,  QTR_BEAT
                dd KICK_SNARE,  QTR_BEAT
                dd HIHAT_NOTE,  QTR_BEAT
                dd KICK_NOTE,   QTR_BEAT
                dd HIHAT_NOTE,  QTR_BEAT
                dd KICK_NOTE,   QTR_BEAT
                dd HIHAT_NOTE,  QTR_BEAT
                dd HIHAT_NOTE,  QTR_BEAT
                dd HIHAT_NOTE,  QTR_BEAT
                dd SNARE_NOTE,  QTR_BEAT
                dd HIHAT_NOTE,  QTR_BEAT
                dd HIHAT_NOTE,  QTR_BEAT
                dd HIHAT_NOTE,  QTR_BEAT
                dd HIHAT_NOTE,  QTR_BEAT
                dd KICK_SNARE,  QTR_BEAT
                dd KICK_NOTE,   QTR_BEAT
                dd SNARE_NOTE,  QTR_BEAT
                dd KICK_SNARE,  QTR_BEAT    ; fill akhir: serentetan aksen
                dd SNARE_NOTE,  QTR_BEAT
                dd KICK_SNARE,  QTR_BEAT
                dd SNARE_NOTE,  QTR_BEAT
                dd 0FFFFFFFFh, 0            ; sentinel: ulangi dari awal


; ============================================================
; Code Section
; ============================================================
.code

; ============================================================
; SynthTriangle
; Menghasilkan 1 sampel triangle wave untuk layer melodi.
; Triangle wave lebih lembut dari square (tidak ada harmonik genap).
;
; Input : EAX = frekuensi (Hz), 0 = REST (diam)
;         EDI = pointer ke DWORD akumulator fase (diubah oleh fungsi)
; Output: AL  = sampel 8-bit unsigned (range 78..178, amplitudo +/-50)
;
; Algoritma fase:
;   phase_increment = freq * 65536 / SAMPLE_RATE  (16-bit per siklus)
;   fase diakumulasi di [EDI], bit 8-15 dipakai sebagai fase 0..255
;   - fase 0..127  -> naik dari 78 ke 178
;   - fase 128..255 -> turun dari 178 ke 78
; ============================================================
SynthTriangle proc
    cmp eax, NOTE_REST          ; cek apakah ini note diam
    jne ST_play
    mov al, 128                 ; output DC (tengah, tidak ada sinyal)
    ret
ST_play:
    push edx
    push ebx
    ; Hitung phase increment = freq * 65536 / SAMPLE_RATE
    shl eax, 16                 ; freq * 65536
    xor edx, edx
    mov ebx, SAMPLE_RATE
    div ebx                     ; EAX = increment per sampel
    add [edi], eax              ; akumulasi fase
    mov eax, [edi]
    shr eax, 8                  ; ambil bit 8-15 sebagai fase 0..255
    pop ebx
    pop edx

    ; Bentuk triangle: naik di fase 0..127, turun di fase 128..255
    cmp eax, 128
    jl  ST_rising               ; fase bawah: nilai sudah benar (0..127)
    ; Fase atas (128..255): lipat balik menjadi 127..0
    neg eax
    add eax, 255                ; 255 - eax -> 0..127

ST_rising:
    ; EAX = 0..127, petakan ke rentang output 78..178
    ; Formula: 78 + eax * 100 / 127
    imul eax, 100
    xor edx, edx
    push ebx
    mov ebx, 127
    div ebx
    pop ebx
    add eax, 78                 ; geser ke 78..178
    ; AL sudah berisi 8-bit bawah dari EAX (range 78..178 masuk dalam AL)
    ret
SynthTriangle endp

; ============================================================
; SynthSaw
; Menghasilkan 1 sampel sawtooth wave untuk layer bass.
; Sawtooth mengandung semua harmonik -> suara gemuk dan hangat.
;
; Input : EAX = frekuensi (Hz), 0 = REST
;         EDI = pointer ke DWORD akumulator fase
; Output: AL  = sampel 8-bit unsigned (range 68..188, amplitudo +/-60)
;
; Sawtooth: fase 0..255 langsung dipetakan linear ke output 68..188
; ============================================================
SynthSaw proc
    cmp eax, NOTE_REST
    jne SS_play
    mov al, 128                 ; output DC (diam)
    ret
SS_play:
    push edx
    push ebx
    ; Hitung phase increment dan akumulasi (sama seperti SynthTriangle)
    shl eax, 16
    xor edx, edx
    mov ebx, SAMPLE_RATE
    div ebx
    add [edi], eax
    mov eax, [edi]
    shr eax, 8                  ; fase 0..255
    pop ebx
    pop edx

    ; Sawtooth linear: petakan 0..255 -> 68..188 (amplitudo +/-60)
    ; Formula: 68 + eax * 120 / 255
    imul eax, 120
    xor edx, edx
    push ebx
    mov ebx, 255
    div ebx
    pop ebx
    add eax, 68                 ; geser ke 68..188
    ; AL berisi hasil 8-bit (68..188 masuk dalam AL)
    ret
SynthSaw endp

; ============================================================
; SynthSquareSoft
; Menghasilkan 1 sampel square wave volume rendah untuk layer arpeggio.
; Dipakai sebagai "chord shimmer" - suara tipis di latar belakang.
;
; Input : EAX = frekuensi (Hz), 0 = REST
;         EDI = pointer ke DWORD akumulator fase
; Output: AL  = sampel 8-bit unsigned (103 atau 153, amplitudo +/-25)
;
; Square wave: output hanya dua nilai (high/low), duty cycle 50%
; Volume sengaja dikecilkan (+/-25 dari tengah 128) agar tidak mendominasi
; ============================================================
SynthSquareSoft proc
    cmp eax, NOTE_REST
    jne SQS_play
    mov al, 128                 ; output DC (diam)
    ret
SQS_play:
    push edx
    push ebx
    ; Hitung phase increment dan akumulasi
    shl eax, 16
    xor edx, edx
    mov ebx, SAMPLE_RATE
    div ebx
    add [edi], eax
    mov eax, [edi]
    shr eax, 8                  ; fase 0..255
    pop ebx
    pop edx

    ; Fase 0..127 -> high (128+25=153), fase 128..255 -> low (128-25=103)
    cmp eax, 128
    jl  SQS_hi
    mov al, 103                 ; low: 128 - 25
    ret
SQS_hi:
    mov al, 153                 ; high: 128 + 25
    ret
SynthSquareSoft endp

; ============================================================
; GetNextSample_Drum
; Menghasilkan 1 sampel campuran semua layer drum yang aktif.
; Setiap drum dimodelkan dengan envelope (amplitudo turun cepat)
; tanpa oscillator permanen - cukup untuk suara perkusif.
;
; Output: EBX = sampel signed (-128..127), sebelum di-mix ke output utama
;
; Drum yang didukung:
;   Kick  : square wave dengan pitch sweep (frekuensi turun seiring env)
;   Snare : white noise dengan envelope (LCG noise)
;   Hihat : white noise frekuensi lebih tinggi, sangat pendek
; Beberapa drum bisa aktif bersamaan (misalnya KICK_SNARE).
; ============================================================
GetNextSample_Drum proc
    xor ebx, ebx    ; akumulasi output drum, mulai dari 0 (silence)

    ; ============================================================
    ; --- KICK DRUM ---
    ; Simulasi "bass drum" dengan square wave ber-pitch-sweep:
    ; frekuensi efektif = KickEnv / 10, mulai ~300Hz, turun ke 20Hz
    ; KickEnv dimulai dari 3000 dan berkurang 3 per sampel
    ; ============================================================
    cmp KickEnv, 0
    je  Drum_checkSnare         ; lewati jika kick tidak aktif

    mov eax, KickEnv
    mov ecx, 10
    xor edx, edx
    div ecx                     ; EAX = frekuensi efektif saat ini (sweep turun)
    cmp eax, 20
    jge Kick_synth
    mov eax, 20                 ; batas bawah frekuensi agar tidak jadi DC
Kick_synth:
    ; Osilasi square wave dengan frekuensi yang sedang sweep turun
    push edi
    mov edi, offset KickPhase
    shl eax, 16
    xor edx, edx
    push ecx
    mov ecx, SAMPLE_RATE
    div ecx                     ; EAX = phase increment
    add [edi], eax              ; akumulasi fase kick
    mov eax, [edi]
    shr eax, 8                  ; fase 0..255
    pop ecx
    pop edi

    ; Output square wave kick: +90 atau -90
    cmp eax, 128
    jl  Kick_hi
    mov eax, -90                ; fase atas -> nilai negatif
    jmp Kick_env
Kick_hi:
    mov eax, 90                 ; fase bawah -> nilai positif
Kick_env:
    ; Terapkan envelope: skala output dengan KickEnv/3000
    ; Semakin kecil KickEnv, semakin kecil amplitudo (fade out alami)
    imul eax, KickEnv           ; EAX = output * envelope
    mov ecx, 3000               ; nilai envelope maksimum
    cdq                         ; sign-extend EAX ke EDX:EAX untuk idiv
    idiv ecx                    ; EAX = output yang sudah di-scale
    add ebx, eax                ; tambahkan ke akumulasi drum

    ; Decay: kurangi envelope 3 per sampel -> kick habis dalam ~1000 sampel (~23ms)
    sub KickEnv, 3
    jns Drum_checkSnare         ; lanjut jika belum negatif
    mov KickEnv, 0              ; clamp ke 0 (tidak boleh negatif)

Drum_checkSnare:
    ; ============================================================
    ; --- SNARE DRUM ---
    ; White noise dengan envelope: suara "crack" percussive
    ; Noise dari LCG (Linear Congruential Generator)
    ; SnareEnv dimulai dari 2500, berkurang 10 per sampel
    ; ============================================================
    cmp SnareEnv, 0
    je  Drum_checkHihat         ; lewati jika snare tidak aktif

    ; Generate sample noise dengan LCG: state = state * 1664525 + 1013904223
    mov eax, NoiseState
    imul eax, 1664525
    add eax, 1013904223
    mov NoiseState, eax         ; simpan state baru untuk sampel berikutnya

    ; Ambil bit 16..21 sebagai nilai noise (-32..31)
    shr eax, 16
    and eax, 63                 ; 0..63
    sub eax, 32                 ; -32..31 (signed noise)

    ; Terapkan envelope: skala dengan SnareEnv/2500
    imul eax, SnareEnv
    mov ecx, 2500
    cdq                         ; sign-extend untuk idiv
    idiv ecx
    add ebx, eax                ; tambahkan ke akumulasi drum

    ; Decay snare lebih cepat dari kick (10 per sampel -> habis dalam ~250 sampel)
    sub SnareEnv, 10
    jns Drum_checkHihat
    mov SnareEnv, 0

Drum_checkHihat:
    ; ============================================================
    ; --- HI-HAT ---
    ; White noise sangat pendek dan pelan: suara "tick" tipis
    ; LCG berbeda dari snare (multiplier 22695477) untuk variasi warna noise
    ; HihatEnv dimulai dari 800, berkurang 30 per sampel
    ; ============================================================
    cmp HihatEnv, 0
    je  Drum_done               ; lewati jika hihat tidak aktif

    ; Generate noise hi-hat dengan multiplier LCG berbeda
    mov eax, NoiseState
    imul eax, 22695477
    add eax, 1
    mov NoiseState, eax         ; update state (dipakai bersama snare, intensional)

    ; Ambil bit 16..20 sebagai noise (-15..15) - lebih kecil dari snare
    shr eax, 16
    and eax, 31                 ; 0..31
    sub eax, 15                 ; -15..15

    ; Hihat sangat pelan: skala dengan HihatEnv/800
    imul eax, HihatEnv
    mov ecx, 800
    cdq
    idiv ecx
    add ebx, eax                ; tambahkan ke akumulasi drum

    ; Decay sangat cepat (30 per sampel -> habis dalam ~27 sampel = 0.6ms)
    sub HihatEnv, 30
    jns Drum_done
    mov HihatEnv, 0

Drum_done:
    ; Clamp output drum ke -100..100 untuk mencegah clipping ekstrem
    cmp ebx, 100
    jle Drum_clampLo
    mov ebx, 100
Drum_clampLo:
    cmp ebx, -100
    jge Drum_ret
    mov ebx, -100
Drum_ret:
    ret
GetNextSample_Drum endp

; ============================================================
; AdvanceSequencer
; Memajukan semua sequencer (melodi, bass, arp, drum) sebesar 1 sampel.
; Dipanggil sekali per sampel dari FillAudioBuffer.
;
; Cara kerja:
;   - Jika sisa sampel note/event = 0, muat note/event berikutnya dari data
;   - Jika sentinel (0FFFFFFFFh) ditemukan, ulangi dari indeks 0
;   - Kurangi sisa sampel sebesar 1
; ============================================================
AdvanceSequencer proc

    ; --- MELODI ---
AdvMel:
    cmp MelSampLeft, 0          ; apakah note saat ini sudah habis?
    jne AdvMelDone
    ; Muat note berikutnya: alamat = MelIndex * 8 + offset MelodyData
    ; (setiap entry = 2 DWORD = 8 byte)
    mov eax, MelIndex
    shl eax, 3                  ; * 8
    add eax, offset MelodyData
    mov ecx, [eax]              ; baca frekuensi
    cmp ecx, 0FFFFFFFFh         ; sentinel = akhir sekuens?
    jne AdvMelLoad
    mov MelIndex, 0             ; reset ke awal, lalu coba lagi
    jmp AdvMel
AdvMelLoad:
    mov MelCurFreq, ecx         ; set frekuensi aktif
    mov ecx, [eax+4]            ; baca durasi (sampel)
    mov MelSampLeft, ecx        ; set sisa durasi
    inc MelIndex                ; maju ke note berikutnya
AdvMelDone:
    dec MelSampLeft             ; hitung mundur durasi note

    ; --- BASS ---
AdvBass:
    cmp BassSampLeft, 0
    jne AdvBassDone
    mov eax, BassIndex
    shl eax, 3
    add eax, offset BassData
    mov ecx, [eax]
    cmp ecx, 0FFFFFFFFh
    jne AdvBassLoad
    mov BassIndex, 0
    jmp AdvBass
AdvBassLoad:
    mov BassCurFreq, ecx
    mov ecx, [eax+4]
    mov BassSampLeft, ecx
    inc BassIndex
AdvBassDone:
    dec BassSampLeft

    ; --- ARPEGGIO ---
AdvArp:
    cmp ArpSampLeft, 0
    jne AdvArpDone
    mov eax, ArpIndex
    shl eax, 3
    add eax, offset ArpData
    mov ecx, [eax]
    cmp ecx, 0FFFFFFFFh
    jne AdvArpLoad
    mov ArpIndex, 0
    jmp AdvArp
AdvArpLoad:
    mov ArpCurFreq, ecx
    mov ecx, [eax+4]
    mov ArpSampLeft, ecx
    inc ArpIndex
AdvArpDone:
    dec ArpSampLeft

    ; --- DRUM ---
AdvDrum:
    cmp DrumSampLeft, 0
    jne AdvDrumDone
    mov eax, DrumIndex
    shl eax, 3
    add eax, offset DrumData
    mov ecx, [eax]              ; baca tipe drum
    cmp ecx, 0FFFFFFFFh
    jne AdvDrumLoad
    mov DrumIndex, 0
    jmp AdvDrum
AdvDrumLoad:
    mov DrumCurType, ecx
    ; Trigger envelope sesuai tipe drum (envelope lama langsung ditimpa)
    cmp ecx, KICK_NOTE
    jne AdvDrum_chkSnare
    mov KickEnv, 3000           ; kick: envelope mulai dari 3000
    mov KickPhase, 0            ; reset fase oscillator kick
    jmp AdvDrum_loadDur
AdvDrum_chkSnare:
    cmp ecx, SNARE_NOTE
    jne AdvDrum_chkHihat
    mov SnareEnv, 2500          ; snare: envelope mulai dari 2500
    jmp AdvDrum_loadDur
AdvDrum_chkHihat:
    cmp ecx, HIHAT_NOTE
    jne AdvDrum_chkKS
    mov HihatEnv, 800           ; hihat: envelope mulai dari 800 (sangat pendek)
    jmp AdvDrum_loadDur
AdvDrum_chkKS:
    cmp ecx, KICK_SNARE
    jne AdvDrum_loadDur
    ; KICK_SNARE: trigger keduanya serentak (pukulan aksen/rimshot)
    mov KickEnv, 3000
    mov KickPhase, 0
    mov SnareEnv, 2500
AdvDrum_loadDur:
    mov ecx, [eax+4]            ; baca durasi event drum
    mov DrumSampLeft, ecx
    inc DrumIndex
AdvDrumDone:
    dec DrumSampLeft

    ret
AdvanceSequencer endp

; ============================================================
; FillAudioBuffer
; Mengisi buffer audio dengan campuran semua 4 layer synth.
; Dipanggil setiap kali satu buffer selesai diputar (polling dari UpdateAudio).
;
; Input : ESI = pointer ke buffer output (byte, 8-bit unsigned PCM)
;         ECX = jumlah sampel yang harus diisi
;
; Mixing:
;   output = (mel*5 + bass*6 + arp*2 + drum*7) * 13 >> 8
;   Bobot: drum paling kuat, bass sedang, melodi jelas, arp halus
;   Faktor 13/256 ≈ 1/19.7 (aproksimasi pembagi 20 untuk normalisasi)
;   Soft limiter: clamp ke -110..110 sebelum konversi ke unsigned
; ============================================================
FillAudioBuffer proc uses esi edi ebx ecx edx
    LOCAL samplesToGo:DWORD
    mov samplesToGo, ecx        ; simpan jumlah sampel yang harus diproses

FillLoop:
    cmp samplesToGo, 0
    je  FillDone

    ; Majukan semua sequencer 1 sampel (update note/drum aktif)
    call AdvanceSequencer

    ; --- Layer 1: Melodi (triangle wave) ---
    mov eax, MelCurFreq
    mov edi, offset MelPhase
    call SynthTriangle
    movzx ebx, al               ; EBX = sampel unsigned 8-bit
    sub ebx, 128                ; konversi ke signed (-128..127)

    ; --- Layer 2: Bass (sawtooth wave) ---
    mov eax, BassCurFreq
    mov edi, offset BassPhase
    call SynthSaw
    movzx ecx, al               ; ECX = sampel bass signed
    sub ecx, 128

    ; --- Layer 3: Arpeggio (soft square wave) ---
    mov eax, ArpCurFreq
    mov edi, offset ArpPhase
    call SynthSquareSoft
    movzx edx, al               ; EDX = sampel arpeggio signed
    sub edx, 128

    ; --- Layer 4: Drum ---
    ; Simpan ketiga layer synth ke stack karena GetNextSample_Drum clobber EBX
    push ebx                    ; simpan melodi
    push ecx                    ; simpan bass
    push edx                    ; simpan arpeggio
    call GetNextSample_Drum     ; EBX = sampel drum signed (-100..100)
    mov eax, ebx                ; EAX = drum (pindahkan sebelum pop)
    pop edx                     ; restore arpeggio
    pop ecx                     ; restore bass
    pop ebx                     ; restore melodi

    ; --- Mixing 4 layer dengan bobot berbeda ---
    ; Formula: (mel*5 + bass*6 + arp*2 + drum*7) * 13 / 256
    ; Pembagi 13/256 ≈ 1/19.7 mendekati 1/(5+6+2+7)=1/20 (normalisasi)
    push eax                    ; simpan drum sementara
    imul ebx, 5                 ; melodi: bobot 5 (jelas tapi tidak mendominasi)
    imul ecx, 6                 ; bass: bobot 6 (sedikit lebih kuat dari melodi)
    imul edx, 2                 ; arpeggio: bobot 2 (sangat latar, hanya shimmer)
    pop eax
    imul eax, 7                 ; drum: bobot 7 (paling dominan, rhythmic punch)
    add ebx, ecx                ; akumulasi semua layer
    add ebx, edx
    add ebx, eax
    ; Normalisasi: *13/256 ≈ /20 (aproksimasi bit-shift, lebih cepat dari div)
    imul ebx, 13
    sar ebx, 8                  ; arithmetic shift right 8 = bagi 256

    ; Soft limiter: clamp ke -110..110 (headroom untuk mencegah hard clipping)
    cmp ebx, 110
    jle MixOK_hi
    mov ebx, 110
MixOK_hi:
    cmp ebx, -110
    jge MixOK_lo
    mov ebx, -110
MixOK_lo:
    ; Konversi dari signed ke unsigned 8-bit (tambah 128 = geser ke 0..255)
    add ebx, 128
    mov [esi], bl               ; tulis 1 sampel ke buffer
    inc esi                     ; maju ke sampel berikutnya

    dec samplesToGo
    jmp FillLoop

FillDone:
    ret
FillAudioBuffer endp

; ============================================================
; InitAudio
; Membuka device waveOut dan mengisi kedua buffer awal,
; lalu langsung memulai pemutaran (double buffering).
; ============================================================
InitAudio proc
    ; Buka device audio default (WAVE_MAPPER = sistem pilih sendiri)
    invoke waveOutOpen, addr hWaveOut, WAVE_MAPPER,
           addr WaveFmt_Tag, 0, 0, CALLBACK_NULL
    cmp eax, MMSYSERR_NOERROR
    jne InitAudio_fail          ; gagal membuka device, lewati saja

    ; Isi buffer pertama dan kedua sebelum mulai playback
    mov esi, offset AudioBuf1
    mov ecx, BUFFER_SIZE
    call FillAudioBuffer

    mov esi, offset AudioBuf2
    mov ecx, BUFFER_SIZE
    call FillAudioBuffer

    ; Prepare dan submit kedua buffer ke driver audio
    ; Driver akan memutar keduanya secara berurutan
    invoke waveOutPrepareHeader, hWaveOut, addr WaveHdr1_lpData, WAVEHDR_SIZE
    invoke waveOutWrite,         hWaveOut, addr WaveHdr1_lpData, WAVEHDR_SIZE
    invoke waveOutPrepareHeader, hWaveOut, addr WaveHdr2_lpData, WAVEHDR_SIZE
    invoke waveOutWrite,         hWaveOut, addr WaveHdr2_lpData, WAVEHDR_SIZE

InitAudio_fail:
    ret
InitAudio endp

; ============================================================
; UpdateAudio
; Polling double buffer: cek apakah ada buffer yang sudah selesai
; diputar (WHDR_DONE), lalu isi ulang dan submit kembali.
; Dipanggil dari WM_TIMER (~30fps), memastikan audio tidak putus.
; ============================================================
UpdateAudio proc
    cmp hWaveOut, 0
    je  UA_done                 ; audio tidak terinisialisasi, lewati

    ; Cek buffer 1
    mov eax, WaveHdr1_dwFlags
    test eax, WHDR_DONE         ; apakah driver sudah selesai pakai buffer ini?
    jz  UA_chk2                 ; belum selesai, cek buffer 2

    ; Buffer 1 selesai: unregister, isi ulang, submit kembali
    invoke waveOutUnprepareHeader, hWaveOut, addr WaveHdr1_lpData, WAVEHDR_SIZE
    and  WaveHdr1_dwFlags, NOT WHDR_DONE    ; bersihkan flag DONE
    mov esi, offset AudioBuf1
    mov ecx, BUFFER_SIZE
    call FillAudioBuffer        ; isi dengan audio baru
    invoke waveOutPrepareHeader, hWaveOut, addr WaveHdr1_lpData, WAVEHDR_SIZE
    invoke waveOutWrite,         hWaveOut, addr WaveHdr1_lpData, WAVEHDR_SIZE

UA_chk2:
    ; Cek buffer 2
    mov eax, WaveHdr2_dwFlags
    test eax, WHDR_DONE
    jz  UA_done

    ; Buffer 2 selesai: unregister, isi ulang, submit kembali
    invoke waveOutUnprepareHeader, hWaveOut, addr WaveHdr2_lpData, WAVEHDR_SIZE
    and  WaveHdr2_dwFlags, NOT WHDR_DONE
    mov esi, offset AudioBuf2
    mov ecx, BUFFER_SIZE
    call FillAudioBuffer
    invoke waveOutPrepareHeader, hWaveOut, addr WaveHdr2_lpData, WAVEHDR_SIZE
    invoke waveOutWrite,         hWaveOut, addr WaveHdr2_lpData, WAVEHDR_SIZE

UA_done:
    ret
UpdateAudio endp

; ============================================================
; CleanupAudio
; Hentikan playback, unregister semua buffer, dan tutup device.
; Dipanggil saat WM_DESTROY.
; ============================================================
CleanupAudio proc
    cmp hWaveOut, 0
    je  CA_done                 ; tidak ada device yang terbuka
    invoke waveOutReset, hWaveOut   ; hentikan semua playback, set semua header DONE
    ; Unregister kedua header (aman dipanggil setelah waveOutReset)
    invoke waveOutUnprepareHeader, hWaveOut, addr WaveHdr1_lpData, WAVEHDR_SIZE
    invoke waveOutUnprepareHeader, hWaveOut, addr WaveHdr2_lpData, WAVEHDR_SIZE
    invoke waveOutClose, hWaveOut
    mov hWaveOut, 0             ; tandai sudah ditutup
CA_done:
    ret
CleanupAudio endp

; ============================================================
; RenderPlasma
; Menghasilkan efek plasma psychedelic ke Buffer (320x240 x 4 byte).
;
; Algoritma (3 gelombang superposisi):
;   wave1 = px/2 + phase1                         (gelombang horizontal)
;   wave2 = py/2 + phase2                         (gelombang vertikal)
;   wave3 = (px + py) / 4 + phase3               (gelombang diagonal)
;   val   = (wave1 + wave2 + wave3) AND 255       (interferensi, mod 256)
;
; PENTING: AND 255 dilakukan SETELAH semua penjumlahan, bukan di tengah.
; Melakukan AND 255 sebelum penjumlahan memotong nilai prematur dan
; menghasilkan stripe diagonal tajam (bukan plasma). Interferensi yang
; sesungguhnya hanya terjadi jika nilai mentah dibiarkan overflow bebas
; sebelum diambil mod 256 di akhir.
;
; Tiga gelombang dengan arah berbeda menghasilkan pola interferensi
; yang lebih kompleks dan organik - inilah ciri khas plasma demoscene.
;
; Warna: tiga channel dengan offset 1/3 siklus (0, 85, 170) agar
; setiap region punya warna berbeda dan transisi smooth.
;
; Setiap frame: phase1+=2, phase2+=3, phase3+=1 -> animasi bergerak
; ============================================================
RenderPlasma proc
    LOCAL px:DWORD, py:DWORD, val:DWORD
    mov esi, offset Buffer      ; pointer tulis ke buffer pixel
    mov py, 0
PY: cmp py, 240
    jge PD                      ; selesai semua baris

    mov px, 0
PX: cmp px, 320
    jge PNY                     ; selesai satu baris

    ; --- Gelombang 1: horizontal (px/2 + phase1) ---
    mov eax, px
    shr eax, 1                  ; px / 2
    add eax, phase1             ; tambah offset animasi horizontal

    ; --- Gelombang 2: vertikal (py/2 + phase2) ---
    mov ebx, py
    shr ebx, 1                  ; py / 2
    add ebx, phase2             ; tambah offset animasi vertikal

    ; --- Gelombang 3: diagonal ((px+py)/4 + phase3) ---
    mov ecx, px
    add ecx, py                 ; px + py
    shr ecx, 2                  ; / 4 (skala lebih lambat = pola lebih besar)
    add ecx, phase3             ; tambah offset animasi diagonal

    ; --- Interferensi: jumlahkan semua gelombang, BARU mod 256 ---
    ; Tidak ada AND 255 di tengah - biarkan overflow bebas agar
    ; interferensi menghasilkan pola yang benar-benar non-linear
    add eax, ebx
    add eax, ecx                ; total interferensi (bisa > 255)
    and eax, 255                ; ambil mod 256 SETELAH semua dijumlah
    mov val, eax

    ; --- Petakan val ke warna RGB dengan offset 1/3 siklus per channel ---
    ; Format pixel: 0x00RRGGBB (BI_RGB 32-bit, byte order little-endian = BGR)

    ; Channel merah (byte 0): val mod 256
    ; Pakai val langsung (sudah 0..255)
    mov eax, val
    and eax, 0FFh               ; isolasi byte bawah = R

    ; Channel hijau (byte 1): (val + 85) mod 256 (geser 1/3 siklus)
    mov ebx, val
    add ebx, 85
    and ebx, 0FFh               ; mod 256
    shl ebx, 8                  ; geser ke posisi byte G (bit 8-15)

    ; Channel biru (byte 2): (val + 170) mod 256 (geser 2/3 siklus)
    mov ecx, val
    add ecx, 170
    and ecx, 0FFh               ; mod 256
    shl ecx, 16                 ; geser ke posisi byte B (bit 16-23)

    ; Gabungkan R | G | B -> pixel BGRA 32-bit (alpha byte 3 = 0)
    or  eax, ebx
    or  eax, ecx
    mov [esi], eax              ; tulis 4 byte pixel ke buffer
    add esi, 4                  ; maju ke pixel berikutnya

    inc px
    jmp PX
PNY:
    inc py
    jmp PY
PD:
    ; Gerakkan ketiga gelombang dengan kecepatan berbeda tiap frame
    ; Kecepatan berbeda = pola interferensi berubah arah dan ritme secara organik
    add phase1, 2               ; gelombang horizontal: kecepatan sedang
    add phase2, 3               ; gelombang vertikal: lebih cepat -> gerak diagonal
    add phase3, 1               ; gelombang diagonal: paling lambat -> efek "napas"
    ret
RenderPlasma endp

; ============================================================
; RenderFrame
; Render satu frame lengkap:
;   1. Buat plasma 320x240 di Buffer
;   2. Stretch ke ukuran window penuh (StretchBlt dengan HALFTONE)
;   3. Gambar teks scrolling di atasnya (dengan shadow dan warna emas)
;
; Tidak ada persistent DC/bitmap - semua dibuat dan dihapus tiap frame
; untuk menghindari resource leak.
; ============================================================
RenderFrame proc
    LOCAL bmi:BITMAPINFO
    LOCAL hdcTemp:DWORD         ; DC asli dari GetDC
    LOCAL hFontTmp:DWORD        ; font yang dibuat untuk frame ini
    LOCAL hOldFontTmp:DWORD     ; font lama yang digantikan (untuk cleanup)
    LOCAL len:DWORD             ; panjang string teks
    LOCAL xPos:DWORD, yPos:DWORD    ; posisi teks
    LOCAL txtW:DWORD, fontH:DWORD   ; lebar teks dan tinggi font

    ; Dapatkan ukuran client area saat ini (responsif terhadap resize)
    invoke GetClientRect, hWndMain, addr rect
    mov eax, rect.right
    sub eax, rect.left
    mov WinWidth, eax
    mov eax, rect.bottom
    sub eax, rect.top
    mov WinHeight, eax

    ; Render plasma ke Buffer (32-bit pixel array 320x240)
    call RenderPlasma

    ; Dapatkan DC dari window untuk operasi GDI
    invoke GetDC, hWndMain
    mov hdcTemp, eax

    ; Buat DC dan bitmap memori untuk plasma 320x240
    invoke CreateCompatibleDC, hdcTemp
    mov hDCMem, eax
    invoke CreateCompatibleBitmap, hdcTemp, 320, 240
    mov hBitmap, eax
    invoke SelectObject, hDCMem, hBitmap
    mov hOldBitmap, eax         ; simpan bitmap lama untuk cleanup

    ; Isi header BITMAPINFO untuk SetDIBitsToDevice
    ; biHeight negatif = top-down (baris pertama = atas)
    mov bmi.bmiHeader.biSize,          sizeof BITMAPINFOHEADER
    mov bmi.bmiHeader.biWidth,         320
    mov bmi.bmiHeader.biHeight,        -240    ; negatif = top-down
    mov bmi.bmiHeader.biPlanes,        1
    mov bmi.bmiHeader.biBitCount,      32      ; 32 bpp BGRA
    mov bmi.bmiHeader.biCompression,   BI_RGB
    mov bmi.bmiHeader.biSizeImage,     0
    mov bmi.bmiHeader.biXPelsPerMeter, 0
    mov bmi.bmiHeader.biYPelsPerMeter, 0
    mov bmi.bmiHeader.biClrUsed,       0
    mov bmi.bmiHeader.biClrImportant,  0

    ; Upload Buffer (raw pixel) ke hDCMem sebagai bitmap
    invoke SetDIBitsToDevice, hDCMem, 0, 0, 320, 240,
           0, 0, 0, 240, addr Buffer, addr bmi, DIB_RGB_COLORS

    ; Buat DC dan bitmap kedua untuk output akhir (ukuran window penuh)
    invoke CreateCompatibleDC, hdcTemp
    mov hDCMem2, eax
    invoke CreateCompatibleBitmap, hdcTemp, WinWidth, WinHeight
    mov hBitmap2, eax
    invoke SelectObject, hDCMem2, hBitmap2
    mov hOldBitmap2, eax        ; simpan bitmap lama untuk cleanup

    ; Stretch plasma 320x240 ke ukuran window penuh dengan anti-aliasing
    invoke SetStretchBltMode, hDCMem2, HALFTONE
    invoke StretchBlt, hDCMem2, 0, 0, WinWidth, WinHeight,
           hDCMem, 0, 0, 320, 240, SRCCOPY

    ; Mode transparent: background teks tidak menimpa plasma
    invoke SetBkMode, hDCMem2, TRANSPARENT

    ; Hitung ukuran font responsif: 1/8 tinggi window, clamp 20..80
    mov eax, WinHeight
    shr eax, 3                  ; WinHeight / 8
    cmp eax, 20
    jge RF_f1
    mov eax, 20                 ; minimum font 20px
RF_f1:
    cmp eax, 80
    jle RF_f2
    mov eax, 80                 ; maksimum font 80px
RF_f2:
    mov fontH, eax

    ; Buat font bold untuk teks scroller
    invoke CreateFont, fontH, 0, 0, 0, 700, 0, 0, 0,
           0, 0, 0, 0, 0, addr szFontName
    mov hFontTmp, eax

    ; Select font ke DC, simpan font lama (SelectObject return = objek lama)
    invoke SelectObject, hDCMem2, eax
    mov hOldFontTmp, eax        ; eax = font lama yang digantikan

    ; Ukur lebar dan tinggi teks scroller
    invoke lstrlen, addr szMessage
    mov len, eax
    invoke GetTextExtentPoint32, hDCMem2, addr szMessage, len, addr szTextSize
    ; szTextSize[0] = lebar (cx), szTextSize[4] = tinggi (cy)
    mov eax, szTextSize
    mov txtW, eax
    mov eax, szTextSize+4
    mov TextHeight, eax

    ; Posisi Y: teks di tengah vertikal window
    mov eax, WinHeight
    sub eax, TextHeight
    shr eax, 1
    mov yPos, eax

    ; Posisi X: mulai dari tengah + offset scrolling
    ; ScrollPos bergerak dari kanan ke kiri, reset saat teks keluar layar kiri
    mov eax, WinWidth
    sub eax, txtW
    shr eax, 1                  ; posisi tengah horizontal
    add eax, ScrollPos          ; tambah offset scroll (bisa negatif saat teks geser kiri)
    mov xPos, eax

    ; Gambar shadow teks (hitam, offset +3/-3 piksel) untuk efek depth
    invoke SetTextColor, hDCMem2, 0         ; warna hitam untuk shadow
    mov eax, xPos
    add eax, 3
    invoke TextOut, hDCMem2, eax, yPos, addr szMessage, len
    mov eax, xPos
    sub eax, 3
    invoke TextOut, hDCMem2, eax, yPos, addr szMessage, len
    invoke TextOut, hDCMem2, xPos, yPos, addr szMessage, len

    ; Gambar teks utama: warna emas (0x00FFD700 = BGR: biru=0, hijau=D7, merah=FF)
    ; Catatan: GDI COLORREF format adalah 0x00BBGGRR
    invoke SetTextColor, hDCMem2, 00FFD700h ; warna emas
    invoke TextOut, hDCMem2, xPos, yPos, addr szMessage, len

    ; Overlay teks dengan warna kuning cerah untuk highlight
    invoke SetTextColor, hDCMem2, 00FFFF00h ; kuning cerah
    invoke TextOut, hDCMem2, xPos, yPos, addr szMessage, len

    ; Update posisi scroll: gerak ke kiri 4 piksel per frame
    sub ScrollPos, 4

    ; ----------------------------------------------------------------
    ; Kondisi reset scroll yang benar:
    ; xPos = (WinWidth - txtW) / 2 + ScrollPos
    ; Teks keluar layar kiri saat: xPos + txtW < 0
    ;   -> (WinWidth - txtW)/2 + ScrollPos + txtW < 0
    ;   -> ScrollPos < -(WinWidth + txtW) / 2
    ;
    ; Bug lama: cek ScrollPos + txtW < 0 -> terlalu dini,
    ; teks masih terlihat sebagian saat ScrollPos direset,
    ; menyebabkan teks "melompat" tiba-tiba ke kanan.
    ;
    ; Perbaikan: hitung xPos aktual, cek apakah ujung kanannya (xPos+txtW)
    ; sudah benar-benar di luar sisi kiri layar (< 0).
    ; ----------------------------------------------------------------
    ; Hitung ulang xPos aktual untuk cek batas
    mov eax, WinWidth
    sub eax, txtW
    sar eax, 1                  ; (WinWidth - txtW) / 2  (arithmetic shift = signed)
    add eax, ScrollPos          ; xPos aktual saat ini
    ; Cek apakah ujung kanan teks (xPos + txtW) sudah melewati sisi kiri
    add eax, txtW               ; eax = xPos + txtW = posisi ujung kanan teks
    cmp eax, 0
    jg  RF_sc                   ; ujung kanan masih di layar -> lanjut scroll
    ; Teks sudah benar-benar keluar layar kiri: reset ke luar sisi kanan
    ; ScrollPos baru: agar xPos = WinWidth + 50 (margin kanan)
    ; xPos = (WinWidth - txtW)/2 + ScrollPos = WinWidth + 50
    ; -> ScrollPos = WinWidth + 50 - (WinWidth - txtW)/2
    ;             = (WinWidth + txtW)/2 + 50
    mov eax, WinWidth
    add eax, txtW
    sar eax, 1                  ; (WinWidth + txtW) / 2
    add eax, 50                 ; tambah margin 50px agar mulai dari luar kanan
    mov ScrollPos, eax
RF_sc:

    ; Cleanup font yang dibuat untuk frame ini
    invoke SelectObject, hDCMem2, hOldFontTmp   ; restore font lama
    invoke DeleteObject, hFontTmp               ; hapus font sementara

    ; BitBlt output akhir dari memory DC ke window DC
    invoke BitBlt, hdcTemp, 0, 0, WinWidth, WinHeight, hDCMem2, 0, 0, SRCCOPY

    ; Cleanup DC dan bitmap sementara (harus dalam urutan: SelectObject -> DeleteObject -> DeleteDC)
    invoke SelectObject, hDCMem,  hOldBitmap    ; restore bitmap lama hDCMem
    invoke DeleteObject, hBitmap                ; hapus bitmap plasma
    invoke DeleteDC,     hDCMem                 ; hapus DC plasma

    invoke SelectObject, hDCMem2, hOldBitmap2   ; restore bitmap lama hDCMem2
    invoke DeleteObject, hBitmap2               ; hapus bitmap output
    invoke DeleteDC,     hDCMem2               ; hapus DC output

    invoke ReleaseDC, hWndMain, hdcTemp         ; kembalikan DC window
    ret
RenderFrame endp

; ============================================================
; WndProc
; Message handler utama window.
;
; WM_CREATE  : Mulai timer 33ms (~30fps) dan inisialisasi audio
; WM_TIMER   : Update audio + render frame + hitung frame
; WM_PAINT   : BeginPaint/EndPaint saja (rendering di WM_TIMER)
; WM_KEYDOWN : ESC -> keluar
; WM_DESTROY : Hentikan timer, bersihkan audio, kirim quit
; ============================================================
WndProc proc hWnd:DWORD, uMsg:DWORD, wParam:DWORD, lParam:DWORD
    cmp uMsg, WM_CREATE
    jne WP_chkTimer
    invoke SetTimer, hWnd, 1, 33, 0    ; timer ID=1, interval 33ms (~30fps)
    call InitAudio
    xor eax, eax
    ret

WP_chkTimer:
    cmp uMsg, WM_TIMER
    jne WP_chkPaint
    call UpdateAudio            ; isi ulang buffer audio yang sudah selesai
    call RenderFrame            ; render frame visual berikutnya
    inc FrameCount              ; hitung frame (bisa dipakai untuk efek time-based)
    xor eax, eax
    ret

WP_chkPaint:
    cmp uMsg, WM_PAINT
    jne WP_chkKey
    ; Rendering dilakukan di WM_TIMER, WM_PAINT hanya perlu validasi region
    invoke BeginPaint, hWnd, addr ps
    invoke EndPaint,   hWnd, addr ps
    xor eax, eax
    ret

WP_chkKey:
    cmp uMsg, WM_KEYDOWN
    jne WP_chkDestroy
    cmp wParam, VK_ESCAPE       ; ESC -> keluar dari program
    jne WP_chkDestroy
    invoke PostQuitMessage, 0
    xor eax, eax
    ret

WP_chkDestroy:
    cmp uMsg, WM_DESTROY
    jne WP_default
    invoke KillTimer, hWnd, 1   ; hentikan timer
    call CleanupAudio           ; tutup device audio dan bebaskan buffer
    invoke PostQuitMessage, 0
    xor eax, eax
    ret

WP_default:
    invoke DefWindowProc, hWnd, uMsg, wParam, lParam
    ret
WndProc endp

; ============================================================
; Entry Point
; Daftarkan kelas window, buat window, jalankan message loop.
; ============================================================
start:
    ; Dapatkan handle instance program ini
    invoke GetModuleHandle, NULL
    mov hInst, eax

    ; Isi WNDCLASSEX
    mov wc.cbSize,        sizeof WNDCLASSEX
    mov wc.style,         CS_HREDRAW or CS_VREDRAW  ; redraw saat resize
    mov wc.lpfnWndProc,   offset WndProc
    mov wc.cbClsExtra,    0
    mov wc.cbWndExtra,    0
    mov wc.hInstance,     eax
    mov wc.hbrBackground, 0                         ; tidak ada background brush (kita handle sendiri)
    mov wc.lpszMenuName,  0
    mov wc.lpszClassName, offset szClassName
    mov wc.hIcon,         0
    mov wc.hIconSm,       0
    invoke LoadCursor, NULL, IDC_ARROW
    mov wc.hCursor,       eax

    invoke RegisterClassEx, addr wc

    ; Buat window dengan ukuran awal 800x600
    invoke CreateWindowEx, 0, addr szClassName, addr szWindowName,
           WS_OVERLAPPEDWINDOW or WS_VISIBLE,
           CW_USEDEFAULT, CW_USEDEFAULT, 800, 600,
           NULL, NULL, hInst, NULL
    mov hWndMain, eax

    ; Message loop standar
    .while TRUE
        invoke GetMessage, addr msg, NULL, 0, 0
        .break .if eax == 0     ; WM_QUIT -> keluar loop
        invoke TranslateMessage, addr msg
        invoke DispatchMessage,  addr msg
    .endw

    invoke ExitProcess, msg.wParam
    ret
end start
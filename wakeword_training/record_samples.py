#!/usr/bin/env python
"""
Record wake-word training clips for "Hey Elder Wand".

Run it, then just say the phrase each time it prompts you. It saves 2.0 s
16 kHz mono WAVs into ./real_samples/ (continuing the s1_### numbering), which
the Colab notebook (cell 13b) picks up automatically.

    python record_samples.py

GOAL: variety beats quantity. The model learns whatever you give it, so give it
the CASUAL way you'll really call it — not just the careful pronunciation.
Aim for 60-100 clips covering the styles it prompts you with.

Controls after each recording:
    [Enter] keep it and go to the next
    r       redo (discard and record again)
    q       quit
"""
import os, sys, glob, time
import numpy as np
import sounddevice as sd
import soundfile as sf

SR = 16000
DUR = 2.0                       # seconds -> 32000 samples == training total_length
OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "real_samples")
os.makedirs(OUT_DIR, exist_ok=True)

# Rotating delivery styles — the whole point is diversity.
STYLES = [
    "NORMAL - say it the way you usually would",
    "CASUAL / lazy - mumble it like you're not trying",
    "FAST - rush through it",
    "SLOW - drag it out",
    "QUIET - almost under your breath",
    "LOUD - call it from across the room",
    "FROM A DISTANCE - hold the mic/phone at arm's length",
    "DIFFERENT TONE - question-like, sing-song, tired, cheerful",
    "MID-SENTENCE - '...ok, hey elder wand, what's the weather'",
]

def next_index():
    existing = glob.glob(os.path.join(OUT_DIR, "s1_*.wav"))
    nums = [int(os.path.basename(f)[3:6]) for f in existing
            if os.path.basename(f)[3:6].isdigit()]
    return (max(nums) + 1) if nums else 1

def record_once():
    for c in ("3", "2", "1", ">>> SPEAK NOW <<<"):
        print("   " + c, end="\r" if c != ">>> SPEAK NOW <<<" else "\n", flush=True)
        time.sleep(0.6)
    audio = sd.rec(int(DUR * SR), samplerate=SR, channels=1, dtype="int16")
    sd.wait()
    return audio.reshape(-1)

def quality(audio):
    a = audio.astype(np.float32)
    peak = int(np.abs(a).max())
    rms = float(np.sqrt((a ** 2).mean()))
    if peak >= 32000:
        return f"peak={peak} - TOO LOUD (clipping), move back a bit"
    if peak < 1500:
        return f"peak={peak} - TOO QUIET, speak up / move closer"
    return f"peak={peak} rms={rms:.0f} - good"

def main():
    print(f"\nRecording to: {OUT_DIR}")
    print(f"Existing clips: {len(glob.glob(os.path.join(OUT_DIR, 's1_*.wav')))}")
    print("Say 'HEY ELDER WAND' (or just 'ELDER WAND') each time.\n"
          "Vary it — the prompt tells you how. Ctrl-C or 'q' to stop.\n")
    i = next_index()
    saved = 0
    try:
        while True:
            style = STYLES[(i - 1) % len(STYLES)]
            print(f"--- clip s1_{i:03d}  |  STYLE: {style}")
            input("    press [Enter] to record...")
            while True:
                audio = record_once()
                print("    " + quality(audio))
                choice = input("    [Enter]=keep  r=redo  q=quit: ").strip().lower()
                if choice == "r":
                    print("    redoing...\n")
                    continue
                if choice == "q":
                    raise KeyboardInterrupt
                path = os.path.join(OUT_DIR, f"s1_{i:03d}.wav")
                sf.write(path, audio, SR, subtype="PCM_16")
                saved += 1
                print(f"    saved {os.path.basename(path)}  ({saved} this session)\n")
                i += 1
                break
    except KeyboardInterrupt:
        pass
    total = len(glob.glob(os.path.join(OUT_DIR, "s1_*.wav")))
    print(f"\nDone. Saved {saved} new clips this session. Total now: {total}.")
    if total < 50:
        print(f"Tip: {total} is still light. 60-100 varied clips gives the best wake rate.")
    print("Next: commit them and rerun the Colab notebook (cell 13b uses them automatically).")

if __name__ == "__main__":
    main()

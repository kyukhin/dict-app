#!/usr/bin/env python3
"""
convert_sound_clips.py
Converts the Mellstroy sound theme's recorded clips (docs/specs/0131-learning.md,
Sounds and Feedback; #340) into the app's data sets:

    python3 Scripts/convert_sound_clips.py <clip folder> [--out <folder>]

Every audio file of the folder (right-1.ogg, ...) becomes
`<out>/<name>.dataset/<name>.m4a` with its Contents.json; `<out>` defaults to
DictApp/Assets.xcassets/Mellstroy, a namespace, so the app reads
`NSDataAsset(name: "Mellstroy/right-1")`. The sources are not committed.

Each clip is:
  1. decoded to mono 44.1 kHz (iOS does not play Ogg), no longer than it was;
  2. trimmed: the silence before and after the voice goes, the voice being
     every 10 ms whose RMS is within 40 dB of the loudest 10 ms; 20 ms are
     kept before it and 80 ms after, cut to whole milliseconds, with a 5 ms
     fade-in and a 10 ms fade-out;
  3. made about as loud as Meme by 0131's rules: its RMS raised to Meme's,
     its peak at most 0.7. A voice's peaks stand far above its RMS, so a
     lookahead limiter (ffmpeg's alimiter) holds them down, by at most 12 dB
     before the encoder's overshoot is taken off;
  4. encoded as AAC .m4a at 64 kbps, with no metadata (the same input and
     ffmpeg give the same bytes). A peak over 0.69 as ffmpeg decodes it (0.7
     as the app does) lowers the limit and encodes again.

It prints each clip's length, size, peak, RMS against Meme's and how far the
limiter pulled its loudest peak down.

Needs ffmpeg and ffprobe on PATH.
"""

import argparse
import array
import json
import math
import subprocess
import sys
from pathlib import Path

RATE = 44_100
PEAK = 0.7
# Apple's AAC decoder peaks up to 1% above ffmpeg's: the script holds
# ffmpeg's decoded peak at 0.69, so the app's stays at most 0.7.
DECODED_PEAK = 0.69
# The RMS of Meme's six sounds together (ToneSynth.wav(_, theme: .meme),
# 0.126 to 0.240 each), measured 2026-11-16.
MEME_RMS = 0.211
# The limiter's first limit, under 0.7 for the encoder's overshoot; how far
# it may pull the loudest peak down; how close to Meme's RMS is enough.
LIMIT = 0.68
MAX_LIMITING = 10 ** (12 / 20)
RMS_SLACK = 10 ** (-0.5 / 20)
FRAME = RATE // 100
VOICE_DB = 40
LEAD, TAIL = int(RATE * 0.02), int(RATE * 0.08)
FADE_IN, FADE_OUT = int(RATE * 0.005), int(RATE * 0.01)
EXTENSIONS = {".ogg", ".opus", ".oga", ".wav", ".m4a", ".mp3", ".flac"}
DATASET_INFO = {"author": "xcode", "version": 1}


def decode(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", str(path), "-ac", "1", "-ar", str(RATE),
                          "-f", "f32le", "-"], check=True, capture_output=True).stdout
    samples = array.array("f")
    samples.frombytes(raw)
    if sys.byteorder != "little":
        samples.byteswap()
    return samples


def duration(path):
    out = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0",
                          str(path)], check=True, capture_output=True, text=True).stdout
    return float(out)


def peak_rms(samples):
    if not samples:
        return 0.0, 0.0
    return max(abs(s) for s in samples), math.sqrt(math.fsum(s * s for s in samples) / len(samples))


def trim(samples):
    frames = [peak_rms(samples[i:i + FRAME])[1] for i in range(0, len(samples), FRAME)]
    loudest = max(frames, default=0)
    if loudest == 0:
        return samples
    voiced = [i for i, rms in enumerate(frames) if rms >= loudest * 10 ** (-VOICE_DB / 20)]
    start = max(0, voiced[0] * FRAME - LEAD)
    end = min(len(samples), (voiced[-1] + 1) * FRAME + TAIL)
    # Whole milliseconds: the .m4a's edit list counts them, rounded, so a
    # clip cut to the sample could play a fraction of one longer.
    end = start + (end - start) * 1000 // RATE * RATE // 1000
    out = samples[start:end]
    for i in range(min(FADE_IN, len(out))):
        out[i] *= i / FADE_IN
    for i in range(min(FADE_OUT, len(out))):
        out[len(out) - 1 - i] *= i / FADE_OUT
    return out


def encode(samples, gain, limit, path):
    """`samples` times `gain`, limited to `limit`, as AAC; its peak and RMS decoded."""
    pcm = array.array("f", (s * gain for s in samples))
    if sys.byteorder != "little":
        pcm.byteswap()
    limiter = f"alimiter=limit={limit:.4f}:attack=5:release=80:level=0:latency=1"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(RATE), "-ac", "1", "-i", "-",
                    "-af", limiter, "-c:a", "aac", "-b:a", "64k", "-map_metadata", "-1",
                    "-fflags", "+bitexact", "-flags:a", "+bitexact", str(path)], input=pcm.tobytes(), check=True)
    return peak_rms(decode(path))


def convert(voice, target):
    """Raises the RMS to Meme's, within MAX_LIMITING, then lowers the limit
    until the decoded peak is at most DECODED_PEAK. Returns the peak, the RMS
    and the limiting in dB."""
    peak, rms = peak_rms(voice)
    gain, limit = MEME_RMS / rms, LIMIT
    for _ in range(8):
        gain = min(gain, MAX_LIMITING * limit / peak)
        out_peak, out_rms = encode(voice, gain, limit, target)
        if out_rms >= MEME_RMS * RMS_SLACK or gain >= MAX_LIMITING * limit / peak * 0.999:
            break
        gain *= MEME_RMS / out_rms
    for _ in range(20):
        if out_peak <= DECODED_PEAK:
            return out_peak, out_rms, 20 * math.log10(max(1, gain * peak / limit))
        limit *= DECODED_PEAK / out_peak * 0.995
        out_peak, out_rms = encode(voice, gain, limit, target)
    sys.exit(f"{target.name}: the peak stays over {DECODED_PEAK}")


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def main():
    parser = argparse.ArgumentParser(description="Converts the Mellstroy clips into the app's data sets.")
    parser.add_argument("clips", type=Path, help="the folder of the source clips")
    parser.add_argument("--out", type=Path,
                        default=Path(__file__).resolve().parent.parent / "DictApp/Assets.xcassets/Mellstroy")
    args = parser.parse_args()

    sources = sorted(p for p in args.clips.iterdir() if p.suffix.lower() in EXTENSIONS)
    if not sources:
        sys.exit(f"no clips in {args.clips}")
    # One data set per name: right-1.ogg and right-1.wav would write the same one.
    by_name = {}
    for source in sources:
        by_name.setdefault(source.stem.casefold(), []).append(source)
    clashes = [paths for paths in by_name.values() if len(paths) > 1]
    if clashes:
        sys.exit("clips with the same name, nothing written:\n" +
                 "\n".join("  " + ", ".join(str(p) for p in paths) for paths in clashes))
    args.out.mkdir(parents=True, exist_ok=True)
    write_json(args.out / "Contents.json", {"info": DATASET_INFO, "properties": {"provides-namespace": True}})

    print(f"{'clip':20} {'source s':>9} {'out s':>7} {'bytes':>7} {'peak':>5} {'RMS dB':>7} {'vs Meme':>8} "
          f"{'limited dB':>10}")
    total = 0
    for source in sources:
        name = source.stem
        dataset = args.out / f"{name}.dataset"
        dataset.mkdir(exist_ok=True)
        target = dataset / f"{name}.m4a"
        # The resampler may add a few samples: never longer than the source.
        voice = trim(decode(source)[:int(duration(source) * RATE)])
        peak, rms, limiting = convert(voice, target)
        write_json(dataset / "Contents.json", {
            "data": [{"filename": target.name, "idiom": "universal",
                      "universal-type-identifier": "com.apple.m4a-audio"}],
            "info": DATASET_INFO,
        })
        size = target.stat().st_size
        total += size
        print(f"{name:20} {duration(source):9.3f} {duration(target):7.3f} {size:7} {peak:5.2f} "
              f"{20 * math.log10(rms):7.1f} {20 * math.log10(rms / MEME_RMS):+8.1f} {limiting:10.1f}")
    print(f"{len(sources)} clips, {total} bytes")


if __name__ == "__main__":
    main()

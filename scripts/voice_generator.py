#!/usr/bin/env python3

import requests
import json
import sys
import os
import wave
from datetime import datetime

# --- 設定項目 ---
OUTPUT_DIR = "dist"
BASE_FILENAME = "voice"
SPEAKER_ID = 12 # 白上虎太郎 ふつう
# SPEAKER_ID = 51 # †聖騎士紅桜† ノーマル
# SPEAKER_ID = 21 # 剣崎雌雄 ノーマル
# SPEAKER_ID = 11 # 玄野武宏 ノーマル
# SPEAKER_ID = 52 # 雀松朱司 ノーマル
# SPEAKER_ID = 67 # 栗田まろん ノーマル
SPEED_SCALE = 1.2
ENDPOINT = "http://localhost:50021"
PAGE_SILENCE = 3.0
LINE_SILENCE = 0.5

def generate_voice(text, filename):
    res1 = requests.post(f"{ENDPOINT}/audio_query", params={'text': text, 'speaker': SPEAKER_ID})
    res1.raise_for_status()
    query = res1.json()
    query['speedScale'] = SPEED_SCALE

    res2 = requests.post(f"{ENDPOINT}/synthesis", params={'speaker': SPEAKER_ID}, data=json.dumps(query))
    res2.raise_for_status()

    with open(filename, "wb") as f:
        f.write(res2.content)

def create_silence_frames(duration, params):
    num_frames = int(duration * params.framerate)
    return b'\x00' * (num_frames * params.nchannels * params.sampwidth)

def main():
    if len(sys.argv) < 2:
        print("Usage: python voice.py <input_file>")
        sys.exit(1)

    # 日時付きファイル名の生成
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    combined_file = f"{BASE_FILENAME}_{timestamp}.wav"

    input_file = sys.argv[1]
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    with open(input_file, "r", encoding="utf-8") as f:
        content = f.read().strip()

    sections = []
    pages = content.split('\n\n')
    for i, page in enumerate(pages):
        lines = [l.strip() for l in page.split('\n') if l.strip()]
        for j, line in enumerate(lines):
            if j == len(lines) - 1:
                silence = PAGE_SILENCE if i < len(pages) - 1 else 0
            else:
                silence = LINE_SILENCE
            sections.append((line, silence))

    generated_files = []
    try:
        for i, (text, _) in enumerate(sections):
            save_path = os.path.join(OUTPUT_DIR, f"temp_{i}.wav")
            print(f"[{i+1}/{len(sections)}] Generating: {text[:15]}...")
            generate_voice(text, save_path)
            generated_files.append(save_path)

        if not generated_files:
            return

        with wave.open(generated_files[0], 'rb') as w:
            params = w.getparams()

        with wave.open(combined_file, 'wb') as outfile:
            outfile.setparams(params)
            for i, (f, silence_duration) in enumerate(zip(generated_files, [s[1] for s in sections])):
                with wave.open(f, 'rb') as w:
                    outfile.writeframes(w.readframes(w.getnframes()))

                if silence_duration > 0:
                    outfile.writeframes(create_silence_frames(silence_duration, params))

        print(f"\nSuccess: Combined into {os.path.abspath(combined_file)}")

    finally:
        for f in generated_files:
            if os.path.exists(f):
                os.remove(f)
        print("Cleanup finished.")

if __name__ == "__main__":
    main()

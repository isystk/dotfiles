#!/usr/bin/env python3
"""
PDFスライドと音声ファイルを合成し、プレゼンテーション動画を作成するスクリプト

【使い方】
    python3 combine_pdf_audio.py <PDFパス> <音声パス> [出力パス]

【仕組み】
    1. 音声データ内の「2秒以上の無音区間」を自動検知します。
    2. 無音の中間地点を「ページ捲り」のタイミングとして判定します。
    3. PDFの各ページと音声を同期させたMP4動画を出力します。

【依存ツール】
    - ffmpeg (OSインストールが必要)
    - poppler-utils (pdf2imageに必要、OSインストールが必要)
"""

import os
import argparse
import numpy as np
from moviepy import ImageClip, AudioFileClip, concatenate_videoclips
from moviepy.audio.fx import MultiplyVolume
from pdf2image import convert_from_path
import tempfile

def detect_silence_switches(audio_path, min_silence_len=2.0, threshold=0.01):
    audio = AudioFileClip(audio_path)
    fps = 100 
    
    # チャンクごとに処理してメモリ節約
    duration = audio.duration
    switches = []
    silence_start = None
    
    for t in np.arange(0, duration, 1/fps):
        chunk = audio.get_frame(t)
        level = np.mean(np.abs(chunk))
        
        silent = level < threshold
        if silent and silence_start is None:
            silence_start = t
        elif not silent and silence_start is not None:
            silence_duration = t - silence_start
            if silence_duration >= min_silence_len:
                switches.append(silence_start + silence_duration / 2)
            silence_start = None
            
    audio.close()
    return switches

def create_presentation_video(pdf_path, audio_path, output_path):
    if not os.path.exists(pdf_path) or not os.path.exists(audio_path):
        return

    audio = AudioFileClip(audio_path)
    audio = audio.with_effects([MultiplyVolume(1.5)])
    
    switch_times = detect_silence_switches(audio_path)
    
    with tempfile.TemporaryDirectory() as temp_dir:
        # 必要な時にだけ画像を生成・保存
        pages = convert_from_path(pdf_path, dpi=200) # メモリのためにDPIを少し下げる（300->200）
        
        durations = []
        last_time = 0
        target_switches = switch_times[:len(pages)-1]

        for i in range(len(pages)):
            if i < len(target_switches):
                duration = target_switches[i] - last_time
                last_time = target_switches[i]
            else:
                duration = max(0.1, audio.duration - last_time)
                last_time = audio.duration
            durations.append(duration)

        clips = []
        for i, page in enumerate(pages):
            img_path = os.path.join(temp_dir, f"page_{i}.png")
            page.resize((1920, 1080)).save(img_path, "PNG")
            
            # 画像をメモリに置かず、ファイルから読み込む設定
            clip = ImageClip(img_path).with_duration(durations[i])
            clips.append(clip)

        final_video = concatenate_videoclips(clips, method="compose")
        final_video = final_video.with_audio(audio)

        final_video.write_videofile(
            output_path,
            fps=24,
            codec="libx264",
            audio_codec="aac", # 互換性の高いaacに変更
            bitrate="4000k",   # メモリ負荷軽減のため少し下げる
            threads=2,         # スレッド数を制限してメモリ使用を安定させる
            ffmpeg_params=["-pix_fmt", "yuv420p", "-preset", "veryfast"]
        )
        
        # クローズ処理
        for c in clips: c.close()
        final_video.close()
        audio.close()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("pdf")
    parser.add_argument("audio")
    parser.add_argument("-o", "--output", default="output_presentation.mp4")

    args = parser.parse_args()
    create_presentation_video(args.pdf, args.audio, args.output)

if __name__ == "__main__":
    main()

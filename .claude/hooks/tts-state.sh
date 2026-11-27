#!/usr/bin/env bash
# UserPromptSubmit hook: TTS OFF（~/.claude/tts-off あり）の間だけ、<!-- tts: --> を付けないよう Claude へ通知する
[ -e "$HOME/.claude/tts-off" ] && echo "[TTS OFF] 音声読み上げは無効。応答末尾の <!-- tts: 要約 --> は付けない。"
exit 0

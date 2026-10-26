---
name: tts-toggle
description: Use when the user wants to turn Claude Code's spoken (text-to-speech) replies on or off, check their status, or set up the VOICEVOX engine that powers them. Triggers on "音声読み上げをON/OFF", "読み上げを止めて", "しゃべらせて", "TTSオフ", "VOICEVOXを構築して", "音が出ない", "/tts-toggle".
---

# tts-toggle

## 概要

Stop フック `~/.claude/hooks/tts-speak.sh` による応答の音声読み上げ（VOICEVOX ずんだもん）を、フラグファイル `~/.claude/tts-off` の有無で切り替える。あわせて、VOICEVOX エンジンが未起動・未構築なら構築・起動まで行う。

- フラグあり → 読み上げ無効（OFF）
- フラグなし → 読み上げ有効（ON）

フラグファイルはフックが毎回確認するため、切り替えは再起動不要で即時反映される。

エンジン不達時のフォールバックは OS ごとに異なる（WSL: Windows SAPI / macOS: `say -v Kyoko`）。

## 手順

1. ユーザー指示から操作を判定する（ON / OFF / 状態確認 / セットアップ / 指定なしならトグル）
2. 現在の状態を `test -e ~/.claude/tts-off` で確認する
3. 操作を実行する
   - OFF: `touch ~/.claude/tts-off` に加え、再生中の音声を止める（`kill -- "-$(cat "${XDG_RUNTIME_DIR:-/tmp}/claude-tts.pid")" 2>/dev/null || true`。ワーカーは別プロセスグループなので、負のPIDでグループごと止める）。続けてエンジンも停止する: コンテナがあれば `docker stop voicevox_engine_tts`、macOS のアプリ起動なら `osascript -e 'quit app "VOICEVOX"'`（いずれも未起動なら何もしない）。ON に戻す時は下記「エンジン確認」で再起動される
   - ON: `rm -f ~/.claude/tts-off` を実行し、続けて下記「エンジン確認」を行う
4. 切り替え後の状態（ON/OFF）とエンジンの状態を簡潔に報告する

## エンジン確認と環境セットアップ

ON にする時、および「音が出ない」「構築して」と言われた時に実施する。

1. 疎通確認: `curl -s -m 2 http://localhost:50022/version` と `:50021` のどちらかが応答すれば起動済み（フックも同じ順で探す）。応答があれば完了
2. 未起動なら、以下の順で起動を試みる（上から最初に使えるもの）
   1. 停止中の既存コンテナ: `docker ps -a --filter name=voicevox_engine_tts` にあれば `docker start voicevox_engine_tts`
   2. Docker が使える（`docker info` が成功）: 未構築なら下記を実行（初回はイメージ取得で数分かかる。事前にユーザーへ一言伝える）
      ```
      docker run -d --name voicevox_engine_tts --restart unless-stopped \
        -p 50022:50021 voicevox/voicevox_engine:cpu-ubuntu20.04-latest
      ```
   3. Docker が使えず macOS: VOICEVOX アプリ（`/Applications/VOICEVOX.app`）があれば `open -a VOICEVOX`（エンジンは 50021 で起動）。無ければ `brew install --cask voicevox` を提案し、承諾後に実行
   4. いずれも不可: 不足している前提（Docker など）をユーザーへ伝えて終了する。インストールは勝手に行わない
3. 起動後、`/version` が応答するまで最大60秒待つ（1〜2秒間隔で再確認）。応答しなければ `docker logs voicevox_engine_tts` などで原因を報告する
4. 再生確認: 短い文で `audio_query` → `synthesis` を呼び、`afplay`（macOS）または `play`（SoX）で鳴らして音声が出ることを確認する。再生コマンドが無ければ報告する（Linux/WSL は `sox` が必要）

## 注意

- フラグはグローバル（`~/.claude/`）なので全プロジェクト・全セッションに効く
- 声の速度・文字数は環境変数 `VOICEVOX_SPEAKER`（既定3=ずんだもん） / `VOICEVOX_SPEED`（既定1.5、範囲0.5〜2.0） / `TTS_MAX_CHARS`（既定200） / `VOICEVOX_URL`（未指定なら 50022→50021 の順で自動検出）で調整できる。このスキルでは変更しない
- 音声入力（`/voice`、マイクでの入力）とは別機能。そちらの切り替えは `/voice` を使うよう案内する

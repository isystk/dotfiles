---
name: handover
description: Use when ending a session, reaching a natural break point (a feature/task just completed, the user signals they are wrapping up, or the session has run long), to record a session handover file that the next session picks up context from.
---

# handover

## 概要

セッション終了時に、作業内容・決定事項・次のアクションを引き継ぎファイル `HANDOVER.md` へ記録するスキル。次セッション開始時は `SessionStart` フック（`~/.claude/hooks/takeover.sh`）が自動的に未読の引き継ぎ内容を検出し、コンテキストへ注入する（takeover）。

参考: https://zenn.dev/ushironoko/articles/6b905435f3afe8

## 使うタイミング

- ユーザーが明示的に `/handover` と入力した時
- 以下いずれかを検知しClaude側から「引き継ぎファイルを作成しますか？」と提案する時
  - 大きな機能・タスクが完了した時
  - ユーザーが会話終了を示唆した時（「今日はここまで」「また今度」等）
  - コンテキストが長時間・大量のやり取りに及んだ時

## 手順

1. `{プロジェクトルート}/HANDOVER.md` が Git 管理対象外か確認する。`.gitignore` に `HANDOVER.md` が無ければ追加する
2. `date` コマンドで現在日時（ISO 8601）を取得する
3. 下記フォーマットに沿って内容をまとめ、`{プロジェクトルート}/HANDOVER.md` へ**上書き保存**する（既存ファイルがあっても丸ごと置き換える）

## ファイルフォーマット

```markdown
---
created: 2026-08-14T15:30:00+09:00
read: false
session_id: session_20260814_1530
---

# 今回やったこと
- 箇条書きで簡潔に

# 決定事項
- 確定した設計判断・方針

# 捨てた選択肢と理由
- 検討したが不採用にしたアプローチと、不採用にした理由

# ハマりどころ
- 詰まったポイント・発生したエラーと対処

# 学び
- 得られた知見

# 次にやること
- 未完了タスク（優先度がわかる形で）

# 関連ファイル
- 触った主要ファイルパス一覧
```

- `created`: 保存時刻（ISO 8601、タイムゾーン付き）
- `read`: 常に `false` で保存する（takeoverフックが読了後 `true` に書き換える）
- `session_id`: `session_<YYYYMMDD>_<HHMM>` 形式の疑似セッションID

## 記載ルール

- 簡潔に、箇条書き中心。事実ベースで書き、曖昧な表現を避ける
- 「捨てた選択肢と理由」は特に重要。次セッションで同じ検討をやり直す・同じ指摘を繰り返す無駄を防ぐ

## セッション開始時の連携（takeover）

`SessionStart` フック（`~/.claude/hooks/takeover.sh`）が `{プロジェクトルート}/HANDOVER.md` の frontmatter を確認し、`read: false` なら「takeoverスキルで確認するか」をユーザーへ確認するよう促す（本文は読まず、`read` の書き換えも行わない）。実際の読み込み・要約提示・`read: true` への更新は `takeover` スキルが担当する。詳細は `takeover` スキルを参照。

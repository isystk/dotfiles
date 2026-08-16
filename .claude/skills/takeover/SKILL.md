---
name: takeover
description: Use when starting a session and a HANDOVER.md was found in the project root, or the user explicitly asks to take over / resume from a previous session, to read the handover file, summarize it, and mark it as read.
---

# takeover

## 概要

前セッションが `handover` スキルで残した `{プロジェクトルート}/HANDOVER.md` を読み込み、内容をユーザーへ要約提示した上で `read: true` に更新するスキル。`handover` スキルの対になる引き継ぎ受け取り側。

参考: https://zenn.dev/ushironoko/articles/6b905435f3afe8

## 使うタイミング

- `SessionStart` フック（`~/.claude/hooks/takeover.sh`）が「未読のHANDOVER.mdが見つかった」と確認を促した時
  - フックは存在確認のみ行い、本文は読まない。実際に読むか・要約提示するかはユーザーへ確認してから、このスキルで行う
- ユーザーが明示的に `/takeover` と入力した時、または「引き継ぎ内容を確認したい」「前回の続きから」等と依頼した時
- フック未対応の環境で、セッション開始時に手動で `{プロジェクトルート}/HANDOVER.md` の存在と `read: false` を確認した時

## 手順

1. `{プロジェクトルート}/HANDOVER.md` が存在するか確認する。無ければ「引き継ぎファイルなし」と伝えて終了する
2. frontmatterの `read` を確認する
   - `read: true` なら、読み込み済みである旨をユーザーへ伝えて終了する（再読込みしたい場合はユーザーに確認する）
   - `read: false` なら次へ進む
3. ユーザーへ「未読の引き継ぎファイルがあります。内容を確認しますか？」と確認する
4. 承諾されたら本文を読み込み、要点をユーザーへ簡潔に提示する（セクション見出しごとに箇条書きで要約。特に「次にやること」「捨てた選択肢と理由」は省略しない）
5. frontmatterの `read: false` を `read: true` に書き換えて保存する

## 記載ルール

- 本文をそのまま垂れ流さず、要約して提示する。ただし事実を省略・改変しない
- ユーザーが確認を拒否した場合は `read` を書き換えない（未読のまま残す）

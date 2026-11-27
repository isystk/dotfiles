---
name: herdr-reviewr-open
description: 作業中のリポジトリ、または別のリポジトリの編集差分を、herdr の reviewr プラグインで表示するスキル。作業中のリポジトリなら今のワークスペースで開き、別リポジトリなら対象ディレクトリを cwd にした herdr ワークスペースを作って開く。「差分を reviewr で見たい」「変更を herdr で表示して」「別リポジトリの差分を見せて」等の依頼で使用する。
---

# herdr-reviewr-open

## 目的

このセッションで編集したリポジトリ（作業中のリポジトリ、または別のリポジトリ）の差分を、ユーザーの herdr 画面で [reviewr](https://github.com/persiyanov/herdr-reviewr)（`persiyanov/herdr-reviewr`）に表示する。

## 前提

- herdr と reviewr プラグインが導入済みであること。未導入なら `herdr plugin install persiyanov/herdr-reviewr` を案内する（導入はユーザーが了承してから）。
- reviewr が表示するのは、開いたペインの cwd にある Git リポジトリの差分だけ。別リポジトリの差分は、今のペインでは出ない。
- reviewr が自動で開くのは、herdr の worktree 機能でワークスペースを作る・開いたときだけ。通常のワークスペースでは手動で開く。
- `herdr plugin action invoke` は `--workspace` を受け付けない。フォーカス中のワークスペースが対象になるため、別リポジトリを開くときは先に `--focus` 付きでワークスペースを作る。
- エージェントのコマンド実行環境からは TUI の画面が見えない。表示の成否は、ユーザーの目視確認に頼る。

## 手順

1. 対象ディレクトリを決める。指定が無ければ、編集したリポジトリのルートを使う。`~/` を展開した絶対パスで扱う。
   - **対象が作業中のリポジトリ（今のワークスペースの cwd）の場合**: ワークスペースは作らない。手順 2・3 の確認の後、手順 4 を飛ばして手順 5 だけ実行する（フォーカス中のワークスペースが既に対象のため）。
   - **別リポジトリの場合**: 手順 2〜5 をすべて実行する。
2. 対象が Git リポジトリであることを確認する。
   ```
   git -C <dir> rev-parse --show-toplevel
   ```
3. 差分があることを確認する（無ければ報告して終了）。ステージ済みの変更は `git diff` では空になるため、`status` で見る。
   ```
   git -C <dir> status --short
   ```
4. ワークスペースを作る。同じ `--label` が既にあれば `herdr workspace list` で確認し、重複を避ける。
   ```
   herdr workspace create --cwd <dir> --label <リポジトリ名> --focus
   ```
5. reviewr を開く。
   ```
   herdr plugin action invoke open --plugin persiyanov.reviewr
   ```
   応答の `context.workspace_cwd` が `<dir>` であること、`log.status` が `running` であることを確認する。
6. ユーザーに、reviewr が表示されているかの確認を依頼する。表示されていなければ、`herdr plugin list` と herdr のサーバーログ（Linux/macOS は `~/.config/herdr/herdr-server.log`）を確認する。

## 閉じる・やり直す

- reviewr を閉じる: `herdr plugin action invoke close --plugin persiyanov.reviewr`
- ワークスペースを閉じる: `herdr workspace close <ID>`（ID は `herdr workspace list` で確認）。ユーザーが指示したときだけ実行する。

## 注意

- コミット、ステージ（`git add`）、ブランチ作成は行わない。差分を見せるだけ。
- reviewr は、ファイルを編集せず、自動で送信もしない。コメントはユーザーが操作して送る。
- 主な操作キー: `Tab` ペイン切替、`j`/`k` 移動、`v` 行選択、`c` コメント、`?` キー一覧。
- `config.toml` で reviewr 用のキー（例 `prefix+r`）を割り当てる場合は、herdr 既定のキー（`prefix+r` はリサイズモード）と衝突しないか確認する。反応しなければコマンドで開く。

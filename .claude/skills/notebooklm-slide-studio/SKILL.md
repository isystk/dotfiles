---
name: notebooklm-slide-studio
description: Use when the user wants to create a compelling, presentation-ready slide deck (not just a quick slide export) — e.g. 「魅力的なプレゼン資料を作って」「聴衆に見せられるスライドを作りたい」「NotebookLMでプレゼン資料を作成して」「プレゼンの構成から考えてほしい」. Distinct from notebooklm-mcp-ops, which only executes a single NotebookLM operation (e.g. "just generate slides") without audience/story design or quality review.
---

# NotebookLM Slide Studio

## Goal

「それっぽいスライド」ではなく、実際に人へ見せられる高品質なプレゼン資料を作る。
NotebookLMのスライド生成機能は`notebooklm-mcp-ops`スキルに委譲し、本スキルは
**目的ヒアリング → ソース設計 → ストーリー設計 → 生成 → 品質レビュー → 修正**
という制作工程そのものを担う。

生成プロンプト1発ではなく、工程を分けて反復することが品質を決める。

## 前提

- スライド生成・ダウンロードの実操作は必ず`notebooklm-mcp-ops`スキルを呼び出す。
  本スキルはそのラッパーであり、NotebookLM操作コマンドを独自に組み立てない。
- `notebooklm-mcp-ops`が未インストール・未ログインの場合はそのスキルの案内に従い、
  ユーザーへローカル端末での対応を促す（本スキル側では代行しない）。
- ソース資料はプロジェクト内ドキュメントの自律分析を基本とする（ユーザーが個別に
  URL/ファイルを指定した場合はそれも追加投入する）。
- 成果物（`presentation_spec.md`等）の保存先は毎回ユーザーに確認する
  （プロジェクト固定ではなく汎用スキルのため）。

## 全体フロー

```
1. 目的ヒアリング（1問ずつ）
      ↓
2. ソース資料の自律収集
      ↓
3. ストーリー設計（Problem→Insight→Evidence→Solution→Action）
      ↓
4. presentation_spec.md 作成
      ↓
5. NotebookLM投入（notebooklm-mcp-opsへ委譲）
      ↓
6. Presenter Slides生成（notebooklm-mcp-opsへ委譲）
      ↓
7. AI品質レビュー（自己レビュー）
      ↓
8. スライド単位の修正指示
      ↓
9. PDF/PPTX出力・ファクトチェック依頼
```

## Step 1: 目的ヒアリング

グローバルルール「質問は1つずつ」に従い、AskUserQuestion等で1問ずつ確認する。
最低限、以下を埋める（ユーザーが依頼文で既に述べている項目はスキップ）。

- プレゼンの目的（何を理解/納得させ、最終的に何をしてもらいたいか）
- 想定聴衆（役職・専門知識レベル・年代等）
- 利用シーン（社内会議/社外提案/登壇資料等）とプレゼンター有無
  （プレゼンターが口頭説明する前提なら`presenter_slides`、読み物として配布するなら`detailed_slides`）
- 目安の分量（スライド枚数 or 所要時間）
- 対象プロジェクト（ソース収集・保存先の起点になる）

## Step 2: ソース資料の自律収集

- 対象プロジェクトのCLAUDE.md・INDEX.md・確定情報・関連成果物を自律的に読み込み、
  プレゼンの目的に必要な情報だけを抽出する（無関係な資料を大量投入しない）。
- 抽出した情報は資料ごとに役割を明記する（例：市場データ→根拠、検証結果→数値、
  ユーザー課題→問題提起、競合調査→比較）。
- ユーザーが個別にURL/PDF/ファイルを指定した場合は候補に追加する。
- 情報が不足している場合は、ここで初めてユーザーに追加資料の所在を確認する。

## Step 3: ストーリー設計

**いきなりスライドを生成しない。** 先に以下を設計する。

- 核心メッセージ（1文。プレゼン全体で伝えたい主張）
- ストーリーライン：`Problem → Insight → Evidence → Solution → Action`
  （聴衆の認識をBefore→Afterに変化させる構成を優先し、情報の羅列にしない）
- 各スライドの役割と、それぞれで伝える「1つのメッセージ」（1スライド1メッセージ）
- 各スライドのタイトルは説明型ではなく結論型にする
  （弱い例：「BTC自動売買について」／強い例：「自動化の最大の効果は判断の一貫性」）

## Step 4: presentation_spec.md 作成

Step 1〜3の結果を以下のテンプレートにまとめ、NotebookLMへ投入するソースの1つにする。
（Markdownファイルのため、原始人口調は適用せず通常の日本語で作成する）

```markdown
# Presentation Specification

## Objective
{目的}

## Audience
{想定聴衆}

## Core Message
{核心メッセージ}

## Story
Problem → Insight → Evidence → Solution → Action
{各段階の要約}

## Tone
Professional / Simple / Data-driven

## Design
Minimal / Modern / High contrast / Large typography

## Rules
- 1 slide = 1 message
- Conclusion-based titles
- Visuals over text (図解 > グラフ > 比較表 > 数値強調 > 短い箇条書き > 長文)
- No unnecessary decoration
- No paragraphs

## Slide Structure
01 Cover
02 Problem
03 Current Situation
04 Key Insight
05 Evidence
06 Solution
07 How It Works
08 Case Study / Comparison
09 Recommendation
10 Conclusion
```

枚数・構成はStep 1の分量目安・Step 3のストーリーに応じて調整する（固定11枚に縛られない）。

## Step 5-6: NotebookLM投入・生成（notebooklm-mcp-opsへ委譲）

`notebooklm-mcp-ops`スキルを呼び出し、以下を実行する。

1. 今回のプレゼン用にNotebookを新規作成する（命名例: `presentation_{テーマ}_{YYYYMMDD}`）
2. Step 2の収集資料 + Step 4の`presentation_spec.md`を全てsourceとして追加する
3. Presenter/Detailed Slidesを生成する（Step 1で決めた形式・`--language ja`必須）。
   `--focus`にはStep 4の核心メッセージ・ストーリーを渡す。

```bash
nlm create slides "$NB" --language ja --format presenter_slides --focus "<核心メッセージ・ストーリー要約>" --confirm --json
```

## Step 7: AI品質レビュー

生成されたスライド内容（取得できる場合はテキスト/構成）を、以下の観点でスライドごとに
自己レビューする。プロのプレゼンテーションデザイナーとして評価する想定。

- メッセージの明確さ／情報量／視認性／ストーリーとの整合性／データの説得力／
  ビジュアル表現／タイトルの強さ／聴衆への価値

特に以下を探す。

- 内容が重複しているスライド
- 情報量が多すぎるスライド（文章化してしまっている箇所）
- 意味のない箇条書き
- 図解にした方がよいスライド
- タイトルが弱い（結論になっていない）スライド
- 根拠が不足している主張・論理が飛んでいる箇所

「スライド番号 → 問題 → 改善案」の形式で改善優先度順に整理し、ユーザーへ提示する。

## Step 8: スライド単位の修正

Step 7の改善案をもとに、抽象的でなく具体的な修正指示を組み立てる（例:
「本文を50%削減」「タイトルを結論型に変更」「比較図に変える」等）。

NotebookLM側でスライド単位の再生成・修正を行う機能はWeb UI上に存在するが、
`nlm` CLIでの個別スライド編集コマンドは`notebooklm-mcp-ops`スキル時点で未確認。
以下のいずれかをユーザーに確認して進める。

- Web UI側で個々のスライドへ変更指示を出して再生成してもらう（Claude側は指示文のみ用意する）
- `--focus`を修正指示込みで具体化し、`nlm create slides`を再実行する

## Step 9: 出力・ファクトチェック

```bash
nlm download slide-deck "$NB" --id <artifact_id> --format pdf --output <保存先>.pdf --no-progress
```

PDF以外の出力形式（pptx等）が必要な場合は、`nlm download slide-deck --help`で対応形式を
確認してから実行する（未確認のオプションを断定しない）。

出力後、以下は必ず人間の確認を促す（NotebookLM公式もAI生成スライドには不正確な情報が
含まれ得ると明記している）。

- 数値・グラフ・日付・比較・引用・統計・因果関係の主張

## 保存

- `presentation_spec.md`・生成物（PDF等）・レビュー結果の保存先は毎回ユーザーに確認する。
- 対象プロジェクトの規約でINDEX.md等の索引更新が必要な場合は、保存後に更新要否を確認する。

## 注意事項

- 一発生成で完了させない。Step 7の品質レビューを経ずにStep 9へ進まない。
- ソースは目的に必要な情報だけに絞る（無関係な資料の大量投入は品質を下げる）。
- `notebooklm-mcp-ops`が使えない場合、本スキルは目的ヒアリング・ストーリー設計・
  `presentation_spec.md`作成までを行い、生成不可である旨を明示して止める
  （代替手段を無断で実行しない）。

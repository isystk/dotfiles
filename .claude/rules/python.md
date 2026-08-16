---
description: Pythonコーディング規約
paths:
  - "**/*.py"
alwaysApply: false
---

# Python Rules

## Language

- Python 3.12以上を前提とする
- 型ヒントは必須とする
- 組み込み型ジェネリクス（`list[str]`、`dict[str, Any]`など）を使用する
- `Any`の使用は最小限にする
- `None`を返す場合も戻り値の型を明示する

## Style

- PEP 8に従う
- RuffおよびBlackのルールに従う

## Exceptions

- `except Exception:`を安易に使用しない

## Imports

- import順序はRuffの設定に従う
- ワイルドカードimport（`from xxx import *`）は禁止する

## Performance

- 不要なループや重複計算を避ける
- 適切なデータ構造を選択する
- 大量データではジェネレータの利用を検討する

言語非依存の設計・コメント・例外方針は`coding-style.md`に従う。
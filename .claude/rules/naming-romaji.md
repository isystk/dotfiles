---
description: 日本語業務用語の命名規則（ヘボン式ローマ字）
alwaysApply: true
---

# Naming (Romaji) Rules

## Purpose

- 英語化が困難な日本固有の業務用語は、無理に英訳せずヘボン式ローマ字を使用する
- 一般的な技術用語やプログラミング用語は英語を使用する

## Naming Rules

- ヘボン式ローマ字を使用する
- PascalCase・camelCase・snake_caseなど、プロジェクトの命名規則に合わせる
- 同じ日本語には常に同じローマ字を使用する
- 複数の表記を混在させない

## Prefer Romaji

以下のような英訳が曖昧な業務用語はローマ字を優先する

- Kaikei
- Torihiki
- Seikyu
- Nyukin
- Shukkin
- Zaiko
- Kessan
- Shohin
- Tantosha

## Prefer English

以下は一般的な英語を使用する

- User
- Customer
- Product
- Order
- Payment
- Invoice
- Service
- Repository
- Controller
- Request
- Response

## Consistency

- 新しい命名は既存コードの命名規則に合わせる
- 同じ概念に複数の名前を付けない
- 英語とローマ字を混在させない
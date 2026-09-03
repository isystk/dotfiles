---
description: PHP/Laravelコーディング規約
paths:
  - "**/*.php"
alwaysApply: false
---

# PHP Rules

## Language

- PHP 8.3以上を前提とする
- `declare(strict_types=1);` を必須とする
- 型宣言（引数・戻り値・プロパティ）は必須
- readonly を利用できる場合は積極的に利用する

## Style

- PSR-12に従う

## Design

- Value Object・Enum・DTOを優先する
- 配列によるデータ受け渡しを避ける

言語非依存の設計・コメント・例外方針は`coding-style.md`に従う。

# Laravel

以下はLaravelを利用したプロジェクトのみに適用する。

- Service層にビジネスロジックを書く。Controllerは薄くする（リクエスト受付とレスポンス整形のみ）
- ドメインロジックはDomain/Servicesに配置し、Eloquentモデルに複雑なロジックを持たせない
- 外部APIやファイルI/OはFileIO/Services配下に分離し、Controllerから直接呼ばない
- Requestバリデーションは必ずFormRequestクラスに書く。Controller内でのバリデーション禁止
- 入力バリデーションを伴うAction（store/update等）には`StoreRequest`/`UpdateRequest`等の専用FormRequestクラスを1対1で作成する
- DTOで層をまたぐデータを受け渡す場合は`Dto`配下に定義する
- 例外はLaravel標準の例外クラスまたは`Exceptions`配下のカスタム例外を使う。生の`Exception`をthrowしない
- Enumは`Enums`配下に集約し、マジックナンバー・マジックストリングを直書きしない
- Enumは`HasLabel`のような共通interfaceを実装し、`label()`メソッド経由で`__('enums.クラス名_値')`形式の翻訳キーからラベルを取得する。ラベル文字列を直書きしない
- Enum値を保持するEntity属性は、可能な限り`casts()`でEnum型にキャストする。新規カラム追加時は最初からEnumキャストを付与する
- symbol・direction・exchange等の列挙的な値を受け取る関数・メソッドの引数は、`string`型ヒントより対応するEnum型を優先する
- DB関連ルール（N+1・Migration等）は`database.md`に従う
- Controller・Job・BatchはRepositoryやEloquentを直接呼ばず、必ずServiceを経由する
- Serviceのインスタンス化は`app(XxxService::class)`を使う
- Serviceは呼び出し元のクラス単位ではなく、呼び出し元の**メソッド**（ControllerのActionメソッド・Jobの`handle`・Batch）に対して1対1で作成する。クラス名はController/Jobのクラス名ではなく、そのアクション**メソッド名**に合わせて命名する（例: `edit()`アクションには`EditService`、`store()`アクションには`StoreService`。無関係な名前を付けない）
- Serviceの各メソッドはできる限り薄く、単体でテスト可能に保つ。Controller/Job/Batchはそのメソッドを呼び出すオーケストレーションに徹し、ビジネスロジックを自ら持たない
- 複数の呼び出し元から共通利用されるServiceのみ1対1原則の例外とし、共通Service用のディレクトリ（例: `app/Services/Common`）に配置する
- Controllerは共通Service（例: `app/Services/Common`配下）を直接呼び出してはならない。呼び出しは必ず1対1原則の専用Service経由とする
- Serviceはコンストラクタで`XxxRepositoryInterface`をインジェクションし、Eloquentモデルを直接呼ばない
- Serviceはリクエストスコープのグローバルヘルパー（`request()`、`auth()`、`session()`等）を直接呼ばない。Controllerが必要な値（例: `$request->ip()`）を取得し、メソッド引数またはDTOのフィールドとして渡す
- Entity（Eloquentモデル）は親への`belongsTo`は許可するが、子への`hasMany`は避け、子のRepositoryを経由して取得する
- Entity（Eloquentモデル）のメソッド内で他モデルのプロパティ・メソッドに踏み込んではならない（例: `User`モデルのメソッド内で`$this->plan->canAutoTrade()`のように別モデルを参照する）。モデルをまたぐ組み立てはService層またはController層で行う
- テストで`factory()`を使う場合は`tests/BaseTest.php`の`createDefaultXxx()`ヘルパー経由で呼び出す。直接`Model::factory()`を書かない
- 追加した関数には対応するテストコードを必ず作成する
- クラス・メソッドには簡潔なPHPDocコメントを付ける（テストコードは不要）
- 処理が複雑な関数のみ、PHPDocに処理の流れを箇条書きで追記する
- Larastan（level 6）でエラーが出ないよう型定義を書く
- 配列リテラルは値ごとに改行して記述する（横並びで書かない）

## ドキュメントコメント（層ごとのルール。上記の一般PHPDocルールより優先する）

- Controllerクラス: クラスレベルのPHPDocは不要
- Controllerのメソッド: 簡潔な日本語1行docを必須とする。ただし`__construct`は不要
- Controllerに`private`メソッドを定義してはならない。ロジックは呼び出し箇所にインライン展開するか、Service（または上記のcross-modelルールに違反しない範囲でEntityメソッド）へ移す
- Serviceクラス（`app/Services/**`）: クラスレベルのPHPDocは不要。ただし`app/Services/Common`配下のクラスのみ、簡潔な日本語クラスレベルdocを必須とする
- DTOクラス（`app/Dto/**`）: クラスレベルの簡潔な日本語docを必須とする。フィールド・プロパティ（コンストラクタプロパティプロモーションを含む）にも簡潔な日本語docを必須とする

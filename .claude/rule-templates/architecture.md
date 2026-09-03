---
description: レイヤー分離の一般原則
alwaysApply: true
---

# Architecture

- レイヤーの責務を混ぜない（Controller/Presentation ⇔ Service/Domain ⇔ Repository/Infra）
- ControllerやJob（バッチ処理単位）からRepositoryを直接参照しない。必ずServiceのメソッドを経由する
- Jobのエントリポイント（handle等）は引数を取らない設計とし、Serviceの解決はDIコンテナ経由でメソッド本体の中で行う
- ビジネスロジックはフレームワーク非依存の層（Service/Domain）に置き、フレームワーク固有APIに依存させない
- 循環依存を作らない。上位層は下位層に依存してよいが逆は禁止
- 共通処理はHelpers/Utilsに集約し、重複実装を作らない
- 新しい抽象化（インターフェース・基底クラス）は2箇所以上で実際に使う見込みがある場合のみ導入する
- 設定値・定数はコード内に散らさず、設定ファイルまたはEnum/Constants層に集約する
- 将来の要件を先取りした実装をしない（YAGNI）

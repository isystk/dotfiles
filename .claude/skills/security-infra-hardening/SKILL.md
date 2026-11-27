---
name: security-infra-hardening
description: Use when hardening a web service that sits behind a CDN/WAF and a reverse proxy against automated scanning and AI-driven pentest tools — adding edge rules (UA block, rate limit), blocking direct-to-origin access (e.g. Authenticated Origin Pulls / mTLS) in staged rollout, setting up log-based attack detection, or auditing exposed webhooks. Triggers on "オリジン直撃を防ぎたい", "WAFルールを追加", "CDNをすり抜けるアクセスを止めたい", "攻撃ログを監視したい", "AIペンテスト対策", "スキャン対策", "レート制限を入れたい(エッジ側)", "認可を点検して", "IDORがないか確認", "ログインに回数制限を付けて", "アプリ側のセキュリティ点検".
---

# Security Infra Hardening

## Overview

CDN/WAF の背後にある自前サーバー(VPS + nginx 系リバースプロキシ)を、自動スキャン・自律型ペンテストから守るための手順集。
「エッジで止める → オリジンへの直撃を止める → 破られても検知する」の3層を、**本番を壊さず段階的に**入れることが目的。CDN は Cloudflare を例にするが、考え方は他の CDN/WAF にも通じる。

アプリ側(認可・回数制限)の点検は `references/app-authz-checklist.md`(チェックリスト・点検書テンプレート)と `references/app-rate-limit-design.md`(キー設計・実測)を使う。

## スコープ

- 見るもの: CDN/WAF のルール、オリジン直撃の遮断(AOP/mTLS)、アクセスログの検知、Webhook・管理系の露出、本番変更の段階導入、アプリの認可・回数制限(`references/app-*.md`)
- 見ないもの: OS・コンテナイメージのパッチと EOL、ホストの認証設定(SSH・fail2ban)、秘密情報の混入(`check-privacy-and-secrets`)、業務ロジックの悪用(金額操作の冪等性など)
- 侵害が疑われる場合の一次対応は `references/detection-rules.md` の手順 5

## When to Use

- 攻撃ツール(スキャナ・自律型ペンテスト)への対策を、インフラ層で入れたい
- CDN のルール(UA ブロック・レート制限・国別制限)を追加・変更したい
- CDN を経由しない直接アクセス(IP 直打ち、DNS 履歴からの発見)を止めたい
- アクセスログから攻撃の兆候を検知し、Slack 等に通知したい
- n8n など Webhook を持つツールが認証なしで公開されていないか点検したい
- アプリ側の認可(IDOR)・認証フロー・ユーザー列挙を点検したい → `references/app-authz-checklist.md`
- ログインや API に回数制限を設計・実装・実測したい → `references/app-rate-limit-design.md`

## 大原則

1. **補助策と過信しない**: UA ブロックは攻撃側が変えられる。エッジのレート制限は直撃で迂回される。単独で完結する対策はない
2. **読み取り → 設計 → 段階導入 → 検証 → 切り戻し手順の用意**の順に進める。本番変更は1ステップごとに利用者の承認を取る
3. **先にバックアップ、先にカナリア**: 影響の小さい1ホストで先行し、問題なければ残りへ広げる
4. **ゾーン/共通設定に効く変更は、影響する全ホストを列挙して確かめる**(ホスト条件を必ず式に入れる)
5. **切り戻しの順序を決めてから着手**: 「参照する側を先に消し、参照される側を後に消す」

## Workflow

### 1. 現状把握(読み取りのみ)

次を確認し、表にまとめる。変更はしない。

- DNS: プロキシ(オレンジ雲)か DNS のみ(グレー雲)か。ホスト別
- TLS モード(Full (Strict) 以外だと、オリジン認証の前提が崩れる)
- 既存の WAF/レート制限ルールと、プランの上限(Free はルール数・時間窓・選べるフィールドに制約)
- オリジンの公開ポート(80/443 以外が開いていないか)、ファイアウォールの許可元
- ログの形式と場所、実クライアント IP の復元設定(`real_ip` 相当)の有無
- 同一サーバー内のサービスが**公開 URL 経由**で互いを呼んでいないか(オリジン認証や IP 制限の巻き込み事故の原因)

### 2. エッジの対策

→ 詳細: `references/edge-rules.md`、確認コマンド: `references/verification.md`

- UA ブロック、レート制限、国別制限。**式は必ず `ホスト名の条件` から始める**
- 決済・フォーム・Webhook の誤ブロックを、導入前後で curl 確認する

### 3. オリジン直撃の遮断(3段階)

→ 詳細: `references/origin-auth-staged.md`

- ① 観測ログのみ追加(拒否しない)
- ② クライアント証明書を optional で導入して観測(拒否しない)
- ③ on にして強制
- 各段階の間に**ゲート条件**(正規通信の直撃が 0 件、など)と利用者承認を置く

### 4. 検知

→ 詳細: `references/detection-rules.md`

- アクセスログを定期集計し、列挙・注入・認証総当たり・直撃を検知する
- 導入順: 記録のみ → 誤検知の確認 → baseline → 通知を有効化
- 通知は絞る(背景スキャンのたびに鳴らすと、本当の兆候が埋もれる)

### 5. Webhook・管理系の露出点検

- Webhook を持つツール(n8n 等)は、各 Webhook に認証(署名検証・Header Auth)があるか確認する
- 署名検証は、**シークレット未登録だと検証が無効になる**製品がある。登録後に「署名なし POST が 401」を実測する
- 無効化したワークフローに残る Webhook も棚卸しする(有効化で露出するため)
- このスキルの対象外: 秘密情報の混入は `check-privacy-and-secrets`、OS・依存の EOL/CVE は別途用意した脆弱性検査(proxy.isystk.com の `vuln-check.sh` など)で点検する

### 6. 本番変更の原則

- 変更前: 設定ファイルと DB のバックアップ。復元方法まで確認
- 変更中: 1ホストずつ。反映後は**そのホストの正常応答と、同じゾーンの他ホスト**を確認
- 変更後: ログで確認(拒否件数・誤ブロックの有無)。観測期間を決めておく
- 切り戻し: 手順と**順序**を事前に文書化し、判断基準(どの症状で戻すか)も書いておく

## よくある罠

→ `references/pitfalls.md`(real_ip 欠如、`nginx -t` 失敗、削除順序、GUI 管理ツールの保存時検証 など)

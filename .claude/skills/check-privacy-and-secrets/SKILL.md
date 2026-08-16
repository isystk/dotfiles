---
name: check-privacy-and-secrets
description: リポジトリ内に、秘密情報（APIキー、トークン、パスワード、接続文字列等）、個人情報（PII、絶対パス等）、特定プロジェクト固有データが含まれていないか段階的に自動スキャンし、リスクレベル（Critical / Warning / Review / Safe）付きで安全判定を行うスキル。
---

# Check Privacy & Secrets Skill

このスキルは、リポジトリの変更時・コミット前・公開前に、秘密情報・個人識別情報 (PII)・特定プロジェクト固有の情報が誤って混入していないかを自律的かつ高精度にスキャンし、リスクレベル付きで判定するための手順と基準を定義します。

## 🎯 スキルの目的と設計方針

1. **差分最優先 (Diff-First Approach)**
   トークン量と実行時間を最適化するため、`git diff --cached` (ステージ済み) ➔ `git diff` (未ステージ) ➔ 未追跡ファイルの順で優先的にスキャンします。必要に応じてリポジトリ全体やGit履歴に拡張します。

2. **専用スキャナ＋フォールバックのハイブリッド**
   Gitleaks などの専用シークレットスキャナが利用可能な場合は優先利用し、未インストールの場合は `rg` (ripgrep) や `git grep` による高精度ルールベース検索で代替します。

3. **拡張パターンと誤検知の防止**
   クラウド/SaaSのAPIキー（AWS, GitHub, Stripe, Slack等）や、データベース接続文字列 (`mysql://user:pass@...`) などを網羅。単なる `password=` などのキーワード単体ではなく「キー名＋実際の文字列」のペアで検出し、`example` / `changeme` / `null` などのプレースホルダーは `Review` / `Safe` に自動分類して誤検知を低減します。

4. **4段階の機密度判定 (Risk Classification)**
   検出結果を `🔴 Critical`, `🟠 Warning`, `🟡 Review`, `🟢 Safe` の4段階に分類し、明確な対処方針を提示します。

5. **.gitignore と追跡状態の二重検証 (2-Step Check)**
   `.gitignore` に除外対象が定義されているかだけでなく、`git ls-files` を使って実際に追跡（tracked）状態になっていないかを二重チェックします。

---

## 🔄 7段階の標準スキャンフロー

本スキルが呼び出された際は、以下のステップを順番に実行してください。

```text
Scope & Priority:
① git diff --cached (コミット予定の変更 [最優先])
② git diff (作業ツリーの未ステージ変更)
③ 未追跡ファイル (git status --short / git ls-files --others)
④ .gitignore と Git Tracking の二重検証 (git ls-files)
⑤ Secret / PII / プロジェクト固有スキャン (Gitleaks ➔ rg / git grep)
⑥ (必要時 / 高リスク時) Git履歴スキャン (gitleaks detect / git log -p)
⑦ 4段階リスク判定とカウントレポート出力
```

---

### Step 1: 変更差分の最優先スキャン (Diff Scan)
まず今回変更されたコード・設定のみをチェックします。

```bash
# ステージ済みの差分
git diff --cached

# 未ステージの差分
git diff
```

---

### Step 2: 未追跡ファイル・状態のチェック (Untracked Check)
`.gitignore` されていない未追跡ファイルが存在しないか確認します。

```bash
# 状態概要
git status --short

# .gitignore 対象外の未追跡ファイル一覧
git ls-files --others --exclude-standard
```

---

### Step 3: `.gitignore` と Git Tracking の二重検証 (Tracking Verification)
除外されるべき秘匿ファイル（`.env*`, `.setenv.local`, `.gitconfig.local`, `hosts.yml`, `*.pem`, `*.key` 等）が、**誤って Git 管理対象（tracked）になっていないか**検証します。

```bash
# 秘匿ファイルが Git に追跡されていないか検証
git ls-files | grep -E '(\.env|\.setenv\.local|\.gitconfig\.local|hosts\.yml|\.pem$|\.key$)'
```
※ 上記コマンドで結果が返ってきた場合、`.gitignore` に書かれていても **tracked** なので `🔴 Critical` となります。

---

### Step 4: 秘密情報・認証トークン・接続文字列スキャン (Secret Scan)

#### 4-1. 専用ツールスキャン（推奨）
`gitleaks` が利用可能な環境では、以下のコマンドを優先実行します。

```bash
gitleaks detect --source . --no-banner
```

#### 4-2. ルールベーススキャン（フォールバック）
`gitleaks` が利用できない場合は、以下のパターンで `git grep` または `rg` を実行します。

##### 🔑 主要 API キー・トークン
```bash
git grep -i -E '(sk-[a-zA-Z0-9]{20,}|ghp_[a-zA-Z0-9]{20,}|gho_[a-zA-Z0-9]{20,}|github_pat_[a-zA-Z0-9_]{22,}|xox[bapz]-[a-zA-Z0-9]{10,}|AIzaSy[a-zA-Z0-9_-]{33}|rk_live_[a-zA-Z0-9]{20,}|sk_live_[a-zA-Z0-9]{20,})'
```

##### 🔐 秘密鍵・認証ヘッダー
```bash
git grep -i -E '(-----BEGIN (RSA|OPENSSH|EC|PGP)? PRIVATE KEY-----|Bearer\s+[a-zA-Z0-9_\-\.]{20,})'
```

##### 🗄️ 接続文字列 (Database URLs / Connection Strings)
```bash
git grep -i -E '(mysql|postgres|postgresql|mongodb|mongodb\+srv|redis|amqp)://[a-zA-Z0-9_]+:[^@\s]+@[a-zA-Z0-9\.-]+'
```

##### ⚠️ パスワード・シークレットの値直接代入（誤検知防止パターン）
単なる変数名ではなく、引用符で囲まれた定数値が代入されているケースを検出します。
```bash
git grep -i -E '(password|secret|api_key|access_key)\s*[:=]\s*[\'\"][^\'\"]{4,}[\'\"]'
```

---

### Step 5: PII・環境依存情報・プロジェクト固有スキャン (PII & Project Scan)

#### 👤 個人識別情報 (PII)
- **メールアドレス**: 個人の非公開アドレス（`example.com`, `xxxx@xxxx.com`, `noreply@...` 以外の実在アドレス）
- **ドメイン/URL**: 個人の固有WebサイトやブログURL
- **環境パス**: `/Users/username`, `C:\Users\username`, `/home/username` 等のローカル固有パス

```bash
# 実メールアドレスの抽出
git grep -E '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' | grep -v -E '(example\.com|xxxx@xxxx\.com|noreply|schema\.org)'

# ローカル絶対パスの検出
git grep -E '(/Users/[a-zA-Z0-9_-]+|C:\\Users\\[a-zA-Z0-9_-]+|/home/[a-zA-Z0-9_-]+)' | grep -v -E '(example|dummy|myproject|username)'
```

#### 🏢 プロジェクト固有データ
- 特定顧客名、社内案件コード、未公開プロダクト名、社内限定ドメイン／IPアドレスがプロンプトやコメントに残っていないか検証。

---

### Step 6: Git 履歴スキャン (History Scan) [必要時]
大規模変更時や、過去のコミットに含まれていないか懸念がある場合のみ実行します。

```bash
# Gitleaks で全履歴をスキャン
gitleaks detect --source . --log-opts="--all" --no-banner

# または直近コミット履歴の差分確認
git log -p -n 10
```

---

## 🚦 機密度分類ルール (Risk Classification)

検出された項目は、以下の基準で判定・分類します。

| レベル | 対象パターン・状態 | 対処方針 |
| :--- | :--- | :--- |
| **🔴 Critical** | ・本物のAPIキー、秘密鍵（RSA/SSH）、JWT、本番DB接続文字列<br>・秘匿ファイル（`.env`等）の誤追跡（tracked）<br>・実パスワード・シークレットのハードコード | **即時停止・修正必須**<br>（コミット/Pushを中断し、値を環境変数化または削除） |
| **🟠 Warning** | ・個人用メールアドレス、個人のWebサイトURL<br>・特定顧客名・社内案件名・非公開のサービス識別子<br>・ローカル開発環境依存の絶対パス | **ユーザー確認推奨**<br>（ユーザーに公開可否を確認、またはプレースホルダー化） |
| **🟡 Review** | ・`password=changeme`, `secret=example` などのダミー値<br>・`.example` ファイル内のサンプル接続文字列<br>・テストデータ内の疑似キー | **AI文脈判断**<br>（設定例として妥当か判断し、報告に注記） |
| **🟢 Safe** | ・`example.com`, `test@example.com` などの公式標準ダミー値<br>・`GEMINI_API_KEY=xxxxxxxxxxxxxxxx` などのマスク値<br>・`git-secrets` 等の公開テスト用サンプルデータ | **問題なし** |

---

## 📋 判定レポートフォーマット

スキャン完了後、AIエージェントは以下の統一フォーマットで結果を出力してください。

```markdown
### 🛡️ プライバシー＆シークレットスキャン結果

#### 📊 検出サマリー
- 🔴 **Critical**: 0 件
- 🟠 **Warning**: 0 件
- 🟡 **Review**: 0 件
- 🟢 **Safe**: 5 件

#### 🏁 総合判定
**【全項目クリア】** 秘密情報や個人情報の混入はなく、安全な状態です。

#### 🔍 詳細確認項目
（検出項目がある場合は、ファイルパス・該当行・分類レベル・推奨対処法を明記）
```

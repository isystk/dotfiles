# オリジン直撃の遮断: 3段階導入(Authenticated Origin Pulls / mTLS)

CDN を経由しないアクセス(IP 直打ち、過去の DNS 履歴・証明書の透明性ログから見つかった IP)を止める。
Cloudflare の Authenticated Origin Pulls(AOP)を例にする。他の CDN でも「CDN がクライアント証明書を提示 → オリジンが検証」の構造は同じ。

## 0. 前提の確認

- TLS モードが Full (Strict)(オリジンが有効な証明書を持つ)
- **対象ホストの全列挙が終わっている**(リバースプロキシの管理画面、DNS ゾーン、証明書の透明性ログ、DNS 履歴、社内メモ)。AOP は「列挙した全ホスト」に効くため、一覧の確定が前提
  - 除外を先に決める: グレー雲のホスト、外部 SaaS の向き先、ワイルドカード証明書だけのホスト、停止予定のホスト
- 対象ホストがすべてプロキシ(オレンジ雲)。DNS のみ(グレー雲)のホストは CDN を通らないので AOP の対象にできない(混在すると、そのホストが止まる)
- 既存のゾーンレベル/ホスト別 AOP 設定が無い(あれば現状を記録)
- オリジンの 80 番が中身を返さない(返すなら Force SSL で 301 にする)
- 同一サーバー内のサービスが公開 URL 経由で他ホストを呼んでいない(呼ぶなら、段階①のログで見つけて CDN 経由に直す)

## 1. 段階①: 観測ログの追加(拒否しない)

目的: CDN 経由のリクエストと直撃を、ログで区別できるようにする。以降の判定材料と、検知ルールの入力を兼ねる。

nginx のコンテキスト別に、2 か所に分ける(`log_format` と `geo` は http 直下、`access_log` は server)。

```nginx
# http コンテキスト(読み込み順で server より前に来る場所に置く)
# 接続元が CDN のレンジなら 1。レンジは実施日に CDN の公開リストを取得して照合する
# (Cloudflare: https://www.cloudflare.com/ips-v4)
geo $realip_remote_addr $aop_from_cf {
    default 0;
    173.245.48.0/20 1;   # 以下、公開リストの全レンジを列挙
}

# 空白を含みうる項目(偽装できるヘッダ・URI・UA)は末尾に置き、awk の列番号を固定する
log_format aop_watch '$time_iso8601 host=$host sni=$ssl_server_name port=$server_port '
                     'peer=$realip_remote_addr from_cf=$aop_from_cf '
                     'verify=$ssl_client_verify status=$status method=$request_method '
                     'cf_ip="$http_cf_connecting_ip" cf_ray="$http_cf_ray" '
                     'uri="$uri" ua="$http_user_agent"';
```

```nginx
# server コンテキスト(全ホスト共通 include)
access_log /path/to/logs/aop-watch/access.log aop_watch;
```

- ログ用ディレクトリを**先に作る**(無いと `nginx -t` が失敗する)
- URI は `$request_uri` ではなく `$uri`(署名付きクエリをログに残さない)
- 既存のアクセスログはそのまま残る(同じリクエストが 2 か所に記録される)
- 検証: CDN 経由のリクエストで `from_cf=1 cf_ray` あり、`--resolve` で直撃したリクエストで `from_cf=0 cf_ray="-"`
- `verify` は、`ssl_verify_client` 未設定の間は `NONE`。②以降で意味を持つ

観測期間: 3 日程度。平日を含め、定期ジョブ(自動投稿・バックアップ・メンテナンス)が一巡すること。

集計例(列番号はこの log_format 固定。`$4`=port、`$5`=peer、`$6`=from_cf):

```bash
L=/path/to/logs/aop-watch/access.log
# 443 への直撃(CDN 以外)を ホスト × 接続元 で集計
awk '$4=="port=443" && $6=="from_cf=0" {print $2, $5}' $L | sort | uniq -c | sort -rn | head -50
# 80 番への直撃(Full (Strict) では CDN は 443 でつなぐため、80 番は全て直撃)
awk '$4=="port=80" {print $2, $5, $8}' $L | sort | uniq -c | sort -rn | head -50
# サーバー自身・コンテナ内部からの直撃(③で止まる正規通信の候補。0 件であるべき)
awk '$6=="from_cf=0" && ($5=="peer=<サーバー公開IP>" || $5 ~ /^peer=172\.(1[6-9]|2[0-9]|3[01])\./) {print $2, $4, $5, $8}' $L | sort | uniq -c | sort -rn
```

**ゲート ①→②**

- G1-1: サーバー自身・コンテナ内部からの 443 直撃が 0 件。あれば呼び出し先を CDN 経由に直す(`/etc/hosts`・`extra_hosts`・設定値)まで進まない
- G1-2: 80 番の直撃で、ステータス 200 を返すホストが無い(あれば Force SSL を ON にする)
- G1-3: 利用者の承認

**切り戻し(順序固定)**: `access_log` 行を先に削除 → `log_format`/`geo` を削除 → `nginx -t && nginx -s reload`。逆順は未定義エラーで `nginx -t` が失敗する。ログファイルは残してよい。

## 2. 段階②: optional で導入(1 件も拒否しない)

目的: CDN 経由の全リクエストが証明書検証に成功する(`verify=SUCCESS`)ことを、遮断せずに確かめる。

1. CDN の CA 証明書(Cloudflare は公式ページの `authenticated_origin_pull_ca.pem`)を取得し、有効期限と指紋を作業記録に残す
2. サーバーに配置し、**コンテナ内から読めること**を確認(パス誤りで nginx が起動しない/ホストが停止する)
3. 影響最小の 1 ホストにだけ追記(カナリア)。管理ツールの画面で Online のまま、設定ファイルがエラー状態(`.err` 等)になっていないことを確認
   ```nginx
   ssl_client_certificate /path/to/authenticated_origin_pull_ca.pem;
   ssl_verify_client optional;
   ```
4. 残りのホストへ 1 つずつ。**CDN を通らないホスト(グレー雲)には入れない**
5. その後で CDN 側の設定(Cloudflare: SSL/TLS → オリジンサーバー → Authenticated Origin Pulls の Global トグルを On)。**origin を先に optional にしてから CDN を有効化する**

観測 1 週間。集計(②の開始時刻以降の行に限る):

```bash
awk '$6=="from_cf=1" {print $2, $7}' $L | sort | uniq -c          # 全件 verify=SUCCESS であること
awk '$4=="port=443" && $6=="from_cf=0" {print $2, $5, $7}' $L | sort | uniq -c | sort -rn | head -50
```

**ゲート ②→③(全て満たす)**

- G2-1: CDN 経由(`from_cf=1`)の全件が `verify=SUCCESS`。1 件でも `NONE`/`FAILED` があれば原因(ホスト・時刻)を調べる
- G2-2: 443 への直撃のうち**正規の通信**(サーバー自身・コンテナ内部・社内ツール・外部サービスからの呼び出し)が検証者以外 0 件。第三者のスキャンの直撃は遮断対象そのものなので止める理由にしない
- G2-3: 期間中に、自動投稿・ワークフロー・バックアップ・定期メンテナンスでエラーが出ていない
- G2-4: G1-2 が引き続き成り立つ
- G2-5: 利用者の承認

**切り戻し**: ① origin のホストから 2 行を削除 ② その後で CDN の Global トグルを Off。**CDN を先に Off にしない**(③の後は全リクエストが 400 になる)。

## 3. 段階③: on にして強制

`ssl_verify_client optional;` を `on;` に変える(②で入れたホストのみ)。

- 事前に CDN のトグルが On のままであることを確認(**Off のまま on にすると全サイトが 400**)
- カナリア 1 ホスト → 残りの順
- 検証:
  - 直撃(`curl -sk --resolve host:443:<origin-ip> https://host/`)が **400**(nginx の 496)
  - SNI と Host の食い違い(`--resolve other:443:<ip> -H 'Host: target'`)で迂回できない(421 または 400。**200 で別ホストの中身が返ったら直ちに切り戻す**)
  - SNI 無しでも迂回できない
  - CDN 経由は全ホスト正常
  - 80 番は従来どおり(AOP の対象外)
  - サーバー自身から自分のホストの API に届く(認証まで到達、400/403 でない)
  - 証明書の自動更新(HTTP-01 は 80 番。DNS-01 でも影響しないことを手動更新で確認)
  - 翌日の定期メンテナンスで新規の ALERT/WARN が無い
- 切り戻しの判断基準(1 つでも該当したら直ちに): SNI 食い違いで 200、CDN 経由で 400、サーバー自身からの API が失敗、自動投稿の失敗、証明書更新の失敗、利用者の「開けない」報告
- 切り戻し手順: `on;` を `optional;` に戻す(遮断だけなくなる。記録は続く)。管理画面が開けないときは、DB と生成済み設定ファイルの**両方**から該当行を直し、`nginx -t` 成功時のみ reload

## 4. 運用上の恒久的な注意

- CA 証明書の有効期限(取得時に記録)の前に差し替える
- 新しいホストを追加するとき、AOP を入れるか(プロキシ配下か)を判断する
- 管理ツールの画面で保存すると、生成済み設定が書き換わる。DB の値と設定ファイルの両方を見る
- 共通 include(`server_proxy.conf` 等)に `ssl_verify_client` を書かない。グレー雲ホストにも効いて 400 になる(ホストごとに書く)

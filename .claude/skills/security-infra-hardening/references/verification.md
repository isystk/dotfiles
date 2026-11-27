# エッジ対策の確認コマンドと判定基準

自分が管理するサービスにだけ実行する。実行に権限の確認が要る環境では、利用者の端末で実行してもらう。

## 1. 通常応答(全ホスト)

```bash
for h in a.example.com b.example.com example.com; do
  printf '%s ' "$h"; curl -s -o /dev/null -w '%{http_code}\n' "https://$h/"
done
```

- 判定: 変更前に取った値と同じ(200 / 301 / IP 制限ホストは許可 IP から 200)であること

## 2. UA ブロック

```bash
curl -s -o /dev/null -w 'blocked-ua:%{http_code}\n' -A 'tool-name/1.0' https://a.example.com/
curl -s -o /dev/null -w 'prefix-ua:%{http_code}\n'  -A 'other-tool/0.4' https://a.example.com/
curl -s -o /dev/null -w 'normal-ua:%{http_code}\n'  https://a.example.com/
```

- 判定: 前 2 つが 403、通常 UA が 200

## 3. 誤ブロックの回帰確認

決済・フォーム・Webhook など、サーバー間通信や Ajax のパスで、**403 にならない**ことを確認する。

**注意:** Webhook パスへの POST は、署名検証が無い(または未登録)場合に処理がそのまま走り、投稿・通知・外部 API 呼び出しなどの副作用が出る。叩く前に、対象ワークフローを停止するか、副作用の無い検証用パスを使う。止められない場合は実行しない。

```bash
curl -s -o /dev/null -w '%{http_code}\n' -X POST https://a.example.com/path/to/ajax-or-webhook
```

- 判定: アプリ固有の応答(400 / 401 / 405 など)ならよい。**403(エッジの遮断)なら NG**
- 200 が返った場合、エッジは通しているが Webhook 自体は無認証で実行できる(`SKILL.md` 手順5 の点検対象)
- 数日間、WAF のイベントログで、正規の発信元(決済サービス、検索エンジン、Slack 等)が遮断されていないことも見る

## 4. 同じゾーンの他ホスト(キャッシュ・ルールの巻き込み)

```bash
curl -sI https://other.example.com/ | grep -i -E '^(HTTP|cf-cache-status)'
```

- 判定: 動的アプリは `cf-cache-status: DYNAMIC` のまま。HIT/MISS が出たらキャッシュルールが他ホストに効いている

## 5. レート制限の実測

→ アプリ側の回数制限と同じ手順。`references/app-rate-limit-design.md` の「実測」を参照。
エッジの確認は、最初の 5 回が通常応答(302/401/422)、6 回目から 429 になることを見る。

## 6. ログでの確認

- オリジンのアクセスログで、変更後に 403/400/429 が増えたホスト・パスがないか
- 正規の連携(自サーバーから公開 URL を呼ぶ処理)の失敗が出ていないか

# GhostPoster

Ghost Admin APIを使って、iPhoneからMarkdown記事を下書き投稿するSwiftUIアプリです。

## セットアップ

1. `GhostPoster.xcodeproj` をXcodeで開きます。
2. Signing & Capabilitiesで自分のDevelopment TeamとBundle Identifierを設定します。
3. アプリのSettings画面で次の値を入力します。
   - GhostサイトURL
   - Ghost Admin API Key
   - Cloudflare Access Client ID
   - Cloudflare Access Client Secret

入力した接続情報はソースコードやUserDefaultsには保存せず、端末のKeychainに保存されます。

## 公開リポジトリでの注意

- 実サイトURLや認証情報をソースコードへ追加しないでください。
- `.env`、署名ファイル、Xcodeの個人用データは `.gitignore` の対象です。
- 認証情報を誤ってコミットした場合は、履歴から削除するだけでなく該当キーを失効・再発行してください。

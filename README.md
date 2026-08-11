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

## Ghost下書きの形式

- 本文はLexical JSONとして送信し、入力中の段落と改行を維持します。
- 参考URLがある場合は、`参考URL：`の次の行へGhostのBookmarkカードを追加します。
- URL先からタイトル、説明、サイト名、画像などを取得できない場合は、Bookmarkカードを作らずURL文字列のみを挿入します。
- 投稿は公開せず、Ghostの下書きとして保存します。

## 公開リポジトリでの注意

- 実サイトURLや認証情報をソースコードへ追加しないでください。
- `.env`、署名ファイル、Xcodeの個人用データは `.gitignore` の対象です。
- 認証情報を誤ってコミットした場合は、履歴から削除するだけでなく該当キーを失効・再発行してください。

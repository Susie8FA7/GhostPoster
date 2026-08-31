# GhostPoster

Ghost Admin APIを使って、iPhoneからMarkdown記事を下書き投稿するSwiftUIアプリです。

## セットアップ

1. `git submodule update --init --recursive`を実行します。
2. `GhostPoster.xcodeproj` をXcodeで開きます。
3. Signing & Capabilitiesで自分のDevelopment TeamとBundle Identifierを設定します。
4. アプリのSettings画面で次の値を入力します。
   - GhostサイトURL
   - Ghost Admin API Key
   - Cloudflare Access Client ID
   - Cloudflare Access Client Secret

入力した接続情報はソースコードやUserDefaultsには保存せず、端末のKeychainに保存されます。

## ハンズフリー投稿

音声案内に従ってタイトル、本文、参考URL、タグを入力し、Ghostへ下書きを保存できます。音声認識にはApple Speech framework、読み上げにはAVSpeechSynthesizerを使用しています。

### 権限

初回利用時に、次の権限を許可してください。

- マイク
- 音声認識

### 開始方法

アプリ内の「ハンズフリー投稿」を開き、「ハンズフリー投稿を開始」をタップします。

App ShortcutがiOSへ登録されている場合は、Siriから次のフレーズでも起動できます。

- 「GhostPosterでGhost下書きを作成」
- 「GhostPosterで音声下書きを作成」

新しいビルドをインストールした後は、GhostPosterを一度手動で起動してApp Shortcutを登録してください。Siriから起動すると、ハンズフリー投稿画面へ移動してタイトル入力を開始します。

### 投稿フロー

1. タイトルを発話します。約5秒の無音で入力を終了します。
2. 「確定」で本文へ進むか、「修正」でタイトルを入力し直します。
3. 本文を発話します。約10秒の無音で入力を終了します。
4. 「追加」で次の段落を追加するか、「確定」で参考URLへ進みます。
5. クリップボードに`http://`または`https://`から始まるURLがあれば、自動的に参考URLとして設定します。
6. クリップボードにURLがない場合は、URLを発話するか「なし」と答えます。
7. タグを読点、カンマ、またはスペース区切りで発話します。タグが不要なら「タグなし」と答えます。
8. 最終確認で「投稿」と発話すると、Ghostへ下書きを保存します。

### 音声コマンド

| コマンド | 動作 |
| --- | --- |
| `確定` | 現在の項目を確定して次へ進む |
| `修正` / `やり直し` | 現在確認している項目を入力し直す |
| `タイトル修正` | 最終確認からタイトルを入力し直し、確定後に最終確認へ戻る |
| `本文修正` | 最終確認から本文を入力し直し、確定後に最終確認へ戻る |
| `タグ修正` | 最終確認からタグを入力し直し、確定後に最終確認へ戻る |
| `追加` / `本文追加` | 現在の本文を残して次の段落を追加する |
| `タイトルやり直し` | タイトル入力へ戻る |
| `なし` / `URLなし` | 参考URLを設定せずに進む |
| `タグなし` / `ありません` | タグを設定せずに進む |
| `読み上げ` | 最終確認時にタイトル、本文、URLの有無、タグを読み上げる |
| `投稿` | Ghostへ下書きを保存する |
| `キャンセル` | ハンズフリー投稿を終了する |

`読み上げ`ではURL文字列そのものは読み上げません。全文読み上げは最終確認時だけ実行できます。

## GUIDE01状態表示

ハンズフリー投稿画面を開くと、周辺のGUIDE01へBluetoothで接続し、現在の投稿状態と次に利用できる音声コマンドを表示します。音声入力、音声認識、読み上げ、Ghost投稿は引き続きiPhoneが担当します。

GUIDE01へ接続できない場合や投稿中に接続が切れた場合も、iPhone上のハンズフリー投稿は継続します。最終確認で「読み上げ」と発話した場合は、音声認識後に補正された箇所を「変更前／変更後」の差分としてGUIDE01へ表示します。本文全文はiPhone上のプレビューと音声読み上げで確認します。

GUIDE01 SDKはGit submoduleとして参照し、プロトコルライブラリ2.0.0（リビジョン`48914b6`）へ固定しています。ライセンスおよびクレジットは[`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md)を参照してください。

## Apple Intelligenceによる音声認識補正

本文は既存の機械的な表記補正を行った後、AppleのFoundation Models frameworkを利用して端末内で校正します。音声認識に由来する同音異義語、漢字変換、固有名詞、表記揺れを文脈に沿って補正し、意味、文体、語調、情報量、改行は維持します。

タイトル、タグ、日付書式、登録語句は高速な機械補正を使用します。Foundation Modelsを利用できない端末や状態、または校正に失敗した場合は、AI校正前の文章をそのまま使用してハンズフリー投稿を継続します。文章は外部のAIサービスへ送信しません。

## GhostPoster Trace Format

Langfuseなどの外部の観測・分析ツールへ取り込めるように、GhostPosterの操作・処理結果をベンダー非依存のJSON形式で生成します。

JSONには、次のメタデータを記録します。

- ハンズフリー投稿のセッション開始・終了
- 状態遷移
- 音声認識と補正の実行結果
- 補正方法、補正前後の文字数、処理時間
- 読み上げ操作
- Ghost下書き作成の開始・成功・失敗

タイトル、本文、補正前後の文字列、参考URL、タグ、認証情報は含みません。Trace機能、JSONプレビュー、JSON共有はDebugビルド限定で、Settingsの「Traceを有効にする」をオンにした場合だけ動作します。「Trace JSONを共有」からAirDropやファイル保存でMacへ渡せます。共有用ファイルは一時領域へ生成し、共有シートを閉じると削除します。外部サービスへ自動送信することはありません。

形式の詳細は[`docs/GHOSTPOSTER_TRACE_FORMAT.md`](docs/GHOSTPOSTER_TRACE_FORMAT.md)を参照してください。

Macへ共有したJSONは[`Tools/GhostPosterTraceImporter`](Tools/GhostPosterTraceImporter)のCLIで検証・集計できます。

```sh
cd Tools/GhostPosterTraceImporter
swift run ghostposter-trace-import /path/to/ghostposter-trace-YYYYMMDD-HHMMSS.json
```

Importerでは送信内容を`--dry-run`で確認した後、`--send`でLangfuse v4のOpenTelemetryエンドポイントへ送信できます。Langfuse API KeyはGhostPosterやリポジトリへ保存せず、MacのKeychainで管理します。

## Ghost下書きの形式

- 本文はLexical JSONとして送信し、入力中の段落と改行を維持します。
- 参考URLがある場合は、`参考URL：`の次の行へGhostのBookmarkカードを追加します。
- URL先からタイトル、説明、サイト名、画像などを取得できない場合は、Bookmarkカードを作らずURL文字列のみを挿入します。
- 投稿は公開せず、Ghostの下書きとして保存します。

### 音声認識の調整

`VoiceInputManager`の`contextualStrings`には、ブログ入力向けの汎用サンプル語句を設定しています。個人名、実サイト名、記事固有の語句を公開リポジトリへ追加しないでください。必要な固有語は各自のローカル環境に合わせて調整してください。

## 公開リポジトリでの注意

- 実サイトURLや認証情報をソースコードへ追加しないでください。
- `.env`、署名ファイル、Xcodeの個人用データは `.gitignore` の対象です。
- 認証情報を誤ってコミットした場合は、履歴から削除するだけでなく該当キーを失効・再発行してください。

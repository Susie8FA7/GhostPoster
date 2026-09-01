# GhostPoster Trace Importer

GhostPoster Trace Format 1.0のJSONをMac上で検証し、セッションとイベントの概要を表示するSwift CLIです。検証済みTraceをOpenTelemetryへ変換し、Langfuse Cloudへ送信できます。

タイトル、本文、URL、タグ、認証情報はTraceにもOpenTelemetry payloadにも含めません。

## 実行

```sh
cd Tools/GhostPosterTraceImporter
swift run ghostposter-trace-import /path/to/trace.json
```

サンプルを読み込む場合:

```sh
swift run ghostposter-trace-import Examples/sample-trace.json
```

## Langfuse設定

```sh
swift run ghostposter-trace-import configure
```

Base URLは設定ファイル、Public KeyとSecret KeyはmacOS Keychainへ保存します。日本リージョンの既定値は`https://jp.cloud.langfuse.com`です。

設定確認と削除:

```sh
swift run ghostposter-trace-import config show
swift run ghostposter-trace-import config clear
```

環境変数`LANGFUSE_BASE_URL`、`LANGFUSE_PUBLIC_KEY`、`LANGFUSE_SECRET_KEY`が設定されている場合は、保存済み設定より優先します。

## OpenTelemetry変換の確認

Langfuseへ送るOTLP/HTTP JSONを、送信せず画面へ表示します。

```sh
swift run ghostposter-trace-import /path/to/trace.json --dry-run
```

1つのGhostPosterセッションを1つのTraceへ変換し、各イベントをルートSpan配下の子Spanとして生成します。

Trace Format 1.0の`state_changed`は、次の状態遷移までの時間を持つPhase SpanへImporter側で変換します。たとえば`titleReview`は`ghostposter.phase.title_review`になります。生の`state_changed`点Spanは重複表示を避けるため送信しません。

`posting`と`completed`は`system_time`、それ以外は現時点では`mixed_user_and_system`として分類します。この分類は粗い状態別プロファイル用であり、発話時間や無音待機などの詳細な内訳はTrace Formatの将来版で扱います。

## Langfuseへ送信

```sh
swift run ghostposter-trace-import /path/to/trace.json --send
```

Langfuse v4対応の`/api/public/otel/v1/traces`へOTLP/HTTP JSONで送信し、`x-langfuse-ingestion-version: 4`を付与します。旧Ingestion APIは使用しません。

## テスト

```sh
swift test
```

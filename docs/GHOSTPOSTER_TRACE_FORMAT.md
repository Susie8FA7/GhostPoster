# GhostPoster Trace Format 1.0

GhostPoster Trace Formatは、GhostPosterの処理状況を外部の観測ツールへ渡すための、ベンダー非依存なJSON形式です。Langfuse固有のIDやAPI構造には依存しません。

現在の実装はDebugビルド限定です。Settingsの「Traceを有効にする」をオンにするとメモリ上へ記録し、同じセクションの「JSONプレビュー」から内容を確認できます。「Trace JSONを共有」では一時JSONファイルを生成し、AirDropやファイル保存でMacへ渡せます。共有シートを閉じると一時ファイルを削除します。Releaseビルドでは記録しません。

## プライバシー方針

トレースには次の内容を保存しません。

- 認識されたタイトルや本文
- 補正前後の文字列
- 参考URL
- タグ
- GhostやCloudflareの認証情報
- エラーの詳細メッセージ

代わりに、状態名、処理結果、文字数、処理時間、補正手段などのメタデータだけを記録します。

## JSON例

```json
{
  "format": "ghostposter-trace",
  "format_version": "1.0",
  "generated_at": "2026-08-31T00:00:00Z",
  "sessions": [
    {
      "id": "00000000-0000-0000-0000-000000000000",
      "started_at": "2026-08-31T00:00:00Z",
      "ended_at": "2026-08-31T00:01:00Z",
      "outcome": "succeeded",
      "events": [
        {
          "sequence": 1,
          "timestamp": "2026-08-31T00:00:00Z",
          "name": "session_started"
        },
        {
          "sequence": 2,
          "timestamp": "2026-08-31T00:00:20Z",
          "name": "transcript_corrected",
          "state": "body",
          "scope": "body",
          "correction_source": "foundation_models",
          "changed": true,
          "input_character_count": 42,
          "output_character_count": 44,
          "duration_milliseconds": 850
        }
      ]
    }
  ]
}
```

## 初期イベント

| `name` | 用途 |
| --- | --- |
| `session_started` | ハンズフリー投稿セッション開始 |
| `state_changed` | 状態機械の遷移 |
| `speech_recognition_completed` | 音声認識結果の受領 |
| `transcript_corrected` | 機械補正またはFoundation Models補正 |
| `read_aloud_requested` | 最終確認の読み上げ開始 |
| `ghost_draft_started` | Ghost下書き作成開始 |
| `ghost_draft_finished` | Ghost下書き作成の成功または失敗 |
| `session_finished` | セッション終了 |

未知のイベント名や未知のフィールドを受け取ったImporterは、それらを無視して既知のデータを処理できます。

# mmconverter

**mmconverter**はSlackからエクスポートしたデータをMattermostにインポートできる形式に変換するPowerShellスクリプトです。

添付ファイルが存在する場合はダウンロードし、変換データと一緒にアーカイブしたzipファイルを出力します。

## 動作確認環境

PowerShell 7.2 on Windows 10 21H2

## 実行方法

```
.\mmconverter.ps1 [-exportZip] slack-export.zip [-exportUserCsv] slack-users.csv [-teamName] "workspace name" [[-outputZip] import.zip] [-jsonlOnly]
```

- **exportZip** Slackのエクスポート機能で生成されたzipファイルのパスを指定します。 **必須**
- **exportUserCsv** Slackのユーザー一覧ページのエクスポート機能で生成されたCSVファイルのパスを指定します。 **必須**
- **teamName** Mattermostのインポート先となるチーム名を指定します。Slackのワークスペース名に相当します。 **必須**
- **outputZip** スクリプトが出力するMattermostインポート用zipファイルのパスを指定します。省略した場合はカレントディレクトリに**import.zip**として出力されます。既に同名のzipファイルが存在する場合は上書きします。
- **jsonlOnly** カレントディレクトリに**import.jsonl**のみを出力します。添付ファイルのダウンロードは行いません。既にimport.jsonlが存在する場合は上書きします。

## mmetlとの違い

- mmetlでは変換対象にならない以下のデータを含めたインポートデータの生成
  - リアクション(使用している絵文字は別途登録する必要あり)
  - 「以下にも投稿する: <チャンネル名>」にチェックを入れてスレッドで投稿したメッセージ
  - ~~Webhook経由で投稿したメッセージ~~(実装予定)
  - 英数字以外の文字を含むチャンネル名
- 変換データの調整
  - generalチャンネルをtown-squareにマッピング
  - ~~複数行のコードブロックの表示が崩れる場合があるのを修正~~(実装予定)
  - コードブロック中の記号がURLエンコードされてしまうのを修正(実装予定)
- 入出力データ
  - ユーザーのメールアドレスをエクスポートCSVファイルから取得(Slackへのbot登録が不要になる)
  - zipファイルの展開、圧縮までスクリプト内で実行


注: 特に理由がなければmmetlを使用することをお勧めします。

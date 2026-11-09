# サービスアイコン

追加画面、管理画面、ポップオーバー、メニューバーには、同じローカル画像を表示します。外部の favicon を取得する通信はありません。

カタログに登録された217件はすべて `ServiceIcons.png` に対応します。123件は公開アイコン素材から作成し、残る94件は製品ロゴと誤認しない色付き略字アイコンです。素材のない製品に別会社のロゴを流用しません。新規サービスを追加するときは、アトラスと `ServiceIconCatalog.swift` と `service-icons.json` を更新してください。`scripts/verify-service-icons.py` が対応漏れを検出します。

- [Lobe Icons](https://github.com/lobehub/lobe-icons) の PNG（MIT、取得時の commit `ea434b96e75813517b377825e01c0df61dee8836n`）。ライセンス本文は [Lobe-Icons-LICENSE](licenses/Lobe-Icons-LICENSE)。
- [Simple Icons](https://github.com/simple-icons/simple-icons) の SVG とブランド色（CC0 1.0、取得時の commit `1bb2f6e6ea50f920de8d2f3d273ae48564a5eaee`）。ライセンス本文は [Simple-Icons-LICENSE.md](licenses/Simple-Icons-LICENSE.md)。
- [service-icons.json](service-icons.json) に、各サービスで使った素材と略字表示の区別を記録しています。

ロゴの商標権は各社に帰属します。Cooltime は各社と提携していません。素材の著作権ライセンスは商標の使用許諾を意味しません。

素材の更新方法: 上記のリポジトリをチェックアウトして `python3 scripts/generate-service-icons.py --lobe /path/to/lobe-icons --simple /path/to/simple-icons` を実行します（Pillow と Inkscape が必要）。その後 `python3 scripts/verify-service-icons.py` を実行します。

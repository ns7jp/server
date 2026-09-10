# lab-base01：マージ演習の原画像

[結果票へ戻る](../../2026-09-10-lab-base01-git-merge-practice.md)

本人提供の原画像5枚を無加工で保存。ユーザー名・ホスト名・演習パス・コミットSHAを含む。
秘密鍵本文やパスワードは含まない。ハッシュはコピーの一致確認用で、日時や実施主体の第三者認証ではない。

[元ファイル名・サイズ・SHA-256](manifest.json) / [SHA256SUMS](SHA256SUMS.txt)

## E01 Fast-forwardとmainの保持

![Fast-forwardとmainの保持](E01-fast-forward.png)

## E02 共通mainからの分岐と競合

![共通mainからの分岐と競合](E02-conflict.png)

## E03 競合解消と2つの親

![競合解消と2つの親](E03-resolved.png)

## E04 競合の再現とabort前後のSHA一致

![競合の再現とabort前後のSHA一致](E04-abort.png)

## E05 mainへの復帰と全ブランチ履歴

![mainへの復帰と全ブランチ履歴](E05-final.png)

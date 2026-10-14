# PhotoCraft

Image editing; an open-source, clean-room reimplementation of Adobe Photoshop, rebuilt in pure Rust.

## インストール方法

前提: Ubuntu/Debian 系、インターネット接続あり。`apt-get` を使うため root 権限で実行してください。

```sh
git clone https://github.com/storytold/photocraft.git /opt/photocraft
curl -fsSL https://raw.githubusercontent.com/hirogura/photocraftweb/main/install.sh -o /opt/photocraft/install.sh
chmod +x /opt/photocraft/install.sh
cd /opt/photocraft
./install.sh
```

上記1本で、ビルド環境の導入から Web 版のビルド・配信まで行います。
完了後、ブラウザで `http://<ホスト>:3365` を開いてください。

オプション:

```sh
./install.sh --port 8080   # 別ポートで配信
./install.sh --skip-build   # ビルドを飛ばして配信だけやり直す
./install.sh --no-serve     # ビルドのみ（配信しない）
```

## GridCraft

Node.js + Vite + React 製の GridCraft を 3366 番ポートでセルフホストします。

前提: Ubuntu/Debian 系、インターネット接続あり。`apt-get` を使うため root 権限で実行してください。

```sh
git clone https://github.com/storytold/gridcraft.git
# 本リポジトリを取得済みの場合はそのディレクトリで実行
./gridcraftweb-install.sh
```

上記1本で、ビルド環境の導入から Web 版のビルド・配信まで行います。
完了後、ブラウザで `http://<ホスト>:3366` を開いてください。

オプション:

```sh
./gridcraftweb-install.sh --port 8080   # 別ポートで配信
./gridcraftweb-install.sh --skip-build   # ビルドを飛ばして配信だけやり直す
./gridcraftweb-install.sh --no-serve     # ビルドのみ（配信しない）
```

## ライセンス

MIT OR Apache-2.0（詳細は `LICENSE-MIT` / `LICENSE-APACHE`）。

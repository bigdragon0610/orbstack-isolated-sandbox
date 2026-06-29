# orbstack-isolated-sandbox

npm の `postinstall` などサプライチェーン攻撃が怖いので、**OrbStack の隔離マシン (isolated machine)** 上で untrusted な依存関係やビルドスクリプトを実行するための設定リポジトリ。

Mac のファイル・SSH 鍵・環境変数から切り離された Linux 環境を `cloud-init` で再現可能に構築する。

## なぜ隔離マシンなのか

OrbStack の通常マシンは Mac のファイルシステム (`/mnt/mac`)・SSH エージェント・ネットワークと統合されている。悪意ある依存関係や `postinstall` スクリプトはこれらに到達でき、ファイルや SSH 鍵、環境変数を読み取れてしまう。

隔離マシンは以下を**既定で遮断**する:

- Mac のファイルシステムをマウントしない (`/mnt/mac` なし)
- macOS ホストへネットワーク到達不可・`mac` コマンド不可
- SSH エージェントのフォワーディングをしない
- USB / シリアル / サウンドのパススルーをしない

ただしインターネットアクセス、`*.orb.local` ドメイン、Mac からの SSH / `orb` アクセスは引き続き使える。

> [!WARNING]
> 隔離マシンはリスクを下げるが**完全なセキュリティ境界ではない**。全マシン／コンテナは OrbStack の単一 Linux VM 上でカーネルを共有しており、隔離は Linux カーネルのセキュリティモデルに依存する。日常的な untrusted コード（サードパーティ依存や AI エージェント）には十分だが、**カーネルを能動的に攻撃するマルウェア解析には使わないこと**。その場合は独自カーネルを持つフル VM を使う。

## 前提

- OrbStack がインストール済み（`orb version` で確認。本リポジトリは v2.2.1 で確認）
- `orb` CLI が PATH 上にあること

## マシンの作成方法

### 1. 隔離マシンを作成

付属の `create-machine.sh` を使うのが簡単。マシン作成 → プロビジョニング完了待ち →
**今使っているターミナルの terminfo をマシンへ動的にコピー**まで行う。

```bash
# このリポジトリのルートで実行（マシン名は任意、既定は sandbox）
./create-machine.sh sandbox
```

ネットワーク隔離や初期マウントを足したい場合は `EXTRA_ARGS` で渡す:

```bash
EXTRA_ARGS="--isolate-network --mount ~/project:/work" ./create-machine.sh sandbox
```

素の `orb` で作る場合は次の通り（terminfo コピーは後述の手順を参照）:

```bash
orb create --isolated ubuntu sandbox -c cloud-init/user-data.yml
```

- `--isolated` : 隔離マシンとして作成（ファイル共有・統合を無効化）
- `-c / --user-data` : cloud-init のユーザーデータファイルを指定して自動プロビジョニング
- `ubuntu` : ディストリビューション（`ubuntu:24.04` のようにバージョン指定も可）
- `sandbox` : マシン名（任意）

GUI の場合は、マシン作成時に **Isolate machine** をオンにする。

### 2. ネットワークも隔離したい場合（任意）

他の OrbStack マシンやホスト IP もブロックしつつインターネットは維持する:

```bash
orb create --isolated --isolate-network ubuntu sandbox -c cloud-init/user-data.yml
```

### 3. マシンに入る（初回ログインでユーザーツールが導入される）

```bash
orb -m sandbox          # シェルに入る
# または
ssh sandbox@orb         # SSH
```

OrbStack は cloud-init の**後**に「macOS ユーザー名のユーザー」を作成する。そのため Volta / Node / npm / Claude Code / Kiro CLI といったユーザー固有ツールは、cloud-init ではなく**初回ログイン時にそのユーザー自身で自動導入**される（ネットワーク経由のダウンロードのため数分かかる）。neovim と AWS CLI は cloud-init の boot 時にシステム全体へ導入済み。

### 4. プロビジョニング完了の確認

```bash
# システム側（boot 時）の完了確認
orb -m sandbox -- cloud-init status   # status: done

# ユーザー側（初回ログイン時）の完了確認
orb -m sandbox -- bash -lc 'test -f ~/.sandbox-provisioned && echo user-provisioned'
```

> [!NOTE]
> 初回ログインのツール導入が終わったら、新しいシェルを開く（または `source ~/.bashrc`）と PATH が通る。導入ログは `~/.sandbox-setup.log` に残る。

### 5. 削除

```bash
orb delete sandbox
```

## 必要なフォルダだけマウントする

隔離マシンは既定では Mac のファイルを一切共有しない。**特定のフォルダだけ**を選択的に共有できる。

### 作成時にマウント

`--mount SOURCE[:DEST]` を使う。複数回繰り返せる。

```bash
# ~/project をマシン内の同じパスに共有
orb create --isolated --mount ~/project ubuntu sandbox

# ~/project をマシン内の /work に共有（マウント先を変更）
orb create --isolated --mount ~/project:/work ubuntu sandbox

# 複数フォルダを共有
orb create --isolated \
  --mount ~/project:/work \
  --mount ~/data:/data \
  ubuntu sandbox -c cloud-init/user-data.yml
```

### 作成後にマウントを変更

既存マシンには `orb config set` で設定変更できる。マシンが起動中なら**再起動が必要**。

```bash
# 単一マウント
orb config set machine.sandbox.mounts '~/project:/work'

# 複数マウントはカンマ区切り
orb config set machine.sandbox.mounts '~/a,~/b:/work'

# 反映のため再起動
orb restart sandbox
```

### その他の後から変更できる設定

```bash
orb config set machine.sandbox.isolated true            # 隔離の ON/OFF
orb config set machine.sandbox.isolate_network true     # ネットワーク隔離
orb config set machine.sandbox.forward_ssh_agent true   # SSH エージェント転送
```

> [!TIP]
> マウントは「必要なプロジェクトフォルダだけ」を共有するのが安全。ホームディレクトリ全体や `~/.ssh` などはマウントしないこと。マウントしたフォルダ内のコードは Mac 上の実体を読み書きできる点に注意。

## neovim 設定（マウントせず git で同期）

neovim 設定は**マウントしない**。理由:

- OrbStack のマウントは read-write のみ（read-only 指定不可）。`~/.config/nvim` をマウントすると、サンドボックス内の untrusted コードが `init.lua` 等を改変でき、次に **Mac 側で nvim を開いた瞬間**にそのコードが Mac 権限で実行され、隔離を突破される。
- treesitter パーサや native プラグインは macOS / Linux でバイナリが異なり、`~/.local/share/nvim` まで共有すると壊れる。

そこで dotfiles を git で**一方向 clone** する。`user-setup.sh` が初回ログイン時に以下を実行する。

```bash
git clone --depth 1 https://github.com/bigdragon0610/nvim-config.git ~/.config/nvim
```

設定（コード）は Mac 側リポジトリ経由でのみ更新され、プラグインは各マシンで Linux 用に新規導入される。別のリポジトリを使う場合は `cloud-init/user-data.yml` 内の clone URL を変更する。プライベートリポジトリにする場合は HTTPS では認証が必要になるため、`orb create --isolated --forward-ssh-agent ...` で SSH エージェントを転送するか、トークンを用意する。

## ターミナルの terminfo（Ctrl+L が効かない時）

Ghostty / kitty / WezTerm など独自 `TERM` を使うターミナルだと、その terminfo がマシン側に無く、`clear-screen`（Ctrl+L）等が動かない。terminfo は端末・バージョン依存なので cloud-init に静的同梱はせず、`create-machine.sh` が**作成後に現在の `$TERM` の定義を動的にコピー**する。

素の `orb create` で作った場合は、Mac 側で一度だけ実行する:

```bash
infocmp -x "$TERM" | orb run -m sandbox tic -x -
```

## cloud-init について

`cloud-init/user-data.yml` がプロビジョニング設定（cloud-config 形式）。導入するツールの一覧と方法はこのファイルを参照。

設計方針（2 フェーズ構成）:

- **boot 時 (root)**: cloud-init の `runcmd` でシステム全体ツールを導入（`/usr/local/sbin/system-setup.sh`）。
- **初回ログイン時 (ログインユーザー)**: `/etc/profile.d/zz-sandbox-setup.sh` が `/usr/local/sbin/user-setup.sh` を 1 回だけ実行し、ユーザー固有ツールを導入する。OrbStack は cloud-init の後にユーザーを作成するため、boot 時点では対象ユーザーが存在せずこの方式を採る。導入済みかは `~/.sandbox-provisioned` で判定し、再ログインでは再実行しない。
- npm の `postinstall` リスク対策として、ユーザーの `~/.npmrc` に `ignore-scripts=true` を設定する。スクリプト実行が必要な信頼できるパッケージだけ `npm install --foreground-scripts` 等で個別に許可する。
- **git-secrets**（AWS 謹製）を導入し、AWS/GCP の認証情報がコミットに紛れ込むのを pre-commit で検知する。boot 時に `make install` でシステム全体へ入れ、初回ログイン時に `git secrets --register-aws --global` 等でグローバル有効化＋`init.templateDir` 設定を行うため、以降 `git clone` / `git init` するリポジトリすべてでフックが効く。
- AWS EC2 など他のクラウドと同じ user-data 形式が使えるため、本番デプロイ前のローカル検証にも流用できる。

詳細は [OrbStack Cloud-init ドキュメント](https://docs.orbstack.dev/machines/cloud-init) および [cloud-init 公式ドキュメント](https://cloudinit.readthedocs.io/en/latest/) を参照。

## 導入後の認証

ツールは導入されるが、認証・認証情報の設定は手動で行う。

- **AWS**: `aws configure`、SSO、または環境変数で設定（隔離マシンには Mac の `~/.aws` は共有されない）。
- **Kiro CLI / Claude Code**: 初回実行時にブラウザでの認証へ誘導される（隔離マシンでもインターネット経由の認証は可能）。
- Volta が PATH に反映されない場合は一度ログインし直すか、`source ~/.bashrc` を実行する。

## 機密情報の扱い

- cloud-init ファイルは平文で保存・共有される。トークン・パスワード・秘密鍵を直接書かないこと。
- 隔離マシンへ秘密情報を渡す必要がある場合は、マシン作成後に手動投入するか、必要最小限のフォルダを一時的にマウントする。

## 参考リンク

- [Isolated machines · OrbStack Docs](https://docs.orbstack.dev/machines/isolated)
- [Cloud-init · OrbStack Docs](https://docs.orbstack.dev/machines/cloud-init)
- [File sharing · OrbStack Docs](https://docs.orbstack.dev/machines/file-sharing)
- [Commands · OrbStack Docs](https://docs.orbstack.dev/machines/commands)

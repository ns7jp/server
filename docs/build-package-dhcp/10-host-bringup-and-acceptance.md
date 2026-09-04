# 立ち上げ環境の選択肢と受け入れ試験

> 💡 **初めて読む方へ**: この文書は「まだ確認していない項目」を、`dhcp-01`とクライアント役VMの2台構成で一気に埋めるための手順書です。案件パック全体の地図は[初心者ガイド](beginner-guide.md#10-立ち上げと受け入れ試験)を参照してください。

これまでに確認できているのは、リポジトリのcheckout環境だけで完結する範囲です。

- `dhcp_server` roleの`ansible-lint --offline`（production profile）
- `ansible-playbook ... playbooks/dhcp.yml --syntax-check`
- `pytest tests/test_portfolio_artifacts.py -k internal_markdown_links`

これらはいずれも対象ホストが存在しなくても実行できる静的チェックであり、実際に`dhcpd.conf`を配置してDHCPv4のリースを払い出せるかどうかは何も確認していません。次の項目がまとめて`NOT RUN`のまま残っています。

- `dhcp.yml`の新規適用・冪等性（DIT-01）
- DORA（DISCOVER/OFFER/REQUEST/ACK）の実測（DIT-02、DNW-06）
- 固定予約・プール枯渇・リース更新・解放・再起動後の永続化（DIT-03〜07）
- サービス停止からの検知・復旧（DIT-09）、中央監視統合（DIT-10）、バックアップ・復元（DIT-11）
- UFW・ファイル権限・AppArmor・SSH hardening・監査ログ（DST-01〜05）
- 構築直前のrogue DHCP非存在確認（DST-06、NFR-08）
- ネットワーク実機検証全項目（DNW-01〜09）

**base Linux版の[立ち上げと受け入れ試験](../build-package/10-host-bringup-and-acceptance.md)は「恒久ホストを1台用意すれば大半が埋まる」という構成でした。本パックはそれと事情が異なります。** DHCPの中心機能であるDORAは、クライアントがまだIPを持たない状態でセグメント全体へ`DHCPDISCOVER`をブロードキャストすることから始まります。ブロードキャストを送る側（クライアント）と受ける側（`dhcp-01`）が別の実体として同一L2セグメントに存在しない限り、この4-way handshakeはそもそも発生しません。したがって本パックで埋めるべき最小構成は「1台の恒久ホスト」ではなく、**`dhcp-01`とクライアント役VMという2台を同一セグメントに置くこと**です。

使い捨てのGitHub-hosted runnerや単発のコンテナでこの2台構成を代替できない理由は[README](README.md#検証環境)と[04-network-ip-plan.md](04-network-ip-plan.md#2-払い出し対象セグメントの内訳)にも記載していますが、要点は次のとおりです。

- CIランナーは1ジョブにつき1台の使い捨てVM（または1コンテナ）であり、同一セグメントにもう1台のDHCPクライアントを常設できない
- 既存の[二セグメント障害ラボ](../../labs/network-troubleshooting/README.md)はDockerの既定bridgeネットワークを使っており、Docker自身がコンテナのIPをIPAMで払い出してしまうため、コンテナ内から素直にDISCOVERを送出してdhcpdへ届ける構成にはひと手間が必要になる
- この2点から、本パックはDockerラボを正本とせず、**VirtualBoxなどのVM/実機での2台構成を正本**とする

## 0. 何を用意するか

| 選択肢 | 目安費用 | 向き |
| --- | --- | --- |
| VirtualBox Host-Onlyネットワーク | 0円 | **推奨。** ホストOS側のアダプタにIPを持たせられるため、[要件定義書](00-requirements.md)のゲートウェイ`192.168.50.1`（VirtualBoxならHost-Onlyネットワークのホスト側）をそのまま体現できる |
| VirtualBox Internalネットワーク | 0円 | より厳密な隔離。ホストOSからもゲスト間通信を覗けず、VirtualBox内蔵DHCPサーバーも存在しないため、rogue DHCP混入の経路が少ない。ただしホストOS側から`ping`等で直接到達できないため、管理・デバッグ用に別NICを1本足す必要がある |
| 自宅LAN上の予備セグメント（別VLANなど） | 0円 | 実機のL2ブロードキャストを体験できるが、既存LANのDHCPサーバーと衝突しないよう相応の知識が要る。一般的な検証にはVirtualBoxのHost-Only/Internalの方が安全 |
| クラウドVPCのプライベートサブネット | 月数百円〜 | 多くのクラウドはL3でルーティングされるサブネット実装であり、素のブロードキャストDHCPをそのまま通さない場合が多い。[要件定義書](00-requirements.md)の対象外に記載のとおり、`apply`/`destroy`相当の実行証跡がない限り本案件の構築実績には含めないため、本書でも正本にはしない |

本書では**VirtualBox Host-OnlyネットワークまたはInternalネットワーク**を基本の立ち上げ環境として扱います。以降の手順はどちらでも共通ですが、差分がある箇所には都度注記します。

最小構成の目安は次のとおりです。isc-dhcp-server自体は軽量なデーモンですが、`common` roleが導入するchrony・unattended-upgrades・UFW・AppArmorも動くため、512MBでは心もとありません。

| VM | vCPU | メモリ | ディスク | OS |
| --- | --- | --- | --- | --- |
| `dhcp-01` | 1 | 2GB以上 | 20GB以上 | Ubuntu Server 24.04 LTS（[要件定義書](00-requirements.md)固定値） |
| クライアント検証VM | 1 | 1GB以上 | 10GB以上 | Ubuntu Server 24.04 LTSなど、`isc-dhcp-client`・`tcpdump`が使えるLinux。[構築手順書](05-build-procedure.md)・[試験仕様書](06-test-specification.md)のコマンド例は`dhclient`前提のため、`dhclient`を持たないOS（Windowsクライアント等での`ipconfig /release`・`/renew`代替）は本書の手順の対象外とする |

クライアント検証VMのOSを`dhcp-01`と同じUbuntu Server 24.04 LTSに揃えておくと、`ip -br link`・`dhclient -v`・`tcpdump`のオプションや出力形式が両ホストで一致し、[構築手順書](05-build-procedure.md)5節の手順をそのまま流用できます。異なるディストリビューションを使う場合は、コマンド名やパッケージ名の差分（例: `isc-dhcp-client`の有無）を自分で吸収してください。

## 1. 立ち上げ前に決めておくこと

作業を始める前に、次を書き出しておきます。あとから思い出せません。

| 項目 | 記入 |
| --- | --- |
| VirtualBoxネットワークの種別（Host-Only / Internal）と名前 | |
| `dhcp-01`のNIC構成（管理用NIC・払い出し対象セグメント用NIC） | |
| クライアント検証VMのNIC構成 | |
| `dhcp_server_interface`に設定する予定のinterface名（`ip -br link`で後から確定） | |
| VirtualBox内蔵DHCPサーバーを無効化したことの確認（Host-Only使用時のみ、2.2節） | |
| 作業してよい時間帯 | |
| 接続不能になったときの復旧手段（VirtualBoxのGUIコンソール） | |

**SSHだけに依存しないでください。** VirtualBoxはVMウィンドウそのものがシリアルコンソール相当の役割を果たします。UFWやNIC設定を誤ってSSHが届かなくなっても、VirtualBox Managerからそのままログインして復旧できることを、firewallを触る前に必ず確認しておきます。

## 2. VirtualBoxネットワークの作成

### 2.1 NIC構成の考え方

`dhcp-01`・クライアント検証VMのどちらも、NICを2本にすることを推奨します。

| NIC | 用途 | ネットワーク種別 |
| --- | --- | --- |
| NIC1（管理用） | 管理端末からのSSH、`apt`によるパッケージ取得 | NAT（既定のインターネット到達性のため） |
| NIC2（払い出し対象セグメント用） | DHCPペイロード（`dhcp-01`側）、DORA実測（クライアント側） | Host-OnlyネットワークまたはInternalネットワーク（`192.168.50.0/24`） |

NIC1をNATにしておくと、`apt-cache policy isc-dhcp-server`（[構築手順書](05-build-procedure.md)3.1節）や`ansible-galaxy collection install`のようなインターネットアクセスを要する手順を、払い出し対象セグメントの隔離を崩さずに実行できます。NIC1を持たず払い出し対象セグメントのみに接続する構成も可能ですが、その場合は別途プロキシ経由のパッケージ取得手段を用意してください。

### 2.2 Host-Onlyネットワークを使う場合

1. VirtualBox Managerの「ツール」→「ネットワーク」→「Host-Onlyネットワーク」で新規ネットワークを作成します（例: `vboxnet1`）。
2. 作成したネットワークの「アダプター」タブで、IPv4アドレスを`192.168.50.1`、ネットマスクを`255.255.255.0`に設定します。これが[要件定義書](00-requirements.md)3章の`option routers`（`192.168.50.1`）に対応する「VirtualBoxならHost-Onlyネットワークのホスト側」です。
3. **「DHCPサーバー」タブで「サーバーを有効化」のチェックを必ず外します。** VirtualBoxのHost-Onlyネットワークは既定で内蔵DHCPサーバーが有効になっていることがあり、これを外さないまま`dhcp-01`を稼働させると、同一セグメントに2台のDHCPサーバー（`dhcp-01`とVirtualBox内蔵DHCPサーバー）が存在するrogue DHCP状態を自分自身で作り出してしまいます。これはNFR-08・DST-06・DNW-09が確認しようとしている状態そのものであり、確認する側が汚染源にならないよう、この設定は3節の構築より前に必ず終えておきます。
4. 各VMの設定で、NIC2を「Host-Onlyアダプター」・作成したネットワーク名に割り当てます。

### 2.3 Internalネットワークを使う場合

1. `dhcp-01`・クライアント検証VMの両方で、NIC2の種別を「内部ネットワーク」にし、同じネットワーク名（例: `intnet-dhcp`）を入力します。Host-Onlyネットワークのような別画面での事前作成は不要です。
2. Internalネットワークには、VirtualBoxの内蔵DHCPサーバーもホストOS側アダプターも存在しません。したがって2.2節の3.のような内蔵DHCPサーバー無効化の手順自体が不要で、rogue DHCPの混入経路がHost-Onlyより単純です。
3. 一方でホストOSからゲストへ直接到達できないため、`ping 192.168.50.5`のような確認をホストOSの端末から行うことはできません。確認は常にVM間、またはVM上のSSHセッションから行います。
4. `192.168.50.1`（ゲートウェイ）に相当する実体はネットワーク上に存在しません。dhcpd.confが配布するオプション値としては存在しますが、実際にその宛先へパケットを転送する機器はない点に注意します（7節参照）。

### 2.4 dhcp-01の払い出し対象セグメント用NICを静的IPにする

`dhcp-01`自身は払い出し対象セグメントのDHCPクライアントにはなりません。[パラメータシート](03-parameter-sheet.md)のとおり、NIC2には静的に`192.168.50.5/24`を設定します（netplanの例）。

```yaml
# /etc/netplan/90-dhcp-segment.yaml（dhcp-01、NIC2側）
network:
  version: 2
  ethernets:
    enp0s8:               # 実機のinterface名はip -br linkで確認する
      addresses: [192.168.50.5/24]
```

クライアント検証VM側のNIC2はDHCPで取得する前提のため、静的IPを設定せず、`ip -br addr`でNIC2にIPが付いていない（またはリンクローカルのみの）状態にしておきます。

## 3. 構築

VM作成とネットワーク接続ができたら、[構築手順書](05-build-procedure.md)をそのまま実行します。本書はここまでの立ち上げ環境の準備を担当し、05は`dhcp-01`へのAnsible適用そのものを担当するという役割分担です。

```bash
cd ansible
cp inventory/staging.dhcp.local.yml.example inventory/staging.dhcp.local.yml
# dhcp-01側で ip -br link を実行し、NIC2の実際のinterface名を確認してから
# staging.dhcp.local.yml の dhcp_server_interface へ反映する
$EDITOR inventory/staging.dhcp.local.yml

ansible dhcp -i inventory/staging.dhcp.local.yml -b -a 'apt-cache policy isc-dhcp-server'
# 3.2 rogue DHCP確認（クライアント検証VM側から、dhcp-01へまだ何も入れていない状態で）
# 詳細は05-build-procedure.md 3.2節を参照

ansible-playbook -i inventory/staging.dhcp.local.yml playbooks/dhcp.yml --check --diff
ansible-playbook -i inventory/staging.dhcp.local.yml playbooks/dhcp.yml
# 2回目。changed=0になることを確認する（DIT-01）
ansible-playbook -i inventory/staging.dhcp.local.yml playbooks/dhcp.yml
```

コマンドの詳細、確認点、rogue DHCP確認の正確な手順は[構築手順書](05-build-procedure.md)を正本とし、本書では重複させません。

## 4. 受け入れ試験

base Linux版のような`acceptance-check.sh`に相当する、DHCP版の自動判定スクリプトは**本パックには存在しません**。[要件定義書](00-requirements.md)・[基本設計書](01-basic-design.md)に記載のとおり、`dhcp_server` roleは実装済みで静的チェックはPASSしていますが、実ホストでの受け入れ試験は[試験仕様書](06-test-specification.md)のDUT/DIT/DST各IDのコマンドを手で実行し、実出力を日付付きevidenceへ書き写す運用です。手でPASSを書く前に、必ず実際のコマンド出力と期待結果を突き合わせてください。

### 4.1 DORA実演（DIT-02、DNW-06）

[構築手順書](05-build-procedure.md)5節と同じ手順です。クライアント検証VM側で2つの端末（SSHセッション）を開き、一方でpacket captureを先に開始し、もう一方で`dhclient`を実行します。

```bash
# 端末A（先に開始）
sudo timeout 30 tcpdump -nn -i <クライアント側interface> -c 20 'udp port 67 or port 68'

# 端末B（Aが動いている間に実行）
sudo dhclient -v <クライアント側interface>
```

`DHCPDISCOVER` → `DHCPOFFER` → `DHCPREQUEST` → `DHCPACK`の順にログが出て、取得IPが`192.168.50.100`〜`.200`の範囲内であることを確認します。

### 4.2 固定予約・プール枯渇（DIT-03、DIT-04）

固定予約は、`dhcp_server_reservations`へ登録したMACアドレスを持つクライアントで同じ`dhclient -v`を実行し、常に同一の予約IPが払い出されることを確認します。

プール枯渇（DIT-04）は、動的プール101個をすべて使い切った状態を作る必要があります。クライアント検証VMを101台用意するのは非現実的なため、1台のクライアント検証VM上でNICのMACアドレスを一時的に書き換えながら`dhclient`を繰り返す方法で代替します。

```bash
for i in $(seq 1 101); do
  sudo ip link set <クライアント側interface> down
  sudo ip link set <クライアント側interface> address 02:00:00:00:$(printf '%02x' $((i/256))):$(printf '%02x' $((i%256)))
  sudo ip link set <クライアント側interface> up
  sudo dhclient -v <クライアント側interface> || true
done
```

101個目まで払い出した状態で、さらに別のMACアドレスで`dhclient`を実行し、`DHCPNAK`または無応答（タイムアウト）になることを確認します。確認後は`dhclient -r`で明示的に解放し、MACアドレスも元に戻してから後始末します。この手順はNICのMACアドレスを繰り返し書き換える、通常運用では行わない操作のため、この受け入れ試験専用の作業として明記し、[トラブルシュート一次記録テンプレート](../evidence/templates/troubleshooting-worklog.md)へ実施記録を残すことを推奨します。

### 4.3 その他のDIT/DST/DNW

サービス停止・復旧（DIT-09）、リース永続化（DIT-06）、バックアップ・復元（DIT-11）の手順は[構築手順書](05-build-procedure.md)6〜7節、UFW・ファイル権限・AppArmor・SSH hardening（DST-01〜05）の確認コマンドは[試験仕様書](06-test-specification.md)、ネットワーク実機検証（DNW-01〜09）の手順は[ネットワーク実機検証手順](09-network-validation-procedure.md)を正本とします。

## 5. 中央監視統合を試す場合（DIT-10）

DIT-10（`up{host="dhcp-01"}=1`の確認）は、中央Prometheus（`monitor-01`）が`dhcp-01`のnode_exporter（9100/tcp）へ到達できることが前提です。VirtualBox Host-Only/Internalネットワークは`192.168.50.0/24`セグメント内で完結しており、既存の[Linux版パック](../build-package/README.md)の`monitor-01`とは通常別ネットワークにあります。この試験を通すには、次のいずれかが必要です。

- `monitor-01`を同じVirtualBoxホスト上に立て、`dhcp-01`のNIC1（管理用NAT系）と到達可能な同一ネットワーク（NAT Networkなど）へ接続する
- 既存の`monitor-01`から`dhcp-01`の管理用IPへ経路がある別のネットワーク構成を用意する

どちらも用意できない場合、DIT-10は本書の2台構成だけでは`NOT RUN`のまま残ります。これは本パックの不備ではなく、「払い出し対象セグメントの検証」と「中央監視統合の検証」が別のネットワーク前提を必要とすることの反映です。

## 6. 証跡の採録

- [ ] `dhclient -v`のログ、`tcpdump`の出力を保存している
- [ ] `FAIL`の項目について、原因を理解している（理解できないまま採録しない）
- [ ] rogue DHCP確認（DST-06、DNW-09）の実施タイミングが構築前・構築後で正しく分かれている
- [ ] host名/IP/秘密値が出ていない
- [ ] [検証証跡台帳](../evidence/README.md)の該当行を`NOT RUN`から更新した
- [ ] [試験仕様書](06-test-specification.md)の**原本は`NOT RUN`のまま**（上書きしない）。結果は`docs/evidence/YYYY-MM-DD-dhcp-build-validation.md`のような日付付きevidenceへコピーする
- [ ] [作業結果・引き渡し報告書](11-work-result-report.md)を日付付きevidenceへ複製し、結果票の件数、差異、残存リスク、受領判定を記入した
- [ ] プール枯渇試験（4.2節）で書き換えたMACアドレスを元に戻し、テストリースを解放した

## 7. この構成で証明できること／できないこと

**`dhcp-01`とクライアント検証VMの2台をVirtualBox Host-Only/Internalネットワークに置く構成でも、証明できることには限界があります。** 「2台用意したのだから、あとは全部確認できたことにする」という混同を避けるため、範囲を分けて明記します。

### できること

| 項目 | 対応する試験ID |
| --- | --- |
| DORAの4-way handshakeの実測（DISCOVER/OFFER/REQUEST/ACK） | DIT-02、DNW-06 |
| 固定予約（reservation）が常に同一IPを払い出すこと | DIT-03 |
| 動的プール枯渇時にDHCPNAKまたは無応答になること（MACアドレス書き換えによる代替） | DIT-04 |
| リース更新・解放、サービス再起動後のリース永続化 | DIT-05〜07 |
| gateway・DNS・ドメイン名のオプション値がクライアントへ正しく渡ること | DIT-08、DNW-08 |
| isc-dhcp-server停止の検知・復旧、RTOの記録 | DIT-09 |
| `dhcpd.conf`・リースDBのバックアップ・復元 | DIT-11 |
| UFW・ファイル権限・AppArmor・SSH hardening・監査ログの静的な確認（`dhcp-01`1台で完結） | DST-01〜05 |
| この閉じたセグメント内に、`dhcp-01`以外のDHCPサーバーが応答しないこと | DST-06、DNW-09 |
| interface/IP/route/待受portの実機確認 | DNW-01、02、05 |

### できないこと

| 項目 | 理由 |
| --- | --- |
| ゲートウェイ`192.168.50.1`経由での実際のインターネット到達性 | Host-Onlyネットワークのホスト側アダプター、Internalネットワークのどちらも、その先のインターネットへ実際にパケットを転送する経路を構成していない。DIT-08はクライアントが値を受け取ったことまでしか確認しない |
| インターネット越しの攻撃に対するUFWの実効性 | Host-Only/InternalネットワークはVirtualBoxホストの外から到達できない。UFWのルールが設計どおりに設定されていることは確認できるが、実際の外部ホストからの攻撃に対して機能するかどうかは別の確認であり、本構成では確認できない |
| 中央Prometheus（`monitor-01`）との監視統合 | 5節のとおり、別途到達可能なネットワーク構成を用意しない限り`NOT RUN`のまま |
| 実組織のLAN・実スイッチ上でのrogue DHCP非存在 | DST-06/DNW-09で確認できるのは、このラボ環境という閉じたセグメント内に他のDHCPサーバーがいないことだけ。実際に引き渡す本番セグメントでは、そのセグメント上で同じ確認を別途実施する必要がある |
| DHCPリレー（`dhcrelay`）を介した複数セグメントへの配信 | [要件定義書](00-requirements.md)の対象外。単一セグメント内へ直接配置する構成のみを検証する |
| 実際の同時多数クライアントからの負荷、実運用相当のブロードキャストトラフィック量 | クライアント検証VMは1台（MACアドレスの書き換えで複数クライアントを模擬する場合も、同一VM・同一timingからの発行） |
| DHCPv6、DHCP failoverによる冗長化、Kea DHCPへの移行後の挙動 | いずれも[要件定義書](00-requirements.md)6章の対象外。「発展的な設計・将来構想」でのみ言及する |
| 24時間・72時間規模の連続稼働 | 本パックのNFR・FRには長時間soakの要件が定義されていない。必要になった場合は個別に計画を追加する |

**2台用意しても埋まらないものを、埋まったことにしないでください。** 5節・7節の「できないこと」に該当する項目は、それぞれの前提（監視統合用ネットワーク、実本番セグメント、実インターネット経路など）が整うまで`NOT RUN`のままにします。

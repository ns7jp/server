"""RHEL 系対応と、3 層 / ルーティング / ストレージ各ラボの不変条件。

このファイルが守っているのは主に次の 3 つ。

1. OS ファミリーを増やしたときに「片方だけ直して満足する」ことを防ぐ
2. ディスクを壊しうる storage role の安全装置を弱めさせない
3. 各ラボの「層の分離」「証跡を自動生成する」という設計を崩させない
"""

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def read(*parts: str) -> str:
    return ROOT.joinpath(*parts).read_text(encoding="utf-8")


def compose_service_section(compose_text: str, service: str) -> str:
    """Return one service block from a compose file.

    先頭の改行まで含めて照合する。``  db:`` だけで分割すると
    ``depends_on:`` の下にある ``      db:`` にも一致してしまう。
    """
    remainder = compose_text.split(f"\n  {service}:\n", 1)[1]
    return re.split(r"\n(?=  [A-Za-z0-9_-]+:)", remainder, maxsplit=1)[0]


# ---------------------------------------------------------------------------
# RHEL 系対応
# ---------------------------------------------------------------------------


def test_os_aware_roles_refuse_unknown_families_before_touching_the_host():
    """未対応 OS では、パッケージを 1 つも入れる前に落ちること。"""
    for role in ("common", "docker"):
        tasks = read("ansible", "roles", role, "tasks", "main.yml")
        refusal = tasks.index("Refuse an unsupported OS family")
        assert "ansible_os_family in ['Debian', 'RedHat']" in tasks
        # include も含め、あらゆる導入・変更タスクより前で落ちる。
        for mutating in ("include_tasks", "ansible.builtin.apt:", "ansible.builtin.dnf:"):
            if mutating in tasks:
                assert refusal < tasks.index(mutating), (role, mutating)


def test_common_role_ships_variables_for_every_supported_family():
    vars_dir = ROOT / "ansible" / "roles" / "common" / "vars"
    assert {path.name for path in vars_dir.glob("*.yml")} == {
        "Debian.yml",
        "RedHat.yml",
    }


def test_service_unit_names_differ_between_families():
    """ssh / sshd、chrony / chronyd を取り違えると handler が動かない。"""
    debian = read("ansible", "roles", "common", "vars", "Debian.yml")
    redhat = read("ansible", "roles", "common", "vars", "RedHat.yml")

    assert "common_ssh_service_name: ssh\n" in debian
    assert "common_ssh_service_name: sshd\n" in redhat
    assert "common_chrony_service_name: chrony\n" in debian
    assert "common_chrony_service_name: chronyd\n" in redhat

    # handler が変数を使っていなければ、片方の OS で必ず失敗する。
    handlers = read("ansible", "roles", "common", "handlers", "main.yml")
    assert "{{ common_ssh_service_name }}" in handlers
    assert "name: ssh\n" not in handlers


def test_both_families_provide_the_same_first_triage_tooling():
    """一次切り分け用のコマンドが、どちらのファミリーでも入ること。

    片方の一覧にだけツールを足すと、そのファミリーでだけ「構築直後に
    dig が無い」ことになる。パッケージ名は違うので、能力単位で対応を見る。
    """
    debian = read("ansible", "roles", "common", "vars", "Debian.yml")
    redhat = read("ansible", "roles", "common", "vars", "RedHat.yml")

    equivalents = (
        ("dnsutils", "bind-utils"),      # dig / nslookup
        ("iproute2", "iproute"),         # ip
        ("iputils-ping", "iputils"),     # ping
        ("unattended-upgrades", "dnf-automatic"),  # 自動セキュリティ更新
        ("ufw", "firewalld"),            # host firewall
    )
    for debian_package, redhat_package in equivalents:
        assert f"- {debian_package}\n" in debian, debian_package
        assert f"- {redhat_package}\n" in redhat, redhat_package

    # 名前が同じもの。どちらか片方から抜け落ちていないこと。
    for shared in ("chrony", "tcpdump", "lvm2", "util-linux", "openssh-server"):
        assert f"- {shared}\n" in debian, shared
        assert f"- {shared}\n" in redhat, shared


def test_firewalld_rate_limit_is_installed_before_the_open_ssh_rule_is_removed():
    """順序が逆だと、SSH を閉じてから代わりの経路を作ることになる。"""
    firewalld = read("ansible", "roles", "common", "tasks", "firewall-firewalld.yml")

    add_limit = firewalld.index("Rate-limit SSH with an explicit firewalld rich rule")
    remove_plain = firewalld.index("Remove the unrestricted default ssh service")
    assert add_limit < remove_plain

    # plain な service accept を残したままでは rich rule の limit が効かない。
    # 外す動作自体は、切り戻せるよう変数で無効化できること。
    assert "common_firewalld_manage_ssh_service | bool" in firewalld
    assert 'limit value="{{ common_firewalld_ssh_rate_limit }}"' in firewalld


def test_redhat_ssh_hardening_checks_drop_in_overrides():
    """RHEL 9 は sshd_config.d/*.conf が本体より優先される。

    本体だけ書き換えて満足すると、drop-in 側で password 認証が
    生き残っていることに気付けない。
    """
    ssh_tasks = read("ansible", "roles", "common", "tasks", "ssh.yml")
    assert "/etc/ssh/sshd_config.d" in ssh_tasks
    assert "Refuse a drop-in that re-enables root login or password authentication" in ssh_tasks


def test_selinux_is_not_silently_weakened():
    selinux = read("ansible", "roles", "common", "tasks", "selinux.yml")
    defaults = read("ansible", "roles", "common", "defaults", "main.yml")

    assert "common_selinux_state: enforcing" in defaults
    assert "state: \"{{ common_selinux_state }}\"" in selinux
    # permissive / disabled にするのは明示的な指定があるときだけ。
    assert "common_selinux_state in ['enforcing', 'permissive', 'disabled']" in selinux


def test_docker_repository_is_family_specific_and_keeps_gpg_verification():
    debian_repo = read("ansible", "roles", "docker", "tasks", "repo-Debian.yml")
    redhat_repo = read("ansible", "roles", "docker", "tasks", "repo-RedHat.yml")

    assert "signed-by=/etc/apt/keyrings/docker.asc" in debian_repo
    assert "download.docker.com/linux/ubuntu" in debian_repo

    assert "ansible.builtin.rpm_key" in redhat_repo
    assert "download.docker.com/linux/centos" in redhat_repo
    assert "gpgcheck: true" in redhat_repo
    # podman / runc が残っていると containerd.io と衝突する。
    assert "Remove conflicting container runtimes" in redhat_repo


def test_el9_molecule_scenarios_exist_and_run_in_ci():
    for role in ("common", "docker"):
        scenario = ROOT / "ansible" / "roles" / role / "molecule" / "el9"
        assert (scenario / "molecule.yml").exists(), role
        assert (scenario / "converge.yml").exists(), role
        assert (scenario / "verify.yml").exists(), role
        verify = (scenario / "verify.yml").read_text(encoding="utf-8")
        # RHEL 以外のイメージで走らせて「通った」と誤認しないこと。
        assert "ansible_os_family == 'RedHat'" in verify

    integration = read(".github", "workflows", "ansible-integration.yml")
    assert "scenario: el9" in integration
    assert "molecule test -s ${{ matrix.scenario }}" in integration


# ---------------------------------------------------------------------------
# storage role の安全装置
# ---------------------------------------------------------------------------


def test_storage_role_probes_signatures_instead_of_trusting_the_lsblk_cache():
    """lsblk の FSTYPE は udev の cache 由来で、空でないディスクでも
    null を返すことがある。これを署名判定に使うと、中身のあるディスクを
    空だと誤認して潰す。wipefs による実読みを正本にすること。
    """
    tasks = read("ansible", "roles", "storage", "tasks", "main.yml")

    assert "Probe target devices for on-disk signatures" in tasks
    assert "- wipefs" in tasks
    # 判定は wipefs の結果を見る。lsblk の fstype を条件に使わない。
    assert "storage_device_found_signatures" in tasks
    assert "storage_device_entry[0].fstype" not in tasks
    # 検査できなかった場合も通さない。
    assert "storage_device_probe.rc == 0" in tasks


def test_storage_role_refuses_to_touch_anything_by_default():
    defaults = read("ansible", "roles", "storage", "defaults", "main.yml")
    tasks = read("ansible", "roles", "storage", "tasks", "main.yml")

    assert "storage_volumes: []" in defaults
    assert "storage_allow_existing_signature: false" in defaults
    assert "storage_allow_loop_devices: false" in defaults
    # 対象が空なら何もせず終わる。
    assert "ansible.builtin.meta: end_role" in tasks
    assert "storage_volumes | length == 0" in tasks


def test_storage_role_refuses_critical_mount_points():
    tasks = read("ansible", "roles", "storage", "tasks", "main.yml")
    for critical in ("'/'", "'/boot'", "'/etc'", "'/usr'", "'/dev'"):
        assert critical in tasks, critical


def test_storage_role_never_shrinks_a_filesystem():
    apply_tasks = read("ansible", "roles", "storage", "tasks", "apply.yml")
    assert "shrink: false" in apply_tasks
    # 既存ファイルシステムを黙って作り直さない。
    assert "force: false" in apply_tasks
    # device path ではなく UUID で fstab に書く（ディスク順が変わっても戻る）。
    assert "src: \"UUID={{ storage_lv_uuid.stdout }}\"" in apply_tasks


def test_storage_guard_test_covers_each_refusal_path():
    """安全装置そのものを検証する negative test が退化していないこと。"""
    guard = read("scripts", "labs", "storage-guard-test.sh")
    for case in (
        "存在しないデバイス",
        "mount point が /",
        "vg 名に不正な文字",
        "未対応のファイルシステム",
        "既存の ext4 署名",
        "loop device だが許可していない",
    ):
        assert case in guard, case
    # 1 件でも通り抜けたら失敗すること。
    assert "[[ $FAIL_COUNT -eq 0 ]]" in guard


# ---------------------------------------------------------------------------
# 3 層ラボ
# ---------------------------------------------------------------------------


def test_three_tier_lab_keeps_the_database_off_the_web_tier():
    """web が db-tier に参加していたら 3 層に分けた意味がない。"""
    compose = read("labs", "three-tier", "compose.yaml")

    web = compose_service_section(compose, "web")
    assert "dmz:" in web
    assert "app-tier:" in web
    assert "db-tier:" not in web

    database = compose_service_section(compose, "db")
    assert "db-tier:" in database
    assert "dmz:" not in database
    assert "app-tier:" not in database

    client = compose_service_section(compose, "client")
    assert "app-tier:" not in client
    assert "db-tier:" not in client

    # 内部セグメントが外へ出られないこと。
    assert compose.count("internal: true") == 2


def test_three_tier_separates_liveness_from_readiness():
    """healthz と readyz を 1 つにまとめると AP 障害と DB 障害を区別できない。"""
    app = read("labs", "three-tier", "ap", "app.py")

    healthz = app.split('@app.get("/healthz")', 1)[1].split("@app.get", 1)[0]
    readyz = app.split('@app.get("/readyz")', 1)[1].split("@app.get", 1)[0]

    # healthz は DB へ触らない。
    assert "_connect()" not in healthz
    # readyz は DB へ触り、落ちていれば 503 を返す。
    assert "_connect()" in readyz
    assert "503" in readyz

    # DB 停止時にワーカーが張り付かないよう接続タイムアウトを持つこと。
    assert "connect_timeout=CONNECT_TIMEOUT_SECONDS" in app


def test_three_tier_drill_proves_tier_isolation_at_runtime():
    """「設定上そうなっている」で済ませず、毎回到達不能を確認すること。"""
    drill = read("labs", "three-tier", "run-drill.sh")
    assert "web から db への直接到達を遮断" in drill
    assert "nc -z -w 3 db 5432" in drill


def test_restore_drill_compares_content_not_only_row_counts():
    """件数一致だけでは「行数は同じだが中身が違う」を見逃す。"""
    drill = read("labs", "three-tier", "run-restore-drill.sh")

    assert "pg_dump" in drill
    assert "pg_restore" in drill
    assert "md5(string_agg(" in drill
    assert "CHECKSUM_RESTORED" in drill
    # バックアップ後に入れた行が戻らないこと = RPO の実体を確認する。
    assert "SKU-9001" in drill
    assert "RPO" in drill
    assert "RTO" in drill


# ---------------------------------------------------------------------------
# ルーティングラボ
# ---------------------------------------------------------------------------


def test_routing_lab_hosts_do_not_share_a_segment():
    """同一セグメントに同居していると、経路を書く演習にならない。"""
    compose = read("labs", "routing", "compose.yaml")

    memberships = {}
    for host in ("host-a", "host-b", "host-c"):
        section = compose_service_section(compose, host)
        memberships[host] = {
            name for name in ("segment-a", "segment-b", "segment-c") if f"{name}:" in section
        }
        assert len(memberships[host]) == 1, host

    assert memberships["host-a"] != memberships["host-b"]
    assert memberships["host-b"] != memberships["host-c"]
    assert memberships["host-a"] != memberships["host-c"]

    # router だけが 3 セグメントすべてに足を出す。
    router = compose_service_section(compose, "router")
    for segment in ("segment-a", "segment-b", "segment-c"):
        assert f"{segment}:" in router
    assert "net.ipv4.ip_forward" in router
    assert "NET_ADMIN" in router


def test_routing_drill_covers_layer2_and_layer3_causes():
    drill = read("labs", "routing", "run-drill.sh")

    # L3: 経路なし / 片道のみ / 転送無効
    assert "ip route add 172.30.20.0/24 via 172.30.10.1" in drill
    assert "戻りの経路だけ消す" in drill
    assert "net.ipv4.ip_forward=0" in drill
    # L2: VLAN サブインターフェースと ID 不一致
    assert "type vlan id 10" in drill
    assert "type vlan id 20" in drill
    # default route に頼らない構成であること。
    assert "ip route del default" in drill


# ---------------------------------------------------------------------------
# 演習スクリプト共通
# ---------------------------------------------------------------------------


DRILL_SCRIPTS = (
    ("labs", "three-tier", "run-drill.sh"),
    ("labs", "three-tier", "run-restore-drill.sh"),
    ("labs", "routing", "run-drill.sh"),
    ("scripts", "labs", "lvm-drill.sh"),
)


def test_drills_write_their_own_evidence_into_the_drill_log_directory():
    for parts in DRILL_SCRIPTS:
        script = read(*parts)
        assert "docs/drills/logs" in script, parts
        assert "EVIDENCE_FILE" in script, parts
        # 証跡に実施日時と commit SHA が入ること。後から辿れない証跡は使えない。
        assert "rev-parse HEAD" in script, parts
        assert "実施日時" in script, parts
        # 何を確認していないかを必ず書く。
        assert "確認していないこと" in script, parts


def test_drills_can_actually_report_failure():
    """常に PASS を書き出すだけの script は証跡にならない。"""
    for parts in DRILL_SCRIPTS:
        script = read(*parts)
        assert "FAIL" in script, parts
        assert "FAIL_COUNT" in script, parts
        # 判定に失敗があれば終了コードで落ちること。
        assert "[[ $FAIL_COUNT -eq 0 ]]" in script, parts


def test_drills_are_executable():
    import os

    for parts in DRILL_SCRIPTS:
        path = ROOT.joinpath(*parts)
        assert os.access(path, os.X_OK), parts


# ---------------------------------------------------------------------------
# 手順書と実装のずれ
# ---------------------------------------------------------------------------


def test_parameter_sheet_matches_the_time_synchronization_actually_installed():
    """パラメータシートが実装から取り残されないようにする。

    以前このシートは時刻同期を「systemd-timesyncd / OS 標準」と書いていたが、
    common ロールは chrony を導入して起動していた。シート自身が
    「正本は Ansible 変数」と宣言している以上、このずれは残せない。
    """
    sheet = read("docs", "build-package", "03-parameter-sheet.md")
    debian_vars = read("ansible", "roles", "common", "vars", "Debian.yml")
    redhat_vars = read("ansible", "roles", "common", "vars", "RedHat.yml")
    time_tasks = read("ansible", "roles", "common", "tasks", "time.yml")

    # 実装側: chrony を入れて、ファミリーごとの unit 名で起動している。
    assert "- chrony\n" in debian_vars
    assert "- chrony\n" in redhat_vars
    assert "{{ common_chrony_service_name }}" in time_tasks

    # 手順書側: chrony と書いてあり、古い記述が残っていない。
    time_row = [line for line in sheet.splitlines() if line.startswith("| 時刻同期")]
    assert len(time_row) == 1, time_row
    assert "chrony" in time_row[0]
    assert "timesyncd" not in sheet


def test_parameter_sheet_documents_both_firewall_backends():
    sheet = read("docs", "build-package", "03-parameter-sheet.md")
    assert "UFW" in sheet
    assert "firewalld" in sheet
    assert "SELinux" in sheet
    # ディスク設計の欄があること。構築案件で必ず聞かれる。
    assert "## ディスク・ファイルシステム" in sheet
    assert "## ユーザー・グループ・権限" in sheet


def test_three_tier_web_resolves_the_ap_upstream_per_request():
    """upstream を静的に書くと、停止 → 再起動で IP が変わったとき
    nginx が古い IP を掴んだままになり、AP が復帰しても 502 が続く。
    「復旧したのに直らない」という誤った観測になるので、
    labs/network-troubleshooting と同じく動的解決にする。
    """
    conf = read("labs", "three-tier", "web", "nginx.conf")

    assert "resolver 127.0.0.11" in conf
    # 変数経由の proxy_pass（リクエストごとに解決される）
    assert "set $ap_upstream ap:8000;" in conf
    assert "proxy_pass http://$ap_upstream;" in conf
    # 起動時に一度だけ解決する upstream ブロック宣言を使っていない。
    # コメント中の「upstream」に反応しないよう、ディレクティブとして
    # 行頭に現れる形だけを見る。
    directives = [
        line.strip()
        for line in conf.splitlines()
        if line.strip() and not line.strip().startswith("#")
    ]
    assert not any(line.startswith("upstream ") for line in directives), directives


# ---------------------------------------------------------------------------
# 引き渡し対象ホストの受け入れ試験
# ---------------------------------------------------------------------------


def test_acceptance_check_covers_the_test_specification_ids():
    """結果票を名乗る以上、試験仕様書の runtime ID を実際に見ていること。"""
    script = read("scripts", "ops", "acceptance-check.sh")

    # 06 の runtime 系 ID（静的検査で済む UT 系と、別環境が要る IT-01/02/10/11 は除く）
    for test_id in ("IT-03", "IT-04", "IT-05", "IT-06", "IT-07", "ST-01", "ST-02", "ST-04"):
        assert f"record {test_id} " in script, test_id


def test_acceptance_check_never_prints_secret_values():
    """秘密値は読むが出力しない。証跡はそのまま公開される前提。"""
    script = read("scripts", "ops", "acceptance-check.sh")

    # 秘密値を保持する変数が echo / printf の引数に現れないこと。
    for secret_var in ("dashboard_password", "metrics_token"):
        for line in script.splitlines():
            stripped = line.strip()
            if stripped.startswith("#"):
                continue
            if f"${{{secret_var}}}" in stripped or f"${secret_var}" in stripped:
                assert not stripped.startswith(("echo", "printf")), stripped
                # record() の実測欄へ入れていないこと
                assert not stripped.startswith("record "), stripped

    # host 名 / IP は既定でマスクする。
    assert "MASK=1" in script
    assert "<masked-host>" in script
    assert "<masked-ip>" in script


def test_acceptance_check_distinguishes_skip_from_pass():
    """SKIP を PASS に混ぜない。「確認していない」は「問題なし」ではない。"""
    script = read("scripts", "ops", "acceptance-check.sh")

    assert "SKIP_COUNT" in script
    assert "SKIP) SKIP_COUNT=$((SKIP_COUNT + 1)) ;;" in script
    # 終了コードは FAIL だけで決まる（SKIP は成否に含めない）
    assert "[[ $FAIL_COUNT -eq 0 ]]" in script
    # heredoc 内なので source ではバッククォートがエスケープされている。
    # 記法に依存しないよう、文言そのものを見る。
    assert "は「確認していない」であって「問題なし」ではない" in script


def test_reboot_mode_detects_a_host_that_was_never_rebooted():
    """boot ID が変わっていなければ再起動していない。

    「再起動したつもりで実はしていない」証跡を作らせない。
    """
    script = read("scripts", "ops", "acceptance-check.sh")

    assert "random/boot_id" in script
    assert 'record RB-01 "実際に再起動した"' in script
    assert '"boot ID が同じ（未再起動）" FAIL' in script


def test_acceptance_check_handles_command_output_without_double_printing():
    """`grep -c` と `curl -w` は失敗時にも値を出力したうえで非ゼロ終了する。

    `|| echo 0` を付けると値が二重になり、算術比較が構文エラーになる。
    実際にこの不具合を踏んだので、ヘルパー経由に統一したことを固定する。
    """
    script = read("scripts", "ops", "acceptance-check.sh")

    assert "count_lines()" in script
    # 二重出力を生む書き方が残っていないこと
    assert "grep -c . || echo 0" not in script
    assert "|| echo \"000\"" not in script


def test_ufw_restricts_ssh_source_when_a_management_cidr_is_given():
    """04-network-ip-plan.md が「受入条件なら実装する」としていた項目。

    絞った rule を入れてから無制限 rule を外す順序であること。
    逆順だと、代わりの経路を作る前に SSH を閉じることになる。
    """
    ufw = read("ansible", "roles", "common", "tasks", "firewall-ufw.yml")
    defaults = read("ansible", "roles", "common", "defaults", "main.yml")

    assert "common_ufw_ssh_source_cidr" in defaults
    add_restricted = ufw.index("Rate-limit SSH from the management source only")
    remove_open = ufw.index("Remove the unrestricted SSH rule once a management source is set")
    assert add_restricted < remove_open

    # 管理元 CIDR 未指定のときだけ全送信元 rate limit を掛ける
    any_source = ufw.split("Rate-limit SSH from any source", 1)[1].split("- name:", 1)[0]
    assert "common_ufw_ssh_source_cidr | length == 0" in any_source


def test_bringup_runbook_states_what_one_host_cannot_cover():
    """1 台で埋まらないものを、埋まったことにしない。"""
    runbook = read("docs", "build-package", "10-host-bringup-and-acceptance.md")

    assert "## 7. この手順で埋まらないもの" in runbook
    for uncovered in ("Slack", "組織 DNS", "D-2", "AWS", "物理層"):
        assert uncovered in runbook, uncovered
    # SSH だけに依存させない警告
    assert "SSH だけに依存しない" in runbook


# ---------------------------------------------------------------------------
# ラボの診断コマンドが、そのイメージに実在すること
# ---------------------------------------------------------------------------


def test_three_tier_probes_run_from_images_that_have_the_tools():
    """診断コマンドを、それが入っていないイメージの中で実行しない。

    nginx:alpine の busybox には `ip -br` も `nc -z` も無く、
    python:3.12-slim には iproute2 自体が入っていない。
    存在しないコマンドで到達性を確かめると「遮断されているから失敗した」のか
    「コマンドが無いから失敗した」のか区別できず、遮断されていないのに
    PASS する偽陽性になる。

    network namespace を共有する netshoot サイドカーから実行すること。
    """
    compose = read("labs", "three-tier", "compose.yaml")
    drill = read("labs", "three-tier", "run-drill.sh")

    # サイドカーが web / ap と netns を共有していること。
    # 共有していなければ、そこから見た到達性は web / ap の到達性ではない。
    web_probe = compose_service_section(compose, "netprobe-web")
    ap_probe = compose_service_section(compose, "netprobe-ap")
    assert 'network_mode: "service:web"' in web_probe
    assert 'network_mode: "service:ap"' in ap_probe
    assert "netshoot" in web_probe and "netshoot" in ap_probe

    # 道具の無いコンテナの中で ip / nc を実行していないこと。
    for line in drill.splitlines():
        stripped = line.strip()
        if stripped.startswith("#") or "exec -T" not in stripped:
            continue
        for thin_container in (" -T web ", " -T ap "):
            if thin_container in stripped:
                assert " ip " not in f" {stripped} ", stripped
                assert " nc " not in f" {stripped} ", stripped


def test_tier_isolation_check_is_fail_closed():
    """probe を実行できなかったときに PASS にしない。

    「到達できなかった」理由が遮断なのか道具不足なのかを区別せずに
    PASS にすると、層が分離されていないのに PASS する。
    """
    drill = read("labs", "three-tier", "run-drill.sh")

    # コメント見出しにも同じ語が出るので、log 行を起点に 3 節までを切り出す。
    isolation = drill.split('log "2. 層の分離', 1)[1].split('log "3.', 1)[0]
    # 実行できなかった場合を明示的に FAIL にしていること
    assert "not found" in isolation
    assert "検証不能" in isolation
    assert 'record "B2-02"' in isolation
    # 3 分岐（到達した / 検証不能 / 遮断を確認）があること
    assert isolation.count('record "B2-02"') == 3


def test_routing_lab_checks_vlan_kernel_support_before_using_it():
    """8021q が無い環境で、分かりにくいエラーではなく理由を出して止める。"""
    drill = read("labs", "routing", "run-drill.sh")

    assert "check_vlan_support" in drill
    assert "/sys/module/8021q" in drill
    # L3 の演習はそこまでで完走させ、VLAN 分だけを SKIP にする
    assert "SKIP-ENV" in drill
    assert "VLAN_SKIPPED" in drill


def test_environment_skips_are_not_counted_as_pass():
    """環境都合で実行できなかったものを PASS に混ぜない。"""
    drill = read("labs", "routing", "run-drill.sh")

    assert "SKIP_COUNT" in drill
    assert "SKIP-ENV) SKIP_COUNT=$((SKIP_COUNT + 1)) ;;" in drill
    # 証跡にも SKIP 件数が出ること
    assert "${SKIP_COUNT} SKIP" in drill


# ---------------------------------------------------------------------------
# 失敗時にも値を出力するコマンドと `|| echo` の併用
# ---------------------------------------------------------------------------


ALL_DRILL_SCRIPTS = (
    ("labs", "three-tier", "run-drill.sh"),
    ("labs", "three-tier", "run-restore-drill.sh"),
    ("labs", "routing", "run-drill.sh"),
    ("scripts", "labs", "lvm-drill.sh"),
    ("scripts", "labs", "storage-guard-test.sh"),
    ("scripts", "ops", "acceptance-check.sh"),
)


def test_no_script_double_prints_a_failure_value():
    """`curl -w '%{http_code}'` と `grep -c` は失敗時にも値を出力する。

    そこへ `|| echo <既定値>` を付けると出力が二重になり
    ("000000" / "0\\n0")、比較が壊れるか、誤った理由で通る。

    実際に acceptance-check.sh と 3 層ラボの 2 本で踏んだので、
    全 script を横断で検査する。
    """
    offenders = []
    for parts in ALL_DRILL_SCRIPTS:
        script = read(*parts)
        for number, line in enumerate(script.splitlines(), start=1):
            stripped = line.strip()
            if stripped.startswith("#"):
                continue
            if "|| echo" not in stripped:
                continue
            # 失敗時にも stdout へ値を出すコマンド
            if (
                "%{http_code}" in stripped
                or "grep -c" in stripped
                # docker version は daemon 不達のとき stdout へ空行を出す
                or "docker version" in stripped
            ):
                offenders.append(f"{'/'.join(parts)}:{number}: {stripped}")
    assert not offenders, "失敗時にも値を出力するコマンドに || echo を付けている:\n" + "\n".join(offenders)


def test_http_status_helpers_default_only_when_empty():
    """既定値は「出力が空のとき」だけ入れる。"""
    for parts in (
        ("labs", "three-tier", "run-drill.sh"),
        ("labs", "three-tier", "run-restore-drill.sh"),
        ("scripts", "ops", "acceptance-check.sh"),
    ):
        script = read(*parts)
        assert '"${code:-000}"' in script, "/".join(parts)


def test_restore_drill_records_pg_restore_exit_code_instead_of_aborting():
    """pg_restore は警告を無視したとき非ゼロで終了することがある。

    set -e のまま呼ぶと ERR trap で演習全体が中断し、証跡が 1 行も残らない。
    終了コードは判定行として記録し、復元の成否は件数・内容ハッシュで見る。
    """
    drill = read("labs", "three-tier", "run-restore-drill.sh")

    assert "RESTORE_RC=$?" in drill
    assert 'record "B3-02b" "復元コマンドの終了コード"' in drill
    # 復元の本判定は照合側に残っていること
    assert "CHECKSUM_RESTORED" in drill
    assert 'record "B3-04"' in drill or "B3-04" in drill


# ---------------------------------------------------------------------------
# soak モードの観測窓
# ---------------------------------------------------------------------------


def test_soak_sample_count_spans_the_requested_window():
    """サンプル間だけ sleep するので、n 回の観測がまたぐ時間は (n-1) 間隔。

    `total / interval` のままだと観測窓が 1 間隔ぶん短くなり、
    「N 時間連続稼働」と題した証跡が実際には N 時間を観測していない。
    実際に --hours 24（既定間隔 900 秒）で 23 時間 45 分しか測れていなかった。
    """
    script = read("scripts", "ops", "acceptance-check.sh")

    assert "samples=$(( total_seconds / SOAK_INTERVAL + 1 ))" in script
    # 旧実装（1 間隔ぶん不足する）が戻っていないこと
    assert "samples=$(( total_seconds / SOAK_INTERVAL ))" not in script

    # 代表的な指定で観測窓が要求以上になること
    for hours, interval in ((1, 900), (1, 1800), (1, 3600), (24, 900), (72, 3600)):
        total = hours * 3600
        samples = total // interval + 1
        assert (samples - 1) * interval >= total, (hours, interval)


def test_soak_rejects_inputs_that_cannot_cover_the_window():
    """0 時間の soak や、観測窓より長い間隔を受け付けない。

    受け付けると「1 回測っただけで N 時間稼働した」証跡が作れてしまう。
    """
    script = read("scripts", "ops", "acceptance-check.sh")

    assert "--hours must be an integer of at least 1" in script
    assert "(( SOAK_HOURS < 1 ))" in script
    assert "must not exceed --hours" in script
    assert "(( SOAK_INTERVAL > SOAK_HOURS * 3600 ))" in script


def test_soak_records_the_measured_window_not_the_requested_one():
    """実際に観測できた時間を測って判定する。

    途中で中断された場合も、要求を満たしていないことが証跡に残る。
    """
    script = read("scripts", "ops", "acceptance-check.sh")

    assert "soak_started_at=" in script
    assert "soak_ended_at=" in script
    assert "soak_observed=" in script
    assert 'record SK-00 "観測窓が要求時間を満たす"' in script
    # 不足時は FAIL
    assert "秒（不足）\" FAIL" in script
    # 証跡本文にも実測値を残す
    assert "実測した観測窓 ${soak_observed} 秒" in script


# ---------------------------------------------------------------------------
# 判定行の「実測」欄
# ---------------------------------------------------------------------------


def test_lvm_drill_reports_what_it_observed_not_a_fixed_string():
    """実測欄を結果に関わらず固定文字列にしない。

    以前 B1-01 は判定が FAIL でも実測欄へ「適用完了」と書いていたため、
    mount できていないのに「適用完了 / FAIL」という自己矛盾した行が
    証跡に残る状態だった。
    """
    drill = read("scripts", "labs", "lvm-drill.sh")

    b1_01 = drill.split('record "B1-01"', 1)[1].split('record "B1-02"', 1)[0]
    # 成否で異なる観測結果を書き分けていること
    assert "mount 済み" in b1_01
    assert "mount されていない" in b1_01
    # 固定文字列と成否を同時に渡していた旧形が戻っていないこと
    assert '"適用完了" "$(mountpoint' not in drill


def test_lvm_drill_preflights_the_tools_its_verdicts_depend_on():
    """判定に使うコマンドが無いと、成功していても FAIL になる（偽 FAIL）。"""
    drill = read("scripts", "labs", "lvm-drill.sh")

    preflight = drill.split("for tool in", 1)[1].split("done", 1)[0]
    for tool in ("mountpoint", "df", "dmsetup", "losetup", "blkid"):
        assert tool in preflight, tool


DRILLS_WITH_DOCKER_VERSION = (
    ("labs", "three-tier", "run-drill.sh"),
    ("labs", "three-tier", "run-restore-drill.sh"),
    ("labs", "routing", "run-drill.sh"),
)


def test_docker_version_is_folded_into_one_line():
    """証跡の「実施環境」欄は markdown の表のセルなので、必ず 1 行でなければ
    ならない。

    `docker version --format ...` は daemon へ繋がらないとき stdout へ空行を
    出したうえで非ゼロ終了する。`|| echo unknown` だけだと値が 2 行になり、
    表がその行で崩れる。helper で 1 行へ畳んでいることを固定する。
    """
    for parts in DRILLS_WITH_DOCKER_VERSION:
        script = read(*parts)
        name = "/".join(parts)
        assert "docker_server_version() {" in script, f"{name}: helper がない"
        assert r"tr -d '\n'" in script, (
            f"{name}: helper が改行を落としていない"
        )
        assert '${v:-unknown}' in script, f"{name}: 空のときだけ既定値にしていない"
        assert "Docker $(docker_server_version)" in script, (
            f"{name}: 証跡が helper を経由していない"
        )


SCRIPTS_WITH_ERR_TRAP = (
    ("labs", "three-tier", "run-drill.sh"),
    ("labs", "three-tier", "run-restore-drill.sh"),
    ("labs", "routing", "run-drill.sh"),
    ("scripts", "labs", "lvm-drill.sh"),
)


def _tolerated_failure_regions(script):
    """`set +e` ... `set -e` の各区間を (開始行, 終了行) で返す（1 始まり）。"""
    lines = script.splitlines()
    regions, start = [], None
    for number, line in enumerate(lines, start=1):
        if line.strip() == "set +e":
            start = number
        elif line.strip() == "set -e" and start is not None:
            regions.append((start, number))
            start = None
    assert start is None, "set +e を張ったまま閉じていない"
    return lines, regions


def test_exit_code_capture_is_inside_a_tolerated_failure_region():
    """`out="$(cmd)"` の直後に `rc=$?` を置く形は、`set -e` の下では動かない。

    代入文そのものが非ゼロを返すため、`rc=$?` の行へ到達する前に script が
    落ちる。落ちるのは cmd が失敗したときなので、「失敗を承知で実行して
    終了コードを見る」という意図と正反対の挙動になる。

    実際に 3 層ラボの層分離チェックで踏んだ。そこでは nc が失敗する＝遮断
    できている＝PASS の入力のときにだけ演習が中断していた。
    """
    offenders = []
    for parts in ALL_DRILL_SCRIPTS:
        script = read(*parts)
        lines, regions = _tolerated_failure_regions(script)
        for number, line in enumerate(lines, start=1):
            if not re.fullmatch(r"\s*[A-Za-z_][A-Za-z0-9_]*=\$\?\s*", line):
                continue
            if not any(start < number < end for start, end in regions):
                offenders.append(f"{'/'.join(parts)}:{number}: {line.strip()}")
    assert not offenders, (
        "終了コードの取得が set +e 区間の外にある（set -e に巻き込まれる）:\n"
        + "\n".join(offenders)
    )


def test_err_trap_is_disarmed_around_tolerated_failures():
    """bash は `set +e` でも ERR trap を実行する。

    そのため後始末を促す注意書きが「正常に進んでいるのに中断した」ように
    見える形で出てしまう。意図した失敗の間は trap も外し、区間を抜けたら
    必ず張り直す。
    """
    offenders = []
    for parts in SCRIPTS_WITH_ERR_TRAP:
        script = read(*parts)
        name = "/".join(parts)
        lines, regions = _tolerated_failure_regions(script)
        for start, end in regions:
            before = lines[start - 2].strip() if start >= 2 else ""
            after = lines[end].strip() if end < len(lines) else ""
            if before != "trap - ERR":
                offenders.append(f"{name}:{start}: 直前で trap を外していない")
            if after != "trap cleanup_note ERR":
                offenders.append(f"{name}:{end}: 直後で trap を張り直していない")
    assert not offenders, "\n".join(offenders)

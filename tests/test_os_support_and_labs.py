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

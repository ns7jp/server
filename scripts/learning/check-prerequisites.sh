#!/usr/bin/env bash
# 初学者が演習前に「不足している道具」と「次の確認」を判別するための読み取り専用診断。
set -uo pipefail

FAILS=0
WARNS=0
MINIMAL=false

usage() {
  cat <<'EOF'
Usage: ./scripts/learning/check-prerequisites.sh [--minimal]

リポジトリ直下で、Linux、Git、Python 3.11以上/venv、curl、OpenSSL、Docker、Compose、空き容量を診断します。
設定変更、package installation、sudo、container起動は行いません。
--minimal: 初回のapp/nginx向け。既定ポート8080のみを調べます。
引数なし: 監視全体の既定ポートとmemoryも診断し、Ansible未導入はWARN扱いです。
変更済みの.envの値は読み込まないため、独自ポートは別途確認してください。
終了コード: 0=必須条件PASS、1=必須条件FAIL（WARNだけなら0）
EOF
}

if [[ ${1:-} == "--help" || ${1:-} == "-h" ]]; then
  usage
  exit 0
fi
if [[ $# -eq 1 && $1 == "--minimal" ]]; then
  MINIMAL=true
elif [[ $# -gt 0 ]]; then
  echo "unknown argument: $1" >&2
  usage >&2
  exit 2
fi

pass() { printf '[PASS] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; WARNS=$((WARNS + 1)); }
fail() { printf '[FAIL] %s\n' "$*"; FAILS=$((FAILS + 1)); }
next() { printf '       NEXT: %s\n' "$*"; }

version_line() {
  "$@" 2>/dev/null | head -n 1 | tr '\n' ' '
}

if [[ -f compose.yaml && -f app.py && -f requirements-dev.txt ]]; then
  pass "実行場所: serverリポジトリ直下"
else
  fail "実行場所がserverリポジトリ直下ではありません"
  next "pwd と ls を確認し、取得済みのserverディレクトリへcdしてください"
fi

if [[ "$(uname -s 2>/dev/null || true)" == "Linux" ]]; then
  pass "Linux host: $(uname -sr)"
else
  fail "このlabのruntime対象はLinuxです: $(uname -s 2>/dev/null || echo unknown)"
  next "破棄できるUbuntu 24.04 VMまたはWSL2を用意してください"
fi

if command -v git >/dev/null 2>&1; then
  pass "Git: $(version_line git --version)"
else
  fail "GitがPATHにありません"
  next "Ubuntu: sudo apt-get update && sudo apt-get install git"
fi

if command -v python3 >/dev/null 2>&1; then
  python_version="$(python3 -c 'import sys; print(".".join(map(str, sys.version_info[:3])))' 2>/dev/null || true)"
  if python3 -c 'import sys; raise SystemExit(sys.version_info < (3, 11))' 2>/dev/null; then
    pass "Python: ${python_version}"
  else
    fail "この学習手順はPython 3.11以上を対象とします: ${python_version:-unknown}"
    next "python3 --version を確認してください。ガイドの使用版は3.11 / Ubuntu 24.04標準の3.12です"
  fi
  if python3 -c 'import venv, ensurepip' 2>/dev/null; then
    pass "Python venv / ensurepipを利用できます"
  else
    fail "Python仮想環境の作成に必要なモジュールが不足しています"
    next "Ubuntu: sudo apt-get install python3-venv"
  fi
else
  fail "python3がPATHにありません"
  next "Ubuntu: sudo apt-get install python3 python3-venv"
fi

if command -v curl >/dev/null 2>&1; then
  pass "curl: $(version_line curl --version)"
else
  fail "curlがPATHにありません（HTTP応答の確認に必要）"
  next "Ubuntu: sudo apt-get install curl"
fi

if command -v openssl >/dev/null 2>&1; then
  pass "OpenSSL: $(version_line openssl version)"
else
  fail "opensslがPATHにありません（学習用secret生成に必要）"
  next "Ubuntu: sudo apt-get install openssl"
fi

if command -v docker >/dev/null 2>&1; then
  pass "Docker CLI: $(version_line docker --version)"
  if docker info >/dev/null 2>&1; then
    pass "Docker daemonへ接続できます"
  else
    fail "Docker CLIはありますがdaemonへ接続できません"
    next "systemctl status docker と id を確認し、sudoで症状を隠さないでください"
  fi
  if docker compose version >/dev/null 2>&1; then
    pass "Docker Compose: $(version_line docker compose version)"
  else
    fail "Docker Compose pluginを利用できません"
    next "docker compose version を確認し、Compose pluginを導入してください"
  fi
else
  fail "dockerがPATHにありません"
  next "公式手順でDocker EngineとCompose pluginを導入してください"
fi

if [[ "$MINIMAL" == false ]]; then
  if command -v ansible >/dev/null 2>&1; then
    pass "Ansible: $(version_line ansible --version)"
  elif command -v ansible-playbook >/dev/null 2>&1; then
    pass "Ansible playbook: $(version_line ansible-playbook --version)"
  else
    warn "ansible/ansible-playbookがPATHにありません（一本道ラーニングパスのLevel 4で必要になります）"
    next "Ubuntu: pipx install ansible-core（詳細はdocs/deployment-ansible.mdを参照）"
  fi
fi

available_kib="$(df -Pk . 2>/dev/null | awk 'NR==2 {print $4}' || true)"
if [[ "$available_kib" =~ ^[0-9]+$ ]]; then
  if (( available_kib >= 10 * 1024 * 1024 )); then
    pass "作業directoryの空き容量: $((available_kib / 1024 / 1024)) GiB"
  else
    warn "空き容量が10 GiB未満です: $((available_kib / 1024 / 1024)) GiB"
    next "df -h . と docker system df で使用量を確認してください"
  fi
else
  warn "空き容量を取得できません"
fi

memory_kib="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo 2>/dev/null || true)"
if [[ "$MINIMAL" == false && "$memory_kib" =~ ^[0-9]+$ ]]; then
  if (( memory_kib >= 6 * 1024 * 1024 )); then
    pass "memory: $((memory_kib / 1024 / 1024)) GiB"
  else
    warn "memoryが6 GiB未満です: $((memory_kib / 1024 / 1024)) GiB"
    next "全stackが不安定な場合はVM memoryを増やしてください"
  fi
fi

if command -v ss >/dev/null 2>&1; then
  ports=(8080)
  if [[ "$MINIMAL" == false ]]; then
    ports=(3000 8080 9090 9093 3100)
  fi
  for port in "${ports[@]}"; do
    if ss -H -lnt 2>/dev/null | awk '{print $4}' | grep -Eq "(^|:)$port$"; then
      warn "TCP port ${port}は既にlistenされています"
      next "ss -lntp | grep ':${port}' で所有processを確認してください"
    else
      pass "TCP port ${port}は未使用です"
    fi
  done
else
  warn "ssがないためport競合を診断できません"
  next "Ubuntu: sudo apt-get install iproute2"
fi

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if [[ -n "$(git status --porcelain --untracked-files=normal 2>/dev/null)" ]]; then
    warn "Git working treeに変更があります（上書き前に内容を確認）"
    next "git status --short"
  else
    pass "Git working treeはcleanです"
  fi
else
  warn "Git repository外で実行されています"
fi

printf '\nSummary: FAIL=%d WARN=%d\n' "$FAILS" "$WARNS"
if (( FAILS > 0 )); then
  echo "必須条件にFAILがあります。NEXTを確認し、解消前の結果はBLOCKEDと記録してください。"
  exit 1
fi
if [[ "$MINIMAL" == true ]]; then
  echo "最小実習の必須条件はPASSです。WARNを確認し、初心者向け学習ガイドのStep 1へ進んでください。"
  echo "監視全体のmemory・ポート・Ansibleは未判定です。Step 6では引数なしで再診断してください。"
else
  echo "必須条件はPASSです。WARNの影響を確認してから学習を進めてください。"
fi

/* =========================================================================
   ファイル名 : static/js/dashboard.js
   役割       : サーバー監視ダッシュボードのフロント側ロジック
   概要       : Flask の /api/stats と /api/processes を定期的に呼び出し、
                取得したJSONを画面の各カードに反映する。
                Chart.jsで CPU/メモリの時系列グラフも描画する。
   ========================================================================= */

(() => {
    'use strict';

    // ===== 設定定数 =====
    const STATS_INTERVAL = 2000;      // CPU・メモリなど主要情報の更新間隔（ミリ秒）
    const PROCESS_INTERVAL = 5000;    // プロセス一覧の更新間隔（ミリ秒）
    const HISTORY_LENGTH = 30;        // グラフに保持する履歴データ数（30点 × 2秒 = 60秒分）
    const GAUGE_CIRCUMFERENCE = 427;  // CPU円形ゲージの円周（2πr ≈ 2*π*68）

    // ===== 履歴データ用の配列 =====
    // グラフ描画用にCPU・メモリの値を時系列で保持しておく
    const cpuHistory = [];
    const memHistory = [];
    const labelHistory = [];

    // ===== 前回のネットワーク値（速度計算用） =====
    // 「今回のbytes - 前回のbytes」÷ 経過秒数 で送受信速度を算出
    let lastNet = null;
    let lastNetTime = null;


    // ============================================================
    //  ユーティリティ関数
    // ============================================================

    /**
     * バイト数を人間が読みやすい単位（KB / MB / GB など）に変換
     * @param {number} bytes バイト数（負値はカウンタリセット時に発生し得るので 0 として扱う）
     * @returns {string} "1.23 GB" のような文字列
     */
    function formatBytes(bytes) {
        if (!Number.isFinite(bytes) || bytes <= 0) return '0 B';
        const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
        const i = Math.min(units.length - 1, Math.floor(Math.log(bytes) / Math.log(1024)));
        const value = bytes / Math.pow(1024, i);
        return value.toFixed(2) + ' ' + units[i];
    }

    /**
     * 秒数を「日 時 分 秒」形式に変換
     * @param {number} seconds 経過秒数
     * @returns {string} 例：「2d 4h 12m」
     */
    function formatUptime(seconds) {
        const d = Math.floor(seconds / 86400);
        const h = Math.floor((seconds % 86400) / 3600);
        const m = Math.floor((seconds % 3600) / 60);
        const s = seconds % 60;
        if (d > 0) return `${d}d ${h}h ${m}m`;
        if (h > 0) return `${h}h ${m}m ${s}s`;
        if (m > 0) return `${m}m ${s}s`;
        return `${s}s`;
    }

    /**
     * 使用率(%)から、状態クラス（warn / alert / danger）を返す
     * @param {number} percent 0-100の数値
     */
    function getThresholdClass(percent) {
        if (percent >= 90) return 'danger';
        if (percent >= 75) return 'alert';
        if (percent >= 50) return 'warn';
        return '';
    }

    /**
     * CPU使用率の数値に応じて、表のセル用カラークラスを返す
     */
    function getCpuColorClass(percent) {
        if (percent >= 50) return 'cpu-danger';
        if (percent >= 25) return 'cpu-high';
        if (percent >= 10) return 'cpu-mid';
        return 'cpu-low';
    }


    // ============================================================
    //  DOM更新：システム情報
    // ============================================================
    function updateSystemInfo(sys, loadAvg) {
        document.getElementById('sys-os').textContent = `${sys.os} ${sys.os_release}`;
        document.getElementById('sys-hostname').textContent = sys.hostname;
        document.getElementById('sys-machine').textContent = sys.machine;
        document.getElementById('sys-processor').textContent = sys.processor;
        document.getElementById('sys-boot').textContent = sys.boot_time;
        document.getElementById('sys-uptime').textContent = formatUptime(sys.uptime_seconds);
        document.getElementById('sys-processes').textContent =
            sys.process_count != null ? sys.process_count.toLocaleString() : '--';
        const loadEl = document.getElementById('sys-loadavg');
        if (loadAvg && typeof loadAvg['1m'] === 'number') {
            loadEl.textContent = `${loadAvg['1m'].toFixed(2)} / ${loadAvg['5m'].toFixed(2)} / ${loadAvg['15m'].toFixed(2)}`;
        } else {
            loadEl.textContent = 'N/A';
        }
    }


    // ============================================================
    //  DOM更新：CPU
    // ============================================================
    function updateCpu(cpu) {
        const percent = cpu.percent;

        // 円形ゲージの進捗を更新
        // stroke-dasharray="進捗 円周" の形で進捗バーの長さを指定
        const gauge = document.getElementById('cpu-gauge');
        const filledLength = (percent / 100) * GAUGE_CIRCUMFERENCE;
        gauge.setAttribute('stroke-dasharray', `${filledLength} ${GAUGE_CIRCUMFERENCE}`);

        // 高負荷時に色を変える（warn/alert/dangerクラスをトグル）
        gauge.classList.remove('warn', 'alert', 'danger');
        const cls = getThresholdClass(percent);
        if (cls) gauge.classList.add(cls);

        // 中央の数値表示
        document.getElementById('cpu-percent').textContent = percent.toFixed(1);

        // CPU詳細
        document.getElementById('cpu-physical').textContent = cpu.count_physical || '-';
        document.getElementById('cpu-logical').textContent = cpu.count_logical || '-';
        document.getElementById('cpu-freq').textContent = cpu.freq_current
            ? `${cpu.freq_current} MHz`
            : 'N/A';

        // コア別バーを再生成（コア数は変わらないので毎回作り直しても軽い）
        const container = document.getElementById('per-core-bars');
        container.innerHTML = '';
        cpu.per_core.forEach((corePercent, index) => {
            const bar = document.createElement('div');
            bar.className = 'core-bar';
            bar.style.setProperty('--core-percent', `${corePercent}%`);
            bar.innerHTML = `
                <span class="core-label">Core ${index}</span>
                <span class="core-value">${corePercent.toFixed(0)}%</span>
            `;
            container.appendChild(bar);
        });
    }


    // ============================================================
    //  DOM更新：メモリ
    // ============================================================
    function updateMemory(mem, swap) {
        document.getElementById('mem-percent').textContent = mem.percent.toFixed(1);
        document.getElementById('mem-used').textContent = formatBytes(mem.used);
        document.getElementById('mem-avail').textContent = formatBytes(mem.available);
        document.getElementById('mem-total').textContent = formatBytes(mem.total);

        // メモリバー
        const memBar = document.getElementById('mem-bar');
        memBar.style.width = `${mem.percent}%`;
        memBar.classList.remove('warn', 'danger');
        if (mem.percent >= 90)      memBar.classList.add('danger');
        else if (mem.percent >= 75) memBar.classList.add('warn');

        // スワップバー
        const swapBar = document.getElementById('swap-bar');
        swapBar.style.width = `${swap.percent || 0}%`;
        document.getElementById('swap-text').textContent =
            `${formatBytes(swap.used)} / ${formatBytes(swap.total)}`;
    }


    // ============================================================
    //  DOM更新：ディスク
    // ============================================================
    function updateDisks(disks) {
        const container = document.getElementById('disk-list');
        container.innerHTML = '';

        if (!disks || disks.length === 0) {
            container.innerHTML = '<p style="color:var(--text-muted)">No disk information.</p>';
            return;
        }

        disks.forEach(d => {
            const cls = getThresholdClass(d.percent);
            const item = document.createElement('div');
            item.className = 'disk-item';
            item.innerHTML = `
                <div class="disk-header">
                    <span class="disk-name">${d.device || d.mountpoint}</span>
                    <span class="disk-detail">${formatBytes(d.used)} / ${formatBytes(d.total)} (${d.percent.toFixed(1)}%)</span>
                </div>
                <div class="progress-bar">
                    <div class="progress-fill disk-fill ${cls}" style="width: ${d.percent}%"></div>
                </div>
            `;
            container.appendChild(item);
        });
    }


    // ============================================================
    //  DOM更新：ネットワーク
    // ============================================================
    function updateNetwork(net) {
        document.getElementById('net-recv').textContent = formatBytes(net.bytes_recv);
        document.getElementById('net-sent').textContent = formatBytes(net.bytes_sent);
        document.getElementById('net-pkt-recv').textContent = net.packets_recv.toLocaleString();
        document.getElementById('net-pkt-sent').textContent = net.packets_sent.toLocaleString();

        // 受信・送信速度を計算（bytes差分 ÷ 秒数）
        const now = Date.now();
        if (lastNet !== null && lastNetTime !== null) {
            const elapsedSec = (now - lastNetTime) / 1000;
            const recvSpeed = (net.bytes_recv - lastNet.bytes_recv) / elapsedSec;
            const sentSpeed = (net.bytes_sent - lastNet.bytes_sent) / elapsedSec;

            document.getElementById('net-recv-speed').textContent =
                `${formatBytes(recvSpeed)}/s`;
            document.getElementById('net-sent-speed').textContent =
                `${formatBytes(sentSpeed)}/s`;
        }
        lastNet = net;
        lastNetTime = now;
    }


    // ============================================================
    //  Chart.js：履歴グラフ
    // ============================================================
    let historyChart = null;

    function initChart() {
        const ctx = document.getElementById('historyChart').getContext('2d');
        historyChart = new Chart(ctx, {
            type: 'line',
            data: {
                labels: [],
                datasets: [
                    {
                        label: 'CPU %',
                        data: [],
                        borderColor: '#00d4ff',
                        backgroundColor: 'rgba(0, 212, 255, 0.15)',
                        borderWidth: 2,
                        fill: true,
                        tension: 0.4,
                        pointRadius: 0,
                    },
                    {
                        label: 'Memory %',
                        data: [],
                        borderColor: '#a78bfa',
                        backgroundColor: 'rgba(167, 139, 250, 0.15)',
                        borderWidth: 2,
                        fill: true,
                        tension: 0.4,
                        pointRadius: 0,
                    }
                ]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                animation: { duration: 400 },
                plugins: {
                    legend: {
                        labels: {
                            color: '#e6edf3',
                            font: { size: 13 }
                        }
                    },
                    tooltip: {
                        backgroundColor: '#1a1f2e',
                        titleColor: '#e6edf3',
                        bodyColor: '#e6edf3',
                        borderColor: '#2d3548',
                        borderWidth: 1,
                    }
                },
                scales: {
                    y: {
                        beginAtZero: true,
                        max: 100,
                        ticks: {
                            color: '#8b949e',
                            callback: v => v + '%',
                        },
                        grid: { color: '#2d3548' },
                    },
                    x: {
                        ticks: { color: '#8b949e', maxRotation: 0 },
                        grid: { display: false },
                    }
                }
            }
        });
    }

    function updateChart(cpuPercent, memPercent) {
        // 時刻ラベルを「HH:MM:SS」形式で追加
        const now = new Date();
        const label = now.toTimeString().slice(0, 8);

        cpuHistory.push(cpuPercent);
        memHistory.push(memPercent);
        labelHistory.push(label);

        // 履歴が長くなりすぎたら古いものから削除
        while (cpuHistory.length > HISTORY_LENGTH) {
            cpuHistory.shift();
            memHistory.shift();
            labelHistory.shift();
        }

        // Chart.jsのデータを更新して再描画
        historyChart.data.labels = labelHistory;
        historyChart.data.datasets[0].data = cpuHistory;
        historyChart.data.datasets[1].data = memHistory;
        historyChart.update('none');  // 'none' でアニメーションなしの軽量更新
    }


    // ============================================================
    //  DOM更新：プロセス一覧
    // ============================================================
    function updateProcesses(procs) {
        const tbody = document.getElementById('process-tbody');
        tbody.innerHTML = '';

        procs.forEach(p => {
            const tr = document.createElement('tr');
            tr.innerHTML = `
                <td>${p.pid}</td>
                <td>${escapeHtml(p.name)}</td>
                <td>${escapeHtml(p.username)}</td>
                <td class="${getCpuColorClass(p.cpu_percent)}">${p.cpu_percent.toFixed(1)}</td>
                <td>${p.memory_percent.toFixed(2)}</td>
            `;
            tbody.appendChild(tr);
        });
    }

    /**
     * HTMLエスケープ：プロセス名等に < > & " が含まれていてもXSSにならないようにする
     */
    function escapeHtml(str) {
        if (str == null) return '';
        return String(str)
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    }


    // ============================================================
    //  メインループ：APIを叩いて画面を更新
    // ============================================================

    /**
     * /api/stats を呼んで画面を更新
     */
    async function fetchStats() {
        try {
            const res = await fetch('/api/stats');
            if (!res.ok) throw new Error(`HTTP ${res.status}`);
            const data = await res.json();

            updateSystemInfo(data.system, data.load_average);
            updateCpu(data.cpu);
            updateMemory(data.memory, data.swap);
            updateDisks(data.disk);
            updateNetwork(data.network);
            updateChart(data.cpu.percent, data.memory.percent);

            document.getElementById('last-update').textContent = data.timestamp;
        } catch (err) {
            console.error('[fetchStats] error:', err);
        }
    }

    /**
     * /api/processes を呼んでプロセス一覧を更新
     */
    async function fetchProcesses() {
        try {
            const res = await fetch('/api/processes');
            if (!res.ok) throw new Error(`HTTP ${res.status}`);
            const data = await res.json();
            updateProcesses(data);
        } catch (err) {
            console.error('[fetchProcesses] error:', err);
        }
    }


    // ============================================================
    //  起動処理
    // ============================================================
    document.addEventListener('DOMContentLoaded', () => {
        initChart();      // Chart.jsの初期化

        // 初回フェッチ
        fetchStats();
        fetchProcesses();

        // 定期更新（setIntervalで一定時間ごとに繰り返す）
        setInterval(fetchStats, STATS_INTERVAL);
        setInterval(fetchProcesses, PROCESS_INTERVAL);
    });

})();

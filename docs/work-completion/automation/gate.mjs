#!/usr/bin/env node
import { readFileSync, statSync } from 'node:fs';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

export const REQUIRED_GATES = Object.freeze(['security', 'functional', 'recovery', 'handover']);
export const THRESHOLDS = Object.freeze({ rechecks: 2, attempts: 2 });
const STATUSES = new Set(['PASS', 'FAIL', 'NOT_RUN', 'NA']);
const MAX_BYTES = 256 * 1024;
const LIMITS = Object.freeze([
  '自己申告された入力を整理する参考判定です。変更・デプロイ・終了を承認しません。',
  '証跡参照の存在・内容・真実性、現在の実環境、安全性、復旧能力は検証しません。',
  'lab の handover は自己説明の記録で構いませんが、本番のレビューや引継ぎの代替にはなりません。',
  'Git・ネットワーク・サーバー操作・削除・コミット・通知・スケジュール登録は行いません。',
  '反復 2 回の閾値と予算は試行用です。実測して調整し、終了コードをデプロイ許可に流用しないでください。',
]);

const isRecord = value => value !== null && typeof value === 'object' && !Array.isArray(value);
const isText = (value, max = 2048) => typeof value === 'string' && value.trim().length > 0
  && value.length <= max && !/[\u0000-\u001f\u007f]/u.test(value);
const isOptionalText = (value, max = 2048) => value === undefined || value === '' || isText(value, max);

function base(input, errors) {
  return {
    schema_version: '1.0',
    assessment_only: true,
    approval: 'NOT_GRANTED',
    service_action: 'NONE',
    task_id: isRecord(input) && isText(input.task_id, 200) ? input.task_id : null,
    input_valid: errors.length === 0,
    validation_errors: errors,
    thresholds: THRESHOLDS,
    limits: [...LIMITS],
  };
}

function validate(input) {
  const errors = [];
  if (!isRecord(input)) return ['入力は JSON オブジェクトである必要があります。'];
  if (!isText(input.task_id, 200)) errors.push('task_id は空でない 200 文字以内の 1 行文字列が必要です。');
  if (!['lab', 'planned', 'incident'].includes(input.mode)) errors.push('mode は lab / planned / incident が必要です。');
  if (!isText(input.revision, 200)) errors.push('revision は空でない 200 文字以内の 1 行文字列が必要です。');
  if (typeof input.elapsed_minutes !== 'number' || !Number.isFinite(input.elapsed_minutes) || input.elapsed_minutes < 0) {
    errors.push('elapsed_minutes は 0 以上の有限数が必要です。');
  }
  if (typeof input.budget_minutes !== 'number' || !Number.isFinite(input.budget_minutes) || input.budget_minutes <= 0) {
    errors.push('budget_minutes は 0 より大きい有限数が必要です。');
  }
  for (const name of ['rechecks_without_change', 'attempts_without_new_hypothesis']) {
    if (!Number.isSafeInteger(input[name]) || input[name] < 0) errors.push(`${name} は 0 以上の安全な整数が必要です。`);
  }
  for (const name of ['critical_risk', 'new_evidence']) {
    if (typeof input[name] !== 'boolean') errors.push(`${name} は true / false の真偽値が必要です。`);
  }
  if (!isRecord(input.gates)) {
    errors.push('gates は security / functional / recovery / handover を持つオブジェクトが必要です。');
    return errors;
  }
  if (Object.keys(input.gates).some(name => !REQUIRED_GATES.includes(name))) {
    errors.push('gates に未定義の項目があります。必須 4 項目の名前を確認してください。');
  }
  for (const name of REQUIRED_GATES) {
    const gate = input.gates[name];
    if (!isRecord(gate)) {
      errors.push(`${name}: ゲートオブジェクトが必要です。`);
      continue;
    }
    if (!STATUSES.has(gate.status)) {
      errors.push(`${name}: status は PASS / FAIL / NOT_RUN / NA が必要です。`);
    }
    if (gate.status === 'PASS' || gate.status === 'NA') {
      if (!isText(gate.revision, 200)) errors.push(`${name}: PASS / NA には revision が必要です。`);
      if (!isText(gate.evidence_ref)) errors.push(`${name}: PASS / NA には evidence_ref が必要です。`);
    } else {
      if (!isOptionalText(gate.revision, 200)) errors.push(`${name}: revision の型または文字列が不正です。`);
      if (!isOptionalText(gate.evidence_ref)) errors.push(`${name}: evidence_ref の型または文字列が不正です。`);
    }
    if (gate.status === 'NA') {
      if (!isText(gate.rationale, 4000)) errors.push(`${name}: NA には rationale が必要です。`);
    } else if (!isOptionalText(gate.rationale, 4000)) {
      errors.push(`${name}: rationale の型または文字列が不正です。`);
    }
  }
  return errors;
}

/** Pure assessment: reads supplied facts only; never performs operational actions. */
export function assess(input) {
  const errors = validate(input);
  const output = base(input, errors);
  // A positive incident/risk signal wins even when other fields need correction.
  if (isRecord(input) && (input.mode === 'incident' || input.critical_risk === true)) {
    return {
      ...output,
      result: 'COORDINATE',
      reasons: [
        'インシデント対応中、または重大リスクの申告があります。',
        ...(errors.length ? ['入力不備もありますが、対応の連携を優先します。'] : []),
      ],
      next_action: '担当者・責任者と状況、影響、対応継続者、次回更新時刻を共有し、組織の対応手順へ移ってください。サービスを放置・自動停止せず、この判定を終了許可にしないでください。',
    };
  }
  if (errors.length > 0) {
    return {
      ...output,
      result: 'NEEDS_INPUT',
      reasons: ['必須の入力が不足しているか、型・値・証跡参照の形式が不正です。'],
      next_action: 'validation_errors の項目を事実に基づいて補ってください。未実施は NOT_RUN と記録し、PASS や NA の証跡を作り上げないでください。',
    };
  }
  const unmet = [];
  for (const name of REQUIRED_GATES) {
    const gate = input.gates[name];
    if (!['PASS', 'NA'].includes(gate.status)) unmet.push({ gate: name, cause: gate.status });
    else if (gate.revision !== input.revision) unmet.push({ gate: name, cause: 'STALE_REVISION' });
  }
  const detail = { ...output, unmet_gates: unmet };
  if (unmet.length === 0 && input.new_evidence === false) {
    return {
      ...detail,
      result: 'READY_TO_CLOSE',
      reasons: ['必須 4 ゲートの申告が PASS または根拠付き NA で、対象 revision と一致しています。', '未反映の新しい証拠はないと申告されています。'],
      next_action: '人が証跡と適用範囲を確認し、必要な責任者の承認・引継ぎを経て終了を記録してください。新しい事実がなければ同じ確認を繰り返さず、改善案は次の作業に分離してください。',
    };
  }
  // New evidence keeps completion pending even if prior gate records look complete.
  const pending = unmet.length > 0 || input.new_evidence;
  if (pending && input.elapsed_minutes >= input.budget_minutes) {
    return {
      ...detail,
      result: 'PAUSE_AND_RECORD',
      reasons: ['終了を確定できない状態で作業予算に到達しています。', ...(input.new_evidence ? ['新しい証拠の反映と再評価が未完了です。'] : [])],
      next_action: '担当サービスの安全状態と対応継続者を確認し、通常の追加作業を区切ってください。未達・新しい証拠・試した仮説・残る影響・次の 1 手・再開条件を記録し、必要なら担当者へ引き継いでください。',
    };
  }
  if (pending && input.new_evidence === false && input.rechecks_without_change >= THRESHOLDS.rechecks) {
    return {
      ...detail,
      result: 'CHANGE_APPROACH',
      reasons: ['新しい事実がないまま、同じ対象の確認が試行用閾値に達しています。'],
      next_action: '同じ確認の追加を止め、未達ゲートを 1 つ選んでください。別の仮説・小さい切り分け・相談のいずれか 1 つを選び、予想結果と次の確認条件を記録してください。',
    };
  }
  if (pending && input.attempts_without_new_hypothesis >= THRESHOLDS.attempts) {
    return {
      ...detail,
      result: 'CHANGE_APPROACH',
      reasons: ['新しい仮説を立てない試行が、試行用閾値に達しています。', ...(input.new_evidence ? ['新しい証拠を先に整理して、仮説を更新する必要があります。'] : [])],
      next_action: 'いったん試行を区切り、観測事実と予想の差を記録してください。新しい証拠があれば反映し、新しい仮説と検証方法を 1 つ定めるか、担当者に相談してください。',
    };
  }
  return {
    ...detail,
    result: 'CONTINUE',
    reasons: input.new_evidence ? ['新しい証拠があり、終了を保留しています。'] : ['未達ゲートがあり、予算・反復の中断条件には達していません。'],
    next_action: input.new_evidence
      ? '新しい証拠を記録し、影響するゲートと revision の申告を更新して再評価してください。new_evidence は反映と影響確認が済んだ時点で人が false にしてください。'
      : '未達ゲートを 1 つ選び、仮説・予想結果・確認方法を記録して小さく 1 回検証してください。結果を入力へ反映して再評価してください。',
  };
}

const HELP = `サーバー作業の区切り方を整理する、読み取り専用の参考判定です。
使用法: node gate.mjs <input.json>
テスト: node --test gate.test.mjs
引数なし / --help / -h: ヘルプ、終了コード 0
有効入力: 判定 JSON、終了コード 0（承認・実行許可ではありません）
入力不備・読込失敗: 判定 JSON、終了コード 2
詳しい入力形式、試行用閾値、制約は README.md を参照してください。
`;

function inputError(reason) {
  return {
    ...base(null, [reason]),
    result: 'NEEDS_INPUT',
    reasons: ['入力ファイルを評価できません。'],
    next_action: '使用法と JSON の形式を確認して再実行してください。入力内容や OS のエラー詳細は出力していません。',
  };
}

export function runCli(args, { stdout = process.stdout, stderr = process.stderr } = {}) {
  if (args.length === 0 || (args.length === 1 && ['--help', '-h'].includes(args[0]))) {
    stdout.write(HELP);
    return 0;
  }
  if (args.length !== 1 || args[0].startsWith('-')) {
    stderr.write(`${JSON.stringify(inputError('入力 JSON ファイルを 1 つ指定してください。'), null, 2)}\n`);
    return 2;
  }
  let input;
  try {
    const path = resolve(args[0]);
    const info = statSync(path);
    if (!info.isFile() || info.size > MAX_BYTES) {
      stderr.write(`${JSON.stringify(inputError('256 KiB 以下の通常の JSON ファイルが必要です。'), null, 2)}\n`);
      return 2;
    }
    const contents = readFileSync(path, 'utf8');
    if (Buffer.byteLength(contents, 'utf8') > MAX_BYTES) {
      stderr.write(`${JSON.stringify(inputError('入力は 256 KiB 以下にしてください。'), null, 2)}\n`);
      return 2;
    }
    input = JSON.parse(contents.replace(/^\uFEFF/u, ''));
  } catch {
    stderr.write(`${JSON.stringify(inputError('読込可能な JSON ファイルが必要です。'), null, 2)}\n`);
    return 2;
  }
  const result = assess(input);
  stdout.write(`${JSON.stringify(result, null, 2)}\n`);
  return result.input_valid ? 0 : 2;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  process.exitCode = runCli(process.argv.slice(2));
}

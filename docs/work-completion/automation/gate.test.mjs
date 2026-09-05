import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { assess, runCli, REQUIRED_GATES } from './gate.mjs';

function valid(overrides = {}) {
  return {
    task_id: 'LAB-EXAMPLE-001', mode: 'lab', revision: 'fictional-revision-1',
    elapsed_minutes: 20, budget_minutes: 45,
    rechecks_without_change: 0, attempts_without_new_hypothesis: 0,
    critical_risk: false, new_evidence: false,
    gates: Object.fromEntries(REQUIRED_GATES.map(name => [name, {
      status: 'PASS', revision: 'fictional-revision-1', evidence_ref: `fictional:${name}`,
    }])),
    ...overrides,
  };
}
function incomplete(overrides = {}) {
  const input = valid(overrides);
  input.gates.recovery = { status: 'NOT_RUN' };
  return input;
}
function capture(args) {
  let stdout = '', stderr = '';
  const code = runCli(args, {
    stdout: { write: value => { stdout += value; } },
    stderr: { write: value => { stderr += value; } },
  });
  return { code, stdout, stderr };
}

test('all four gates at the same revision permit only a human closure review', () => {
  const result = assess(valid());
  assert.equal(result.result, 'READY_TO_CLOSE');
  assert.equal(result.assessment_only, true);
  assert.equal(result.approval, 'NOT_GRANTED');
  assert.equal(result.service_action, 'NONE');
  assert.match(result.next_action, /人が証跡/);
});
test('completion wins over ordinary time and repetition thresholds', () => {
  assert.equal(assess(valid({ elapsed_minutes: 90, rechecks_without_change: 10, attempts_without_new_hypothesis: 10 })).result, 'READY_TO_CLOSE');
});
test('incident wins over all passing gates', () => {
  assert.equal(assess(valid({ mode: 'incident' })).result, 'COORDINATE');
});
test('critical risk wins over elapsed budget and repetitions', () => {
  assert.equal(assess(incomplete({ critical_risk: true, elapsed_minutes: 100, rechecks_without_change: 8 })).result, 'COORDINATE');
});
test('explicit critical risk wins despite missing input, with invalid status retained', () => {
  const result = assess({ critical_risk: true });
  assert.equal(result.result, 'COORDINATE');
  assert.equal(result.input_valid, false);
  assert.ok(result.validation_errors.length > 0);
});
test('incident with malformed fields coordinates and never silently validates', () => {
  const result = assess({ mode: 'incident', critical_risk: 'false' });
  assert.equal(result.result, 'COORDINATE');
  assert.equal(result.input_valid, false);
});
test('truthy strings do not count as an explicit risk signal', () => {
  assert.equal(assess(valid({ critical_risk: 'true' })).result, 'NEEDS_INPUT');
});
test('NA needs rationale, evidence and current revision', () => {
  const input = valid();
  input.gates.handover = { status: 'NA', revision: input.revision, evidence_ref: 'fictional:scope-review', rationale: 'この架空演習の適用範囲を確認済みというテスト入力' };
  assert.equal(assess(input).result, 'READY_TO_CLOSE');
  delete input.gates.handover.rationale;
  assert.equal(assess(input).result, 'NEEDS_INPUT');
});
test('NA with old revision remains unmet', () => {
  const input = valid();
  input.gates.security = { status: 'NA', revision: 'older', evidence_ref: 'fictional:scope', rationale: '架空の除外理由' };
  const result = assess(input);
  assert.equal(result.result, 'CONTINUE');
  assert.deepEqual(result.unmet_gates, [{ gate: 'security', cause: 'STALE_REVISION' }]);
});
test('PASS without evidence cannot close', () => {
  const input = valid(); delete input.gates.security.evidence_ref;
  assert.equal(assess(input).result, 'NEEDS_INPUT');
});
test('PASS with blank evidence cannot close', () => {
  const input = valid(); input.gates.security.evidence_ref = '   ';
  assert.equal(assess(input).result, 'NEEDS_INPUT');
});
test('PASS without revision cannot close', () => {
  const input = valid(); delete input.gates.security.revision;
  assert.equal(assess(input).result, 'NEEDS_INPUT');
});
test('an older PASS is unmet even with evidence', () => {
  const input = valid(); input.gates.functional.revision = 'older';
  assert.equal(assess(input).result, 'CONTINUE');
});
test('FAIL is unmet rather than invalid when no evidence is available', () => {
  const input = valid(); input.gates.functional = { status: 'FAIL' };
  const result = assess(input);
  assert.equal(result.result, 'CONTINUE');
  assert.equal(result.input_valid, true);
});
test('NOT_RUN is unmet rather than missing input', () => {
  assert.equal(assess(incomplete()).result, 'CONTINUE');
});
test('empty gates cannot produce a vacuous completion', () => {
  assert.equal(assess(valid({ gates: {} })).result, 'NEEDS_INPUT');
});
test('a missing required gate cannot close', () => {
  const input = valid(); delete input.gates.handover;
  assert.equal(assess(input).result, 'NEEDS_INPUT');
});
test('misspelled or additional gate names are surfaced rather than ignored', () => {
  const input = valid(); input.gates.secretTypo = { status: 'FAIL' };
  const result = assess(input);
  assert.equal(result.result, 'NEEDS_INPUT');
  assert.doesNotMatch(JSON.stringify(result), /secretTypo/);
});
test('a malformed gate status is invalid', () => {
  const input = valid(); input.gates.security.status = 'pass';
  assert.equal(assess(input).result, 'NEEDS_INPUT');
});
test('budget equality pauses unfinished work and wins over repetition', () => {
  assert.equal(assess(incomplete({ elapsed_minutes: 45, rechecks_without_change: 2 })).result, 'PAUSE_AND_RECORD');
});
test('just below budget continues unfinished work', () => {
  assert.equal(assess(incomplete({ elapsed_minutes: 44.99 })).result, 'CONTINUE');
});
test('same check threshold changes approach only with no new evidence', () => {
  assert.equal(assess(incomplete({ rechecks_without_change: 2 })).result, 'CHANGE_APPROACH');
  assert.equal(assess(incomplete({ rechecks_without_change: 2, new_evidence: true })).result, 'CONTINUE');
});
test('one recheck remains below threshold', () => {
  assert.equal(assess(incomplete({ rechecks_without_change: 1 })).result, 'CONTINUE');
});
test('no-new-hypothesis attempts reach change threshold', () => {
  assert.equal(assess(incomplete({ attempts_without_new_hypothesis: 2 })).result, 'CHANGE_APPROACH');
});
test('new evidence does not excuse attempts without updating a hypothesis', () => {
  assert.equal(assess(incomplete({ attempts_without_new_hypothesis: 2, new_evidence: true })).result, 'CHANGE_APPROACH');
});
test('new evidence blocks closure when all old records pass', () => {
  const result = assess(valid({ new_evidence: true }));
  assert.equal(result.result, 'CONTINUE');
  assert.match(result.next_action, /人が false/);
});
test('new evidence pending at budget pauses and records instead of closing', () => {
  assert.equal(assess(valid({ new_evidence: true, elapsed_minutes: 45 })).result, 'PAUSE_AND_RECORD');
});
test('planned mode uses the same assessment and requires human evidence review', () => {
  assert.equal(assess(valid({ mode: 'planned' })).result, 'READY_TO_CLOSE');
});
test('root nonobjects are rejected without crashing', () => {
  for (const input of [null, undefined, [], 'secret', 0, true]) assert.equal(assess(input).result, 'NEEDS_INPUT');
});
test('gates must be an object and each required gate must be an object', () => {
  for (const gates of [null, [], 'PASS', 2]) assert.equal(assess(valid({ gates })).result, 'NEEDS_INPUT');
  const input = valid(); input.gates.security = [];
  assert.equal(assess(input).result, 'NEEDS_INPUT');
});
test('numeric strings, nonfinite values, negative time and zero budget are invalid', () => {
  for (const elapsed_minutes of ['20', -1, NaN, Infinity, null]) {
    assert.equal(assess(valid({ elapsed_minutes })).result, 'NEEDS_INPUT');
  }
  for (const budget_minutes of ['45', 0, -1, Infinity, null]) {
    assert.equal(assess(valid({ budget_minutes })).result, 'NEEDS_INPUT');
  }
});
test('attempt counters must be nonnegative safe integers', () => {
  for (const value of [-1, 0.5, '2', Number.MAX_SAFE_INTEGER + 1, null]) {
    assert.equal(assess(valid({ rechecks_without_change: value })).result, 'NEEDS_INPUT');
    assert.equal(assess(valid({ attempts_without_new_hypothesis: value })).result, 'NEEDS_INPUT');
  }
});
test('missing or nonboolean new-evidence declaration never permits closure', () => {
  for (const new_evidence of [undefined, null, 'false', 0]) {
    assert.equal(assess(valid({ new_evidence })).result, 'NEEDS_INPUT');
  }
});
test('blank IDs, missing revisions and unknown modes are invalid', () => {
  for (const override of [{ task_id: '' }, { task_id: 'x\ny' }, { revision: ' ' }, { mode: 'production' }]) {
    assert.equal(assess(valid(override)).result, 'NEEDS_INPUT');
  }
});
test('assessment does not mutate the input', () => {
  const input = valid(); const before = structuredClone(input);
  assess(input); assert.deepEqual(input, before);
});
test('evidence references, rationale and extra private input are not echoed', () => {
  const input = valid({ private_details: 'private-canary-value' });
  input.gates.security.evidence_ref = 'secret-evidence-value';
  input.gates.security.rationale = 'secret-rationale-value';
  const serialized = JSON.stringify(assess(input));
  assert.doesNotMatch(serialized, /private-canary-value|secret-evidence-value|secret-rationale-value/);
  assert.match(serialized, /LAB-EXAMPLE-001/);
});
test('no arguments and the help flags exit successfully', () => {
  for (const args of [[], ['--help'], ['-h']]) {
    const result = capture(args);
    assert.equal(result.code, 0); assert.match(result.stdout, /使用法/); assert.equal(result.stderr, '');
  }
});
test('invalid arguments produce JSON and exit 2 without echoing them', () => {
  const result = capture(['--secret-value', 'private-file']);
  assert.equal(result.code, 2);
  assert.equal(JSON.parse(result.stderr).result, 'NEEDS_INPUT');
  assert.doesNotMatch(result.stderr, /secret-value|private-file/);
});
test('missing file produces exit 2 without exposing the path', () => {
  const result = capture(['__not_existing_private_file_canary__.json']);
  assert.equal(result.code, 2);
  assert.equal(JSON.parse(result.stderr).result, 'NEEDS_INPUT');
  assert.doesNotMatch(result.stderr, /private_file_canary/);
});
test('non-JSON existing file is handled as invalid input', () => {
  const result = capture([fileURLToPath(import.meta.url)]);
  assert.equal(result.code, 2);
  assert.equal(JSON.parse(result.stderr).result, 'NEEDS_INPUT');
});
test('directories are not treated as JSON input', () => {
  const result = capture([fileURLToPath(new URL('.', import.meta.url))]);
  assert.equal(result.code, 2);
});
test('all fictional examples work through the real CLI and never grant approval', () => {
  const examples = { 'ready-lab.json': 'READY_TO_CLOSE', 'repeat-lab.json': 'CHANGE_APPROACH', 'incident.json': 'COORDINATE' };
  for (const [name, expected] of Object.entries(examples)) {
    const result = spawnSync(process.execPath, [fileURLToPath(new URL('./gate.mjs', import.meta.url)), fileURLToPath(new URL(`./examples/${name}`, import.meta.url))], { encoding: 'utf8' });
    assert.equal(result.status, 0, result.stderr);
    const parsed = JSON.parse(result.stdout);
    assert.equal(parsed.result, expected);
    assert.equal(parsed.approval, 'NOT_GRANTED');
  }
});

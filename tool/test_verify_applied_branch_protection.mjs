import assert from 'node:assert/strict';
import test from 'node:test';
import { validateAppliedProtection as validate } from './verify_applied_branch_protection.mjs';
function fixture() {
  return { branch: { protected: true }, rules: [
    ...['pull_request', 'deletion', 'non_fast_forward'].map((type) => ({ type, ruleset_id: 1 })),
    { type: 'required_status_checks', ruleset_id: 1, parameters: { strict_required_status_checks_policy: true,
      required_status_checks: [{ context: 'quality', integration_id: 15368 }] } },
  ], sets: [{ id: 1, enforcement: 'active', bypass_actors: [] }] };
}
function verify(v) { validate(v.branch, v.rules, v.sets, ['quality']); }
test('accepts effective active strict Actions rules with no bypass', () => verify(fixture()));
test('rejects unprotected branches', () => {
  const v = fixture(); v.branch.protected = false; assert.throws(() => verify(v));
});
for (const type of ['pull_request', 'deletion', 'non_fast_forward', 'required_status_checks']) {
  test(`rejects missing ${type}`, () => {
    const v = fixture(); v.rules = v.rules.filter((r) => r.type !== type); assert.throws(() => verify(v));
  });
}
test('rejects name prefixes and different integrations', () => {
  const v = fixture(); const c = v.rules[3].parameters.required_status_checks[0];
  c.context = 'quality-impostor'; assert.throws(() => verify(v));
  c.context = 'quality'; c.integration_id = 999; assert.throws(() => verify(v));
});
test('rejects non-strict checks', () => {
  const v = fixture(); v.rules[3].parameters.strict_required_status_checks_policy = false; assert.throws(() => verify(v));
});
test('rejects inactive, missing or bypass-enabled evidence', () => {
  const v = fixture(); v.sets[0].enforcement = 'evaluate'; assert.throws(() => verify(v));
  v.sets[0].enforcement = 'active'; v.sets[0].bypass_actors = [{ actor_id: 5 }]; assert.throws(() => verify(v));
  v.sets = []; assert.throws(() => verify(v));
});
test('public bypass redaction is reported as unverified, never as no bypass', () => {
  const v = fixture(); delete v.sets[0].bypass_actors;
  assert.deepEqual(validate(v.branch, v.rules, v.sets, ['quality']), { bypassVerified: false });
});

import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

export function validateAppliedProtection(branch, rules, rulesets, expected) {
  assert.equal(branch.protected, true, 'Branch is not protected on GitHub.');
  for (const type of ['pull_request', 'deletion', 'non_fast_forward']) {
    assert(rules.some((r) => r.type === type), `Missing applied rule: ${type}`);
  }
  for (const name of expected) {
    assert(rules.some((r) => r.type === 'required_status_checks'
      && r.parameters?.strict_required_status_checks_policy === true
      && r.parameters.required_status_checks?.some((c) => c.context === name && c.integration_id === 15368)),
    `Missing strict GitHub Actions required check: ${name}`);
  }
  for (const id of new Set(rules.map((r) => r.ruleset_id))) {
    const r = rulesets.find((s) => s.id === id);
    assert(r, `No read-back evidence for ruleset ${id}`);
    assert.equal(r.enforcement, 'active', `Ruleset ${id} is not active.`);
    if (r.bypass_actors !== undefined) {
      assert(Array.isArray(r.bypass_actors) && r.bypass_actors.length === 0, `Ruleset ${id} permits bypass.`);
    }
  }
  return { bypassVerified: rulesets.every((r) => Array.isArray(r.bypass_actors)) };
}

export async function verifyAppliedProtection(repository, request = fetch) {
  assert(/^[\w.-]+\/[\w.-]+$/.test(repository), 'Expected owner/repository.');
  const config = JSON.parse(await readFile(new URL('../.github/rulesets/main-required-checks.json', import.meta.url)));
  const expected = config.rules.find((r) => r.type === 'required_status_checks').parameters.required_status_checks.map((c) => c.context);
  const headers = { Accept: 'application/vnd.github+json', 'User-Agent': 'applied-protection-verifier' };
  if (process.env.BRANCH_PROTECTION_TOKEN) headers.Authorization = `Bearer ${process.env.BRANCH_PROTECTION_TOKEN}`;
  async function get(path) {
    const response = await request(`https://api.github.com/repos/${repository}/${path}`, { headers, signal: AbortSignal.timeout(30000) });
    assert(response.ok, `Applied protection read-back failed: ${path}, HTTP ${response.status}`);
    return response.json();
  }
  const branch = await get('branches/main');
  const rules = await get('rules/branches/main');
  assert(Array.isArray(rules) && rules.length > 0, 'No effective rules apply to main.');
  const ids = [...new Set(rules.map((r) => r.ruleset_id))];
  const sets = await Promise.all(ids.map((id) => get(`rulesets/${id}`)));
  const result = validateAppliedProtection(branch, rules, sets, expected);
  if (!result.bypassVerified) {
    console.warn('::warning::GitHub public read-back hides bypass actors. Bypass configuration is NOT verified by this check; administrative read-back is required.');
  }
  console.log(`Effective branch/check rules PASS: ${repository}/main; ${expected.join(', ')}; bypassVerified=${result.bypassVerified}.`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  await verifyAppliedProtection(process.argv[2] ?? process.env.GITHUB_REPOSITORY);
}

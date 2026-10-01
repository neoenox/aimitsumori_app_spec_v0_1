# Applied branch protection

The checked-in ruleset JSON is a static contract, not proof of GitHub enforcement.
Run `node tool/verify_applied_branch_protection.mjs neoenox/aimitsumori_app_spec_v0_1`
to read the protected flag, effective main rules and contributing rulesets.
PRs, deletion/force-push prevention, exact Actions checks with strict up-to-date
enforcement and active rulesets are required. Missing or inaccessible branch,
rule or ruleset evidence fails. When GitHub exposes bypass actors, any actor
fails validation. Public read-back redacts that field: CI explicitly warns and
reports `bypassVerified=false` rather than claiming no bypass. An administrator
must read back bypass actors separately after policy changes.

Public APIs need no administration PAT. `BRANCH_PROTECTION_TOKEN` is optional for
authenticated/private read-back. Its absence does not bypass validation. API
rate limits and authentication failures remain failures. The validator changes
no repository or credential settings. The administrative read-back on 2026-10-01
confirmed active ruleset 21994520 with an empty bypass actor list. Public CI
cannot detect a later bypass-only change; this is an explicit coverage limit.

The required checks are `Format, analyze, test, debug build`, `Android emulator
E2E`, and `Release APK compile`. The post-merge `Create release tag` job cannot
be a pre-merge requirement because it does not run on PRs.

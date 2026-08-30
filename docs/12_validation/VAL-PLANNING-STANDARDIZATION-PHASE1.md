# VAL-PLANNING-STANDARDIZATION-PHASE1: Repository planning standardization adoption (docs only)

```yaml
id: VAL-PLANNING-STANDARDIZATION-PHASE1
target:
  - STATE.json
  - docs/registry/REPOSITORY_PROFILE.json
  - docs/registry/ARTIFACT_INDEX.json
status: validated
date: 2026-08-30
validator: Copilot CLI agent
scope: documentation-only
```

## Summary

Validated planning-standardization adoption for `database-server` by checking
JSON validity, collectable/indexed path integrity, allowlist/exclusion policy
compliance, forbidden runtime/deploy/schema path references, placeholder-free
registry content, and whitespace-safe git diff.

## Commands and Results

1. JSON parse

```bash
python3 -m json.tool STATE.json >/dev/null
python3 -m json.tool docs/registry/REPOSITORY_PROFILE.json >/dev/null
python3 -m json.tool docs/registry/ARTIFACT_INDEX.json >/dev/null
```

Result: **Pass**.

2. Indexed path + allowlist + exclusion + forbidden-reference checks

```bash
python3 - <<'PY'
import json
from pathlib import Path
from fnmatch import fnmatch

root = Path('.')
profile = json.loads((root / 'docs/registry/REPOSITORY_PROFILE.json').read_text())
index = json.loads((root / 'docs/registry/ARTIFACT_INDEX.json').read_text())

allow = profile['collectable_paths']
exclude = profile['excluded_path_patterns']
forbidden_prefixes = ('src/', 'k8s/', 'scripts/', 'deploy.config.sh', 'prisma/', 'migrations/')
errors = []

for path in allow:
    if not (root / path).is_file():
        errors.append(f'collectable path missing: {path}')
    blocked = [pattern for pattern in exclude if fnmatch(path, pattern)]
    if blocked:
        errors.append(f'collectable path matches excluded pattern {blocked}: {path}')
    if path.startswith(forbidden_prefixes) or '/src/' in path or '/k8s/' in path or '/scripts/' in path or '/migrations/' in path:
        errors.append(f'collectable path references forbidden runtime/deploy/schema location: {path}')

allow_set = set(allow)
for artifact in index['artifacts']:
    path = artifact['path']
    if not (root / path).is_file():
        errors.append(f'indexed artifact path missing: {path}')
    if path not in allow_set:
        errors.append(f'indexed artifact path not in collectable_paths: {path}')
    blocked = [pattern for pattern in exclude if fnmatch(path, pattern)]
    if blocked:
        errors.append(f'indexed artifact path matches excluded pattern {blocked}: {path}')
    if path.startswith(forbidden_prefixes) or '/src/' in path or '/k8s/' in path or '/scripts/' in path or '/migrations/' in path:
        errors.append(f'indexed artifact path references forbidden runtime/deploy/schema location: {path}')

if errors:
    raise SystemExit('\n'.join(errors))
print('PASS')
PY
```

Result: **Pass**.

3. Forbidden placeholder/reference scan

```bash
rg -n -i "example-service|REPLACE_ME|TODO_PLACEHOLDER" \
  STATE.json docs/registry/REPOSITORY_PROFILE.json docs/registry/ARTIFACT_INDEX.json
```

Result: **Pass** (`rg` returned no matches).

4. Git diff whitespace and conflict-marker check

```bash
git diff --check -- \
  STATE.json \
  docs/registry/REPOSITORY_PROFILE.json \
  docs/registry/ARTIFACT_INDEX.json \
  docs/12_validation/VAL-PLANNING-STANDARDIZATION-PHASE1.md
```

Result: **Pass**.

## Notes

- Profile selection is `ips-full` because verified repository artifacts already
  include root service planning docs and canonical numbered IPS planning chain
  files (`00/01/06/11/12/17/21/22`).
- RunLayer mapping remains intentionally unlinked (`null`) because no verified
  repository-local RunLayer slug/permalink evidence exists.
- `TASKS.md` was intentionally left unchanged to avoid unsafe format migration.

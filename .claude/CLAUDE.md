# Ansible HomeLab

## General Rules

- **Research before advising**: When giving architectural advice or framework-specific guidance (variable precedence, module behavior), verify against official documentation. Do not guess.
- **Documentation granularity**: When writing to project memory or documentation, keep content pattern-oriented and guiding. Focus on principles and decision rationale, not implementation minutiae. Avoid code/config snippets.

Domain-specific rules live in `.claude/rules/`. Read relevant rule files before working in each area.

## Quick Reference

```bash
mise run lxc:deploy [hosts] [tags]   # LXC lifecycle
mise run vm:deploy [hosts] [tags]    # VM lifecycle
mise run vps:deploy [hosts] [tags]   # VPS provisioning
mise run swarm:deploy                # Swarm bootstrap
mise run validate                    # Lint & validation
```

- Environment: `MISE_ENV=dev` (default) or `prod` (native mise profiles)
- Vault: `.secrets/vault-{env}.yml` (symlinked to `inventory/group_vars/all/vault.yml`)
- Schemas: `schemas/*.schema.json`

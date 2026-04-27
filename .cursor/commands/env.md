# Use .env as Single Point Of Truth

> **Vault-first:** Production secrets live in Vault at `secret/prod/database-server`, NOT in committed `.env` files.
>
> - **k8s services:** Secrets injected automatically via ESO — no `.env` needed.
> - **Docker Compose / local dev:** Generate `.env` from Vault:
>   ```bash
>   ./shared/scripts/vault-env-gen.sh database-server prod
>   ```
>   Never hand-write secrets. Never commit the generated `.env`.

check for any hardcoded values within the project files, which can be used as variables from .env file.
Replace all hardcoded values in the code with variables from .env
issue command cat .env to see the current variables list.
.env exists in the project and don't recreate it.
It is forbidden to recreate .env file.
Add new keys and values to the .env file, check if they were added there and use the variables in codebase instead of hardcoded values.
Compare .env and .env.example and make sure all variables are in both files.
.env: Contains actual secrets and real configuration for your environment
.env.example: Contains safe placeholders that show other developers what variables they need to set up
Don't Exposed secrets in the example file (security risk)

## Environment Variable Management Commands

```bash
# View current environment variables (contains actual values)
cat .env

# View environment variables template (safe to share)
cat .env.example

# Edit environment variables
# ⚠️ Only edit `.env` for non-secret configuration (ports, feature flags). All credentials must come from Vault via `vault-env-gen.sh`.
nano .env
```

# procol-chat Development Guidelines

> ⚠️ Este es un fork de Chatwoot (https://github.com/chatwoot/chatwoot)
> Repo: https://github.com/Proyectoscol/procol-chat

---

## 🔴 REGLAS CRÍTICAS DEL FORK — LEER PRIMERO

### Rama de trabajo
- **Siempre trabajar en la rama `custom`**. NUNCA hacer commits en `main`.
- Antes de cualquier acción git, verificar con `git branch` que estás en `custom`.
- Si estás en otra rama, cambiar a `custom` antes de continuar.

### Al iniciar cada sesión
1. Ejecutar `git branch` y confirmar que estás en `custom`
2. Ejecutar `git status` e informar al usuario si hay cambios pendientes
3. Si estás en `main` u otra rama, avisar al usuario antes de hacer cualquier cosa

### Reglas git
- `main` es espejo limpio del upstream oficial — **no tocar nunca**
- Pedir confirmación explícita al usuario antes de cada commit
- Nunca hacer `git push --force`
- Nunca hacer merge de `main` hacia `custom` sin autorización explícita del usuario
- No referenciar Claude en los mensajes de commit

### Reglas de modificación de código
- Preferir ocultar elementos con CSS (`v-show="false"` o clase Tailwind `hidden`) antes que borrarlos
- No borrar bloques grandes de código — comentarlos si es necesario quitarlos
- Los cambios deben ser en el menor número de líneas posible
- Si un cambio afecta más de 3 archivos, pedir confirmación antes de proceder
- Siempre buscar en `enterprise/` cuando se modifique lógica del core

### Flujo de deploy
1. Cambio en rama `custom` → commit → push
2. GitHub Actions construye imagen Docker automáticamente (~20-30 min)
3. El usuario hace Redeploy en EasyPanel manualmente
- **Claude NO hace deploy**, solo prepara el código

### Sincronización con upstream
Cuando el usuario quiera traer cambios del chatwoot oficial:
1. En GitHub: rama `main` → "Sync fork" → "Update branch"
2. En terminal: `git checkout custom && git rebase main`
3. Resolver conflictos con cuidado — los cambios propios están en `custom`

---

## Build / Test / Lint

- **Setup**: `bundle install && pnpm install`
- **Run Dev**: `pnpm dev` or `overmind start -f ./Procfile.dev`
- **Seed Local Test Data**: `bundle exec rails db:seed`
- **Seed Search Test Data**: `bundle exec rails search:setup_test_data`
- **Seed Account Sample Data**: `Seeders::AccountSeeder` via Super Admin → Accounts → Seed
- **Lint JS/Vue**: `pnpm eslint` / `pnpm eslint:fix`
- **Lint Ruby**: `bundle exec rubocop -a`
- **Test JS**: `pnpm test` or `pnpm test:watch`
- **Test Ruby**: `bundle exec rspec spec/path/to/file_spec.rb`
- **Single Test**: `bundle exec rspec spec/path/to/file_spec.rb:LINE_NUMBER`
- **Ruby Version**: Manage via `rbenv`, install version in `.ruby-version`
- **rbenv setup**: `eval "$(rbenv init -)"` antes de cualquier comando bundle/rspec
- Siempre usar `bundle exec` para tareas Ruby CLI

## Code Style

- **Ruby**: RuboCop (150 chars max)
- **Vue/JS**: ESLint (Airbnb base + Vue 3 recommended)
- **Vue Components**: PascalCase
- **Events**: camelCase
- **I18n**: No bare strings en templates; usar i18n
- **Error Handling**: Custom exceptions en `lib/custom_exceptions/`
- **Vue API**: Siempre usar Composition API con `<script setup>`

## Styling

- **Tailwind Only**: No CSS custom, no scoped CSS, no inline styles
- **Colors**: Ver `tailwind.config.js`

## General Guidelines

- MVP focus: mínimo cambio de código
- Preferir código legible sobre abstracciones elaboradas
- No escribir specs a menos que se pida explícitamente
- Eliminar código muerto/no alcanzable
- No escribir múltiples versiones del mismo logic
- Prefer the smallest production-ready change that solves the current problem.
- Build for the expected production path first. Do not add speculative guards, fallbacks, retries, or edge-case handling unless the caller can actually hit that case or production has proven it necessary.
- Enforce eligibility and exclusivity rules at the earliest shared entry point. Do not repeat backup guards across downstream jobs, callbacks, services, or writes unless a proven independent path bypasses that point.
- When an impossible or misconfigured state would indicate a setup/deployment bug, let it fail loudly instead of silently skipping behavior.
- For locked/internal configs that must exist in production, prefer direct reads (`find`, `find_by!`, required hash keys) over silent fallbacks.
- Do not add validation or response checks unless the code uses the result or the check changes behavior meaningfully.
- Prefer existing repo dependencies/client libraries over hand-rolled protocol code for auth, signing, parsing, or API plumbing.
- Avoid one-use private helpers unless they hide real complexity or make the main flow meaningfully easier to read.
- Prefer minimal, readable code over elaborate abstractions; clarity beats cleverness
- Break down complex tasks into small, testable units
- Iterate after confirmation
- Avoid writing specs unless explicitly asked
- In specs, avoid custom helper methods for setup/data. Prefer `let` values and direct per-example setup; only add a helper when it removes meaningful repeated complexity.
- Remove dead/unreachable/unused code
- Don’t write multiple versions or backups for the same logic — pick the best approach and implement it
- Prefer `with_modified_env` (from spec helpers) over stubbing `ENV` directly in specs
- Specs in parallel/reloading environments: prefer comparing `error.class.name` over constant class equality when asserting raised errors

## Codex Worktree Workflow

- Use a separate git worktree + branch per task to keep changes isolated.
- Keep Codex-specific local setup under `.codex/` and use `Procfile.worktree` for worktree process orchestration.
- The setup workflow in `.codex/environments/environment.toml` should dynamically generate per-worktree DB/port values (Rails, Vite, Redis DB index) to avoid collisions.
- Start each worktree with its own Overmind socket/title so multiple instances can run at the same time.

## Commit Messages

- Conventional Commits: `type(scope): subject`
- Ejemplo: `feat(ui): hide premium menu items`
- No referenciar Claude en commits

## Translations

- Solo actualizar `en.yml` y `en.json`
- Backend i18n → `en.yml`, Frontend i18n → `en.json`

## Frontend

- Archivos en `app/javascript/`
- Rutas Vue en `app/javascript/dashboard/router/`
- Usar `components-next/` para message bubbles (el resto está en deprecación)
- **Translations**:
  - For product and source-string changes, only update `en.yml` and `en.json`; other languages are handled through Crowdin and the community
  - Crowdin-generated translation sync PRs may update non-English locale files; do not flag those changes solely for modifying translated locale files
  - Preserve product and brand names, OAuth scopes, API values, and other machine-readable identifiers unless an official localized form exists
  - When reviewing Crowdin syncs, verify protected terms remain unchanged. Add newly introduced product names, brand names, and machine-readable identifiers to the Crowdin glossary as non-translatable, and keep the glossary current

## Enterprise Edition

- Overlay en `enterprise/` que extiende el OSS
- Buscar archivos relacionados en ambos árboles antes de editar
- Evitar hardcodear comportamiento específico de plan en OSS
- Preferir feature flags o extension points

## Frontend Conventions

- Prefer existing design-system utilities and shared composables.
- Use typography utilities instead of manually recreating font styles.
- Use logical Tailwind utilities (`ms`, `me`, `start`, `end`) for direction-aware layouts.
- Use `rem` for arbitrary CSS dimensions; preserve native numeric values required by chart/SVG APIs.
- Extract repeated or domain-specific strings, thresholds, colors, and durations into named constants.
- Use shared request-cancellation utilities instead of local `AbortController` logic.

## Stack del proyecto

- Frontend: Vue 3 + Vite + Tailwind
- Backend: Ruby on Rails
- Workers: Sidekiq
- DB: PostgreSQL + Redis
- Imagen Docker: `ghcr.io/proyectoscol/procol-chat:latest`

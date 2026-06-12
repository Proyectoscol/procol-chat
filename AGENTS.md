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
- Usar `components-next/` para message bubbles

## Enterprise Edition

- Overlay en `enterprise/` que extiende el OSS
- Buscar archivos relacionados en ambos árboles antes de editar
- Evitar hardcodear comportamiento específico de plan en OSS
- Preferir feature flags o extension points

## Stack del proyecto

- Frontend: Vue 3 + Vite + Tailwind
- Backend: Ruby on Rails
- Workers: Sidekiq
- DB: PostgreSQL + Redis
- Imagen Docker: `ghcr.io/proyectoscol/procol-chat:latest`

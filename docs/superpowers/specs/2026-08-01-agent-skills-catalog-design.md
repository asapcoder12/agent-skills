# Каталог агентских скиллов: дизайн репозитория

Дата: 2026-08-01
Репозиторий: `asapcoder12/agent-skills`

## Цель

Превратить репозиторий в публичный каталог агентских скиллов, который:

1. устанавливается одной командой с интерактивным мульти-выбором скиллов и выбором харнеса;
2. даёт пользователю готовый блок маршрутизации для файла инструкций его агента,
   собранный только под те скиллы, которые он реально поставил;
3. не выпускает наружу битые скиллы — структура и метаданные проверяются в CI.

## Исходный факт, определяющий дизайн

Мульти-выбор скиллов и выбор харнеса **уже реализованы в CLI `skills`** и не требуют
собственного установщика. `npx skills add <owner>/<repo>` последовательно спрашивает:

1. какие скиллы установить (чек-бокс список),
2. для каких агентов (75 поддерживаемых: claude-code, cursor, codex, github-copilot,
   windsurf, gemini, cline, amp, antigravity и др.),
3. symlink или copy.

CLI находит скиллы по стандартным раскладкам, в том числе плоской `skills/<имя>/SKILL.md` —
это текущая раскладка репозитория. Манифест уровня репозитория для установки не нужен.

Следствие: работа сводится не к написанию установщика, а к тому, чтобы репозиторий был
корректным, самоописанным каталогом.

## Что в объём не входит

- Собственный установочный скрипт (`install.sh` / `install.ps1`) — дублировал бы CLI.
- Версионирование через changesets, CHANGELOG, release-workflow — добавляется позже,
  когда скиллов станет много.
- Категории (`skills/<категория>/<имя>/`) — раскладка остаётся плоской. CLI поддерживает
  вложенность, поэтому переход на категории позже не ломающий.
- Слой `docs/<категория>/<скилл>.md` как отдельная человеческая документация.
- Переписывание тел SKILL.md. Меняются только поля `description` (см. ниже).

## Структура репозитория

```
skills/
  azure-devops-my-workitems/
    SKILL.md
    ROUTING.md
    azdo-mine.sh
  documentation-writer/
    SKILL.md
    ROUTING.md
  error-handling-patterns/
    SKILL.md
    ROUTING.md
    references/details.md
.claude-plugin/
  plugin.json
  marketplace.json
scripts/
  validate.mjs
  routing.mjs
.github/workflows/ci.yml
package.json
README.md
CONTRIBUTING.md
LICENSE
```

Существующие файлы не перемещаются. Новое — `ROUTING.md` на каждый скилл и всё, что
вне `skills/`.

## Компоненты

### 1. Скилл

Единица установки — папка `skills/<имя>/` с обязательным `SKILL.md`. Требования к
frontmatter (по официальным лимитам Agent Skills):

| Поле | Правило |
|---|---|
| `name` | обязателен; ≤ 64 символов; только `[a-z0-9-]`; совпадает с именем папки; не содержит `anthropic` или `claude` |
| `description` | обязателен; непустой; ≤ 1024 символов; без XML-тегов; третье лицо |

Тело SKILL.md — до 500 строк. Всё, что длиннее, выносится в `references/`.

`description` — единственное, что агент видит до срабатывания скилла, поэтому он несёт
всю маршрутизацию: **что скилл делает**, **когда его звать**, **когда точно не звать**,
**ключевые слова**. Скилл должен работать точно даже у пользователя, который ничего не
настраивал в своём файле инструкций.

### 2. ROUTING.md — источник правды для блока маршрутизации

Файл `skills/<имя>/ROUTING.md` содержит один абзац: текст, который станет буллетом в
блоке Skills пользователя. Без ведущего `- `, без имени скилла в начале — генератор
добавит и то, и другое.

Хранится рядом со скиллом, а не в общем реестре: при добавлении скилла правится одно
место, рассинхрон невозможен по построению.

Содержимое на старте — формулировки, которые уже используются автором:

**`skills/azure-devops-my-workitems/ROUTING.md`**

```
use only when the user invokes it by name or directly asks about their own Azure Boards
work items: list/show the items assigned to them, create a Task under one, update fields
on one, set an item's state, or comment on it (every write goes through `azdo-mine.sh`,
which fails closed unless the item is verifiably theirs). Never trigger it from ordinary
git, branch, PR, or build activity, or from any task where the user hasn't mentioned work
items — and never use it to touch someone else's item
```

**`skills/documentation-writer/ROUTING.md`**

```
use when authoring or restructuring a standalone document: a new or reworked file under
`docs/`, a README, or a Diátaxis tutorial/how-to/reference/explanation (runs a clarify →
outline → approval → write workflow). Not for docstrings, code comments, log/exception
text, commit/PR bodies, small doc fixes, or the agent-instructions file itself
```

**`skills/error-handling-patterns/ROUTING.md`**

```
use when designing a new error-handling strategy: an exception hierarchy, Result type,
API error contract, or retry/circuit-breaker/timeout policy (its advice is input; the
repo's own conventions and minimal, surgical changes win). Not for routine `try/except`,
bugfixes, or reading an existing stack trace
```

Формулировка для `documentation-writer` намеренно обобщена: вместо `CLAUDE.md itself`
написано `the agent-instructions file itself`, поскольку блок предназначен для любого
харнеса. Упоминания конкретных для одного проекта функций (`remote_call`, `gql_post`,
Foundry IO) убраны — в публичном каталоге они бессмысленны.

### 3. `scripts/routing.mjs` — генератор блока

```
node scripts/routing.mjs                                    # все скиллы
node scripts/routing.mjs documentation-writer error-handling-patterns   # выбранные
npm run routing -- documentation-writer                     # то же через npm
```

Читает `skills/*/SKILL.md` (берёт `name`) и `skills/*/ROUTING.md` (берёт текст),
печатает в stdout:

```
Ask your agent:

────────────────────────────────────────────────────────────
Add the section below to this project's agent-instructions file — CLAUDE.md,
AGENTS.md, GEMINI.md, .cursor/rules/, or whatever file this harness reads for
project instructions. Put it where the project's other conventions live, and
keep the wording exactly as written.

## Skills

Invoke by exact name via the Skill tool, only on the tasks below. Skills
*inform*; the conventions above in this file always win.

- `azure-devops-my-workitems` — use only when the user invokes it by name or …
- `documentation-writer` — use when authoring or restructuring a standalone …
────────────────────────────────────────────────────────────
```

Harness-агностичность достигается **инструкцией агенту о том, куда положить блок**, а не
выхолащиванием самого блока. Текст блока сохраняется дословно, включая «via the Skill
tool»: агент любого харнеса понимает это как «вызови скилл по имени».

Порядок буллетов — порядок аргументов; без аргументов — алфавитный. Неизвестное имя
скилла: сообщение в stderr со списком доступных, код выхода 1. Шапка-инструкция и
преамбула блока — константы в начале `routing.mjs`, чтобы правиться в одном месте.

### 4. `scripts/validate.mjs` — валидатор

```
node scripts/validate.mjs      # или npm run validate
```

Проверки:

1. каждая папка в `skills/` содержит `SKILL.md`;
2. frontmatter парсится и содержит `name` и `description`;
3. `name` ≤ 64 символов, соответствует `^[a-z0-9]+(-[a-z0-9]+)*$`, не содержит
   `anthropic` / `claude`, совпадает с именем папки;
4. `description` непустой, ≤ 1024 символов, не содержит `<` … `>`-тегов;
5. имена скиллов уникальны;
6. тело SKILL.md ≤ 500 строк (предупреждение, не ошибка);
7. `ROUTING.md` существует, непустой, не начинается с `- ` и не начинается с имени скилла;
8. `plugin.json.skills` — множество, точно равное множеству папок в `skills/`
   (сообщает и лишние, и недостающие пути);
9. каждый скилл упомянут в таблице каталога в `README.md`.

Парсер frontmatter — собственный, ~30 строк: берётся блок между первой и второй строкой
`---`, разбираются пары `ключ: значение` верхнего уровня. Этого достаточно, потому что
валидные SKILL.md содержат только скалярные `name` и `description`. Если строка
frontmatter не разбирается — это ошибка валидации, а не молчаливый пропуск.

Вывод: по строке на проблему в формате `skills/<имя>/SKILL.md: <что не так>`. Код выхода
0 при отсутствии ошибок, 1 при наличии. Предупреждения не влияют на код выхода.

### 5. `.claude-plugin/` — второй путь установки

Даёт `claude plugins install` в дополнение к `npx skills add`.

`plugin.json`: `name`, `version`, `description`, `author`, `repository`, `license`,
`keywords`, `skills` — массив путей вида `./skills/<имя>`. Версия ведётся вручную
(changesets в объём не входят), валидатор её не проверяет.

`marketplace.json`: `name`, `owner`, `description`, `plugins` — один элемент,
указывающий на `./`.

Синхронность `skills[]` с содержимым `skills/` обеспечивает валидатор (проверка 8).

### 6. `README.md`

Разделы, в порядке:

1. **Что это** — одна-две фразы.
2. **Установка** — `npx skills add asapcoder12/agent-skills`; описание интерактивного
   потока (выбор скиллов → выбор агентов → symlink/copy); неинтерактивные флаги
   (`-s` скиллы, `-a` агенты, `-g` глобально, `--copy`, `--all`, `--list`); альтернатива
   через `claude plugins install`.
3. **Скиллы** — таблица: имя со ссылкой на `SKILL.md` | что делает. Каждая строка
   проверяется валидатором на присутствие.
4. **Рекомендуемая настройка** — почему блок Skills нужен (`description` даёт агенту
   знание о скилле, блок даёт приоритет и запрет на всё остальное), harness-агностичная
   инструкция, готовый блок для всех скиллов и упоминание `npm run routing -- <имена>`
   для подмножества.
5. **Contributing** — ссылка на `CONTRIBUTING.md`.

### 7. `CONTRIBUTING.md`

Как добавить скилл: создать `skills/<имя>/SKILL.md` с корректным frontmatter, написать
`ROUTING.md`, добавить путь в `plugin.json`, добавить строку в таблицу README, прогнать
`npm run validate`. Плюс рекомендации к `description` (третье лицо, триггеры,
анти-триггеры, ключевые слова) и к телу (≤ 500 строк, длинное — в `references/`).

### 8. `package.json`

`private: true`, ноль зависимостей. Скрипты: `validate`, `routing`. Существует ради
удобных команд и ради того, чтобы CI не требовал `npm install`.

### 9. CI

`.github/workflows/ci.yml` — на `push` и `pull_request`: checkout, setup-node (20),
`node scripts/validate.mjs`. Без `npm install`, так как зависимостей нет.

### 10. `LICENSE`

MIT, правообладатель — ASAP Coder. Обычный выбор для публичного каталога скиллов;
меняется одним файлом, если нужно иное.

## Изменения в существующих скиллах

`azure-devops-my-workitems` — `description` не меняется, он уже построен по нужной схеме.

`documentation-writer` — новый `description`:

```yaml
description: Authors or restructures a standalone document using the Diátaxis framework, running a clarify → outline → approval → write workflow to produce a tutorial, how-to guide, reference, or explanation. Use when creating or reworking a file under docs/, a README, a getting-started guide, or an architecture explainer, or when the user asks to write or restructure documentation. Do NOT use for docstrings, code comments, log or exception text, commit and PR bodies, typo-level doc fixes, or agent-instruction files. Keywords - Diátaxis, tutorial, how-to guide, reference doc, explanation, docs site, README.
```

Причина замены: текущий текст (`Diátaxis Documentation Expert. An expert technical writer
specializing in…`) описывает роль, а не условия срабатывания, написан не в третьем лице
относительно скилла и не содержит анти-триггеров — агент не может по нему решить, звать
скилл или нет.

`error-handling-patterns` — новый `description`:

```yaml
description: Provides patterns for designing an error-handling strategy - exception hierarchies versus Result types, error propagation and wrapping, and retry, timeout, circuit-breaker and graceful-degradation policies. Use when designing a new error model, an API error contract, or a resilience policy around an unreliable dependency, or when reviewing how failures are surfaced across a codebase. Do NOT use for a routine try/except around a single call, ordinary bugfixes, or reading an existing stack trace. Keywords - Result type, exception hierarchy, retry, backoff, circuit breaker, timeout, error contract, graceful degradation.
```

Причина замены: текущий текст перечисляет темы, но его условие («Use when implementing
error handling») настолько широкое, что скилл будет подхватываться на любом `try/except`.

Оба новых `description` — в пределах 1024 символов, в третьем лице, с явными
анти-триггерами и ключевыми словами.

## Приёмка

Работа считается выполненной, когда:

1. `node scripts/validate.mjs` завершается с кодом 0 и без ошибок;
2. временная поломка любого инварианта (переименовать `SKILL.md`, стереть `description`,
   удалить путь из `plugin.json`, убрать строку из README) даёт код выхода 1 и внятное
   сообщение; после отката снова 0;
3. `node scripts/routing.mjs` печатает блок с тремя буллетами;
   `node scripts/routing.mjs documentation-writer` — с одним;
   `node scripts/routing.mjs nope` — ошибка со списком доступных имён и код 1;
4. `npx skills add . --list` из корня репозитория перечисляет ровно три скилла —
   подтверждение, что CLI видит каталог;
5. CI зелёный на ветке.

Ручных проверок в реальном харнесе спека не требует: срабатывание `description` — вопрос
последующей итерации по наблюдению, а не приёмки этого изменения.

## Риски

- **`description` может не давать нужной точности с первого раза.** Смягчается блоком
  Skills, который перекрывает промах, и тем, что `description` правится одной строкой.
- **`plugin.json` ведётся вручную.** Валидатор ловит расхождение до мержа.
- **Фраза «via the Skill tool» родом из Claude Code.** Для прочих харнесов читается как
  «вызови скилл по имени» и вреда не наносит; если на практике окажется иначе — правится
  в одной константе `routing.mjs`.

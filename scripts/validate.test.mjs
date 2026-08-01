import { test } from 'node:test'
import assert from 'node:assert/strict'
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join, dirname } from 'node:path'

import { parseFrontmatter, validateSkillFrontmatter, validateRepo } from './validate.mjs'

test('parseFrontmatter reads name and description', () => {
  const text = '---\nname: demo-skill\ndescription: Does a thing.\n---\n\n# Demo\n'
  const { fields } = parseFrontmatter(text)
  assert.equal(fields.name, 'demo-skill')
  assert.equal(fields.description, 'Does a thing.')
})

test('parseFrontmatter strips surrounding quotes', () => {
  const text = "---\nname: demo-skill\ndescription: 'Quoted value.'\n---\n\nbody\n"
  const { fields } = parseFrontmatter(text)
  assert.equal(fields.description, 'Quoted value.')
})

test('parseFrontmatter counts body lines without trailing blanks', () => {
  const text = '---\nname: demo-skill\ndescription: Does a thing.\n---\nline one\nline two\n\n\n'
  const { bodyLineCount } = parseFrontmatter(text)
  assert.equal(bodyLineCount, 2)
})

test('parseFrontmatter tolerates CRLF line endings', () => {
  const text = '---\r\nname: demo-skill\r\ndescription: Does a thing.\r\n---\r\n\r\nbody\r\n'
  const { fields } = parseFrontmatter(text)
  assert.equal(fields.name, 'demo-skill')
})

test('parseFrontmatter throws when the file does not open with ---', () => {
  assert.throws(() => parseFrontmatter('# No frontmatter\n'), /must start with ---/)
})

test('parseFrontmatter throws when the closing --- is missing', () => {
  assert.throws(() => parseFrontmatter('---\nname: demo-skill\n'), /no closing ---/)
})

test('parseFrontmatter throws on a line it cannot parse', () => {
  const text = '---\nname: demo-skill\n  - not a key\n---\n\nbody\n'
  assert.throws(() => parseFrontmatter(text), /unparseable frontmatter line/)
})

function skillText({ name = 'demo-skill', description = 'Does a thing. Use when testing.', body = '# Demo' } = {}) {
  return `---\nname: ${name}\ndescription: ${description}\n---\n\n${body}\n`
}

test('validateSkillFrontmatter accepts a clean skill', () => {
  const { errors, warnings } = validateSkillFrontmatter('demo-skill', skillText())
  assert.deepEqual(errors, [])
  assert.deepEqual(warnings, [])
})

test('validateSkillFrontmatter reports malformed frontmatter as a single error', () => {
  const { errors } = validateSkillFrontmatter('demo-skill', '# no frontmatter\n')
  assert.equal(errors.length, 1)
  assert.match(errors[0], /must start with ---/)
})

test('validateSkillFrontmatter rejects a name that differs from the directory', () => {
  const { errors } = validateSkillFrontmatter('other-name', skillText())
  assert.equal(errors.length, 1)
  assert.match(errors[0], /does not match directory name "other-name"/)
})

test('validateSkillFrontmatter rejects an uppercase name', () => {
  const { errors } = validateSkillFrontmatter('Demo-Skill', skillText({ name: 'Demo-Skill' }))
  assert.ok(errors.some((message) => /lowercase letters, digits and single hyphens/.test(message)))
})

test('validateSkillFrontmatter rejects a reserved word in the name', () => {
  const { errors } = validateSkillFrontmatter('claude-helper', skillText({ name: 'claude-helper' }))
  assert.ok(errors.some((message) => /reserved word "claude"/.test(message)))
})

test('validateSkillFrontmatter rejects a name over 64 characters', () => {
  const longName = 'a'.repeat(65)
  const { errors } = validateSkillFrontmatter(longName, skillText({ name: longName }))
  assert.ok(errors.some((message) => /name is 65 characters/.test(message)))
})

test('validateSkillFrontmatter rejects a missing description', () => {
  const text = '---\nname: demo-skill\n---\n\n# Demo\n'
  const { errors } = validateSkillFrontmatter('demo-skill', text)
  assert.ok(errors.some((message) => /missing `description`/.test(message)))
})

test('validateSkillFrontmatter rejects a description over 1024 characters', () => {
  const { errors } = validateSkillFrontmatter('demo-skill', skillText({ description: 'x'.repeat(1025) }))
  assert.ok(errors.some((message) => /description is 1025 characters/.test(message)))
})

test('validateSkillFrontmatter rejects tags in the description', () => {
  const { errors } = validateSkillFrontmatter('demo-skill', skillText({ description: 'Use when <thinking> happens.' }))
  assert.ok(errors.some((message) => /must not contain XML or HTML tags/.test(message)))
})

test('validateSkillFrontmatter warns rather than errors on a long body', () => {
  // 501 content lines, plus the blank line that follows the frontmatter, is 502 body lines
  const body = Array.from({ length: 501 }, (_, index) => `line ${index}`).join('\n')
  const { errors, warnings } = validateSkillFrontmatter('demo-skill', skillText({ body }))
  assert.deepEqual(errors, [])
  assert.equal(warnings.length, 1)
  assert.match(warnings[0], /body is 502 lines/)
})

function validRepoFiles(overrides = {}) {
  const files = {
    'skills/demo-skill/SKILL.md': '---\nname: demo-skill\ndescription: Does a thing. Use when testing.\n---\n\n# Demo\n',
    '.claude-plugin/plugin.json': JSON.stringify({ skills: ['./skills/demo-skill'] }, null, 2),
    'README.md': [
      '| Skill | What it does |',
      '|---|---|',
      '| [`demo-skill`](skills/demo-skill/SKILL.md) | Demo |',
      '',
      '- `demo-skill` — use when testing',
      ''
    ].join('\n')
  }
  for (const [path, contents] of Object.entries(overrides)) {
    if (contents === null) delete files[path]
    else files[path] = contents
  }
  return files
}

function makeRepo(t, files) {
  const root = mkdtempSync(join(tmpdir(), 'agent-skills-'))
  t.after(() => rmSync(root, { recursive: true, force: true }))
  for (const [relativePath, contents] of Object.entries(files)) {
    const full = join(root, relativePath)
    mkdirSync(dirname(full), { recursive: true })
    writeFileSync(full, contents)
  }
  return root
}

test('validateRepo accepts a well-formed repo', (t) => {
  const { errors, warnings, skills } = validateRepo(makeRepo(t, validRepoFiles()))
  assert.deepEqual(errors, [])
  assert.deepEqual(warnings, [])
  assert.deepEqual(skills, ['demo-skill'])
})

test('validateRepo reports a skill directory without SKILL.md', (t) => {
  const files = validRepoFiles({ 'skills/demo-skill/SKILL.md': null, 'skills/demo-skill/notes.md': 'hi' })
  const { errors } = validateRepo(makeRepo(t, files))
  assert.ok(errors.some((message) => /skills\/demo-skill: SKILL\.md is missing/.test(message)))
})

test('validateRepo prefixes skill errors with the file path', (t) => {
  const files = validRepoFiles({
    'skills/demo-skill/SKILL.md': '---\nname: wrong-name\ndescription: Does a thing.\n---\n\n# Demo\n'
  })
  const { errors } = validateRepo(makeRepo(t, files))
  assert.ok(errors.some((message) => message.startsWith('skills/demo-skill/SKILL.md: ')))
})

test('validateRepo reports a skill missing from plugin.json', (t) => {
  const files = validRepoFiles({ '.claude-plugin/plugin.json': JSON.stringify({ skills: [] }) })
  const { errors } = validateRepo(makeRepo(t, files))
  assert.ok(errors.some((message) => /missing "\.\/skills\/demo-skill"/.test(message)))
})

test('validateRepo reports a stale path in plugin.json', (t) => {
  const files = validRepoFiles({
    '.claude-plugin/plugin.json': JSON.stringify({ skills: ['./skills/demo-skill', './skills/gone'] })
  })
  const { errors } = validateRepo(makeRepo(t, files))
  assert.ok(errors.some((message) => /"\.\/skills\/gone" does not exist/.test(message)))
})

test('validateRepo reports invalid JSON in plugin.json', (t) => {
  const files = validRepoFiles({ '.claude-plugin/plugin.json': '{ not json' })
  const { errors } = validateRepo(makeRepo(t, files))
  assert.ok(errors.some((message) => /invalid JSON/.test(message)))
})

test('validateRepo reports a skill missing from the README table', (t) => {
  const files = validRepoFiles({ 'README.md': '- `demo-skill` — use when testing\n' })
  const { errors } = validateRepo(makeRepo(t, files))
  assert.ok(errors.some((message) => /no catalog table row for "demo-skill"/.test(message)))
})

test('validateRepo reports a skill missing from the README block', (t) => {
  const files = validRepoFiles({ 'README.md': '| [`demo-skill`](skills/demo-skill/SKILL.md) | Demo |\n' })
  const { errors } = validateRepo(makeRepo(t, files))
  assert.ok(errors.some((message) => /no Skills-block bullet for "demo-skill"/.test(message)))
})

test('validateRepo does not accept a hyphen in place of the em dash', (t) => {
  const files = validRepoFiles({
    'README.md': '| [`demo-skill`](skills/demo-skill/SKILL.md) | Demo |\n- `demo-skill` - use when testing\n'
  })
  const { errors } = validateRepo(makeRepo(t, files))
  assert.ok(errors.some((message) => /no Skills-block bullet for "demo-skill"/.test(message)))
})

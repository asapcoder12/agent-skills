import { test } from 'node:test'
import assert from 'node:assert/strict'

import { parseFrontmatter } from './validate.mjs'

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

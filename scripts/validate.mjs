import { existsSync, readdirSync, readFileSync } from 'node:fs'
import { join, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

export const MAX_NAME = 64
export const MAX_DESCRIPTION = 1024
export const MAX_BODY_LINES = 500
export const NAME_PATTERN = /^[a-z0-9]+(-[a-z0-9]+)*$/
export const RESERVED_WORDS = ['anthropic', 'claude']

function unquote(value) {
  if (value.length < 2) return value
  const first = value[0]
  const last = value[value.length - 1]
  if ((first === '"' && last === '"') || (first === "'" && last === "'")) {
    return value.slice(1, -1)
  }
  return value
}

export function parseFrontmatter(text) {
  const lines = text.replace(/\r\n/g, '\n').split('\n')
  if (lines[0] !== '---') {
    throw new Error('frontmatter must start with --- on the first line')
  }
  const closingIndex = lines.indexOf('---', 1)
  if (closingIndex === -1) {
    throw new Error('frontmatter has no closing ---')
  }

  const fields = {}
  for (let index = 1; index < closingIndex; index += 1) {
    const line = lines[index]
    if (line.trim() === '') continue
    const match = /^([A-Za-z0-9_-]+):\s*(.*)$/.exec(line)
    if (match === null) {
      throw new Error(`unparseable frontmatter line ${index + 1}: ${line}`)
    }
    fields[match[1]] = unquote(match[2].trim())
  }

  const body = lines.slice(closingIndex + 1)
  while (body.length > 0 && body[body.length - 1].trim() === '') {
    body.pop()
  }

  return { fields, bodyLineCount: body.length }
}

export function validateSkillFrontmatter(directoryName, text) {
  const errors = []
  const warnings = []

  let parsed
  try {
    parsed = parseFrontmatter(text)
  } catch (error) {
    return { errors: [error.message], warnings }
  }

  const { fields, bodyLineCount } = parsed
  const name = fields.name
  const description = fields.description

  if (!name) {
    errors.push('frontmatter is missing `name`')
  } else {
    if (name.length > MAX_NAME) {
      errors.push(`name is ${name.length} characters, the limit is ${MAX_NAME}`)
    }
    if (!NAME_PATTERN.test(name)) {
      errors.push(`name "${name}" must be lowercase letters, digits and single hyphens`)
    }
    for (const word of RESERVED_WORDS) {
      if (name.includes(word)) {
        errors.push(`name "${name}" contains the reserved word "${word}"`)
      }
    }
    if (name !== directoryName) {
      errors.push(`name "${name}" does not match directory name "${directoryName}"`)
    }
  }

  if (!description) {
    errors.push('frontmatter is missing `description`')
  } else {
    if (description.length > MAX_DESCRIPTION) {
      errors.push(`description is ${description.length} characters, the limit is ${MAX_DESCRIPTION}`)
    }
    if (/<[^>]+>/.test(description)) {
      errors.push('description must not contain XML or HTML tags')
    }
  }

  if (bodyLineCount > MAX_BODY_LINES) {
    warnings.push(`body is ${bodyLineCount} lines, the recommended maximum is ${MAX_BODY_LINES}`)
  }

  return { errors, warnings }
}

function hasCatalogRow(readmeLines, name) {
  return readmeLines.some((line) => line.trimStart().startsWith('|') && line.includes(`skills/${name}/SKILL.md`))
}

function hasRoutingBullet(readmeLines, name) {
  return readmeLines.some((line) => line.startsWith(`- \`${name}\` — `))
}

export function validateRepo(repoRoot) {
  const errors = []
  const warnings = []

  const skillsDir = join(repoRoot, 'skills')
  if (!existsSync(skillsDir)) {
    return { errors: ['skills/: directory is missing'], warnings, skills: [] }
  }

  const directoryNames = readdirSync(skillsDir, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => entry.name)
    .sort()

  const seenNames = new Set()
  for (const directoryName of directoryNames) {
    const skillPath = join(skillsDir, directoryName, 'SKILL.md')
    if (!existsSync(skillPath)) {
      errors.push(`skills/${directoryName}: SKILL.md is missing`)
      continue
    }
    const label = `skills/${directoryName}/SKILL.md`
    const result = validateSkillFrontmatter(directoryName, readFileSync(skillPath, 'utf8'))
    for (const message of result.errors) errors.push(`${label}: ${message}`)
    for (const message of result.warnings) warnings.push(`${label}: ${message}`)

    if (seenNames.has(directoryName)) {
      errors.push(`${label}: duplicate skill name "${directoryName}"`)
    }
    seenNames.add(directoryName)
  }

  const pluginPath = join(repoRoot, '.claude-plugin', 'plugin.json')
  if (!existsSync(pluginPath)) {
    errors.push('.claude-plugin/plugin.json: file is missing')
  } else {
    let plugin = null
    try {
      plugin = JSON.parse(readFileSync(pluginPath, 'utf8'))
    } catch (error) {
      errors.push(`.claude-plugin/plugin.json: invalid JSON (${error.message})`)
    }
    if (plugin !== null) {
      const declared = new Set(Array.isArray(plugin.skills) ? plugin.skills : [])
      const expected = new Set(directoryNames.map((name) => `./skills/${name}`))
      for (const path of expected) {
        if (!declared.has(path)) errors.push(`.claude-plugin/plugin.json: missing "${path}"`)
      }
      for (const path of declared) {
        if (!expected.has(path)) errors.push(`.claude-plugin/plugin.json: "${path}" does not exist under skills/`)
      }
    }
  }

  const readmePath = join(repoRoot, 'README.md')
  if (!existsSync(readmePath)) {
    errors.push('README.md: file is missing')
  } else {
    const readmeLines = readFileSync(readmePath, 'utf8').replace(/\r\n/g, '\n').split('\n')
    for (const name of directoryNames) {
      if (!hasCatalogRow(readmeLines, name)) {
        errors.push(`README.md: no catalog table row for "${name}"`)
      }
      if (!hasRoutingBullet(readmeLines, name)) {
        errors.push(`README.md: no Skills-block bullet for "${name}"`)
      }
    }
  }

  return { errors, warnings, skills: directoryNames }
}

const invokedDirectly = resolve(process.argv[1] ?? '') === fileURLToPath(import.meta.url)
if (invokedDirectly) {
  const repoRoot = join(fileURLToPath(new URL('.', import.meta.url)), '..')
  const { errors, warnings, skills } = validateRepo(repoRoot)

  for (const message of warnings) console.warn(`warning: ${message}`)
  for (const message of errors) console.error(message)

  if (errors.length > 0) {
    console.error(`\n${errors.length} problem(s) found.`)
    process.exit(1)
  }
  console.log(`OK — ${skills.length} skill(s) validated.`)
}

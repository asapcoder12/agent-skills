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

#!/usr/bin/env node
// Compatibility patch for upstream commit 528c682 -> d347e703:
// dsh-permission-presets records `origin` inside `permission/preset`, but the
// released v0->v1 migration shipped in the same build froze the payload as
// `{ preset }` only. Older v0 logs are therefore refused on load. This patch
// re-admits the optional official origin while validating its exact enum.
import { existsSync, promises as fs } from 'node:fs'
import { join } from 'node:path'

const target = process.argv[2]
if (!target) {
  console.error('usage: node patch-session-format-migration.mjs <runtime-backend-root>')
  process.exit(64)
}

const pkg = join(target, 'node_modules', '@deepseek-ai', 'dsh-session-format-v0-to-v1')
if (!existsSync(pkg)) {
  console.log('session-format migration package not present; compatibility patch skipped')
  process.exit(0)
}

const files = [
  join(pkg, 'src', 'dispositions.ts'),
  join(pkg, 'src', 'payload-validation.ts'),
  join(pkg, 'lib', 'index.js'),
  join(pkg, 'lib', 'types', 'dispositions.js'),
  join(pkg, 'lib', 'types', 'payload-validation.js'),
]

function fileKind(file) {
  if (file.endsWith(join('lib', 'index.js'))) return 'both'
  if (file.includes('dispositions')) return 'disposition'
  if (file.includes('payload-validation')) return 'validation'
  return 'both'
}

function dispositionReady(source) {
  return /disposition\(\[["']preset["']\],\s*\[["']origin["']\]\)/.test(source)
}

function validationReady(source) {
  return /data\[["']origin["']\]\s*!==\s*(void\s+0|undefined)/.test(source)
}

function patchDisposition(source) {
  const quote = source.includes('"permission/preset"') ? '"' : "'"
  const from = `${quote}permission/preset${quote}: disposition([${quote}preset${quote}])`
  const to = `${quote}permission/preset${quote}: disposition([${quote}preset${quote}], [${quote}origin${quote}])`
  return source.includes(from) ? source.replace(from, to) : source
}

function patchValidation(source) {
  const double = source.includes('case "permission/preset"')
  const quote = double ? '"' : "'"
  const from = `case ${quote}permission/preset${quote}:`
  const marker = `nonEmptyString(data[${quote}preset${quote}], \`\${label} preset\`)`
  const at = source.indexOf(from)
  if (at === -1) return source
  const after = source.indexOf(marker, at)
  if (after === -1) return source
  if (validationReady(source)) return source
  const lineEnd = source.indexOf('\n', after)
  if (lineEnd === -1) return source
  const insertion = `\n      if (data[${quote}origin${quote}] !== void 0) literalValue(data[${quote}origin${quote}], [${quote}default${quote}, ${quote}selection${quote}, ${quote}inferred${quote}], \`\${label} origin\`)`
  return `${source.slice(0, lineEnd)}${insertion}${source.slice(lineEnd)}`
}

let changed = 0
for (const file of files) {
  let source
  try {
    source = await fs.readFile(file, 'utf8')
  } catch {
    continue
  }
  const next = patchValidation(patchDisposition(source))
  if (next !== source) {
    await fs.writeFile(file, next)
    changed += 1
  }
}

let relevant = 0
let ready = 0
const missing = []
for (const file of files) {
  let source
  try {
    source = await fs.readFile(file, 'utf8')
  } catch {
    continue
  }
  if (!source.includes('permission/preset')) continue
  relevant += 1
  const kind = fileKind(file)
  const isReady = kind === 'both'
    ? dispositionReady(source) && validationReady(source)
    : kind === 'disposition'
      ? dispositionReady(source)
      : validationReady(source)
  if (isReady) {
    ready += 1
  } else {
    missing.push(file)
  }
}

if (missing.length > 0) {
  console.error('session-format compatibility patch did not verify:')
  for (const file of missing) console.error(`  ${file}`)
  process.exit(1)
}

if (relevant === 0) {
  console.log('session-format migration has no released permission/preset inventory')
} else if (changed === 0) {
  console.log('session-format migration already compatible')
} else {
  console.log(`patched ${changed} session-format compatibility file(s) in ${pkg}`)
}

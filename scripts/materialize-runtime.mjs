import { cpSync, existsSync, lstatSync, mkdirSync, readFileSync, readdirSync, rmSync } from 'node:fs'
import { join, resolve } from 'node:path'

const root = resolve(import.meta.dirname, '..')
const [harnessArgument, backendArgument] = process.argv.slice(2)
const harness = harnessArgument === undefined
  ? join(root, 'upstream', 'deepseek-harness')
  : resolve(harnessArgument)
const backend = backendArgument === undefined
  ? join(root, 'glass', 'build', 'backend')
  : resolve(backendArgument)
const nodeModules = join(backend, 'node_modules')

const workspaceRoots = [
  join(harness, 'vendor'),
  join(harness, 'packages'),
]

const packageByName = new Map()
for (const workspaceRoot of workspaceRoots) {
  for (const path of walk(workspaceRoot)) {
    if (!path.endsWith('/package.json')) continue
    const manifest = readJson(path)
    if (typeof manifest.name !== 'string') continue
    packageByName.set(manifest.name, { dir: join(path, '..'), manifest })
  }
}
const cliManifestPath = join(harness, 'apps', 'cli', 'package.json')
packageByName.set('@deepseek-ai/dsh', {
  dir: join(cliManifestPath, '..'),
  manifest: readJson(cliManifestPath),
})

const roots = ['@deepseek-ai/dsh']
const closure = new Set()
const queue = [...roots]
for (let index = 0; index < queue.length; index += 1) {
  const name = queue[index]
  if (closure.has(name)) continue
  closure.add(name)
  const packageInfo = packageByName.get(name)
  if (packageInfo === undefined) continue
  const manifest = packageInfo.manifest
  const dependencies = {
    ...manifest.dependencies,
    ...manifest.optionalDependencies,
    ...manifest.peerDependencies,
  }
  for (const dependency of Object.keys(dependencies)) {
    if (packageByName.has(dependency) && !closure.has(dependency)) queue.push(dependency)
  }
}

for (const name of closure) {
  const packageInfo = packageByName.get(name)
  if (packageInfo === undefined) continue
  const destination = join(nodeModules, name)
  rmSync(destination, { recursive: true, force: true })
  mkdirSync(join(destination, '..'), { recursive: true })
  cpSync(packageInfo.dir, destination, {
    recursive: true,
    dereference: true,
    filter: (source) => {
      const relative = source.slice(packageInfo.dir.length + 1)
      return relative !== 'node_modules'
        && !relative.startsWith('node_modules/')
        && relative !== '.git'
        && !relative.startsWith('.git/')
    },
  })
}

// The hoisted deploy has already copied every external production dependency
// to the root. Its `.pnpm` virtual store and `.bin` shims are build-time
// implementation details; dropping them keeps the App relocatable and avoids
// checkout/store symlinks. App PATH supplies the fixed bundled pnpm instead.
rmSync(join(nodeModules, '.pnpm'), { recursive: true, force: true })
rmSync(join(nodeModules, '.bin'), { recursive: true, force: true })

const remainingSymlinks = [...walk(nodeModules, { includeDirectories: false })].filter(isSymlink)
if (remainingSymlinks.length > 0) {
  throw new Error(`runtime materialization left symlinks:\n${remainingSymlinks.join('\n')}`)
}

console.log(`materialized ${closure.size} official workspace packages into ${nodeModules}`)

function walk(directory, options = {}) {
  const results = []
  if (!existsSync(directory)) return results
  for (const entry of readdirSync(directory, { withFileTypes: true })) {
    const path = join(directory, entry.name)
    if (entry.isSymbolicLink()) {
      if (options.includeDirectories === false) results.push(path)
      continue
    }
    if (entry.isDirectory()) {
      if (options.includeDirectories === true) results.push(path)
      results.push(...walk(path, options))
    } else {
      results.push(path)
    }
  }
  return results
}

function readJson(path) {
  return JSON.parse(readFileSync(path, 'utf8'))
}

function isSymlink(path) {
  try {
    return lstatSync(path).isSymbolicLink()
  } catch {
    return false
  }
}

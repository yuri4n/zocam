// agent: claude — whole module. Use it as a black box.
// The pure core of code-reference resolution: turn a reference such as
// "Zocam.Span.t()", "Point.compose/2", "ground/3", or "lib/zocam/point.ex"
// into a link target.
//
// agent: claude — changed: this used to be one module bound to the real
// manifest (`~/assets/api-manifest.json`), which no test could import
// outside Nuxt. It is now a FACTORY: createApiLinks(modules, site) closes
// over the data and returns the resolvers. The pattern is dependency
// injection: the shell (api-refs.ts) injects the real manifest; the tests
// (scripts/api-links.test.mts) inject a fixture.
//
//       api-refs.ts (shell)                    api-links.ts (this file)
//       manifest + site identity  ──inject──▶  createApiLinks(...)
//                                                ├ resolveApiRef
//                                                ├ resolvePathRef
//                                                ├ findRefRanges
//                                                └ linkifyCodeElement
//
// The resolution ladder, in order. The order is part of the design:
//
//   1. Another project's package (site.packageDocs). The boundary is
//      structural: a name under a foreign root belongs to that project BY
//      RULE, so a stale row in our generated manifest can never claim it.
//   2. Our own modules: the exact name, then an Elixir-style alias — the
//      tail segments of a module chain ("Point" for "Zocam.Point").
//   3. The Elixir stdlib. It comes AFTER our modules, because an alias
//      shadows a stdlib root exactly as `alias` does in Elixir source.
//   4. A bare entry ("ground/3"): the current page's module first, then
//      the one module that owns the name — if exactly one does.
//   5. A repository path ("lib/zocam/point.ex") → GitHub.

export type ApiModule = {
  slug: string
  types: Record<string, string>
  functions: Record<string, string>
}
export type ApiModules = Record<string, ApiModule>

// Where another project publishes its reference. 'hexdocs' is the format
// of hexdocs.pm ("Zocam.Span.html#of/1"); 'site' is the format of a docs
// site like this one ("/api/zocam-span#of").
export type PackageDocs = { style: 'hexdocs' | 'site'; base: string }

export type SiteOptions = {
  /** The GitHub repository ("owner/name") that owns a repository path. */
  repoFor: (path: string) => string
  /** Foreign module roots and where their docs live: { Zocam: {…} }. */
  packageDocs?: Record<string, PackageDocs>
}

export type Range = { start: number; end: number; href: string }

// "Zocam.Intervals" → "zocam-intervals", the ingest script's page slug.
export function moduleSlug(moduleName: string): string {
  return moduleName.toLowerCase().replaceAll('.', '-')
}

// A qualified reference: a module chain, then an optional entry with an
// optional "()" or "/arity" suffix. Example: Zocam.Span.of/1
const QUALIFIED = /^([A-Z][A-Za-z0-9_]*(?:\.[A-Z][A-Za-z0-9_]*)*)(?:\.([a-z_][A-Za-z0-9_]*[!?]?)(\(\)|\/\d+)?)?$/
// A bare entry reference. The suffix is required; a bare word would
// over-match prose.
const LOCAL = /^([a-z_][A-Za-z0-9_]*[!?]?)(\(\)|\/\d+)$/

// The fence scanners: the same three shapes, found inside running text.
const QUAL_SCAN = /[A-Z][A-Za-z0-9_]*(?:\.[A-Z][A-Za-z0-9_]*)*(?:\.([a-z_][A-Za-z0-9_]*[!?]?)(\(\)|\/\d+)?)?/g
const LOCAL_SCAN = /(?:^|[^.\w:%])([a-z_][A-Za-z0-9_]*[!?]?)(\(\)|\/\d+)/g
const PATH_SCAN = /(?:^|[^\w./-])((?:[\w.-]+\/)+[\w.{}*,-]+\/?)/g

// The Elixir standard library. A member reference ("Enum.map/2") links to
// hexdocs.pm/elixir. A BARE root ("Task") stays plain text: many stdlib
// roots are ordinary English words, and the tail of a project alias is
// often one of them (`alias S7r.Task` — then "Task" means the project's
// module, not Elixir's). A bare foreign-package root DOES link (see
// packageUrl): a package root is an owned name that nothing else carries.
const STDLIB_ROOTS = new Set([
  'Access', 'Agent', 'Application', 'Atom', 'Base', 'Bitwise', 'Calendar',
  'Code', 'Config', 'Date', 'DateTime', 'Duration', 'DynamicSupervisor',
  'Enum', 'Exception', 'File', 'Float', 'Function', 'GenServer', 'IO',
  'Inspect', 'Integer', 'Kernel', 'Keyword', 'List', 'Macro', 'Map',
  'MapSet', 'Module', 'NaiveDateTime', 'Node', 'OptionParser', 'Path',
  'Port', 'Process', 'Protocol', 'Range', 'Record', 'Regex', 'Registry',
  'Stream', 'String', 'StringIO', 'Supervisor', 'System', 'Task', 'Time',
  'Tuple', 'URI', 'Version',
])

// Repository paths. The first segment must be a known top folder, so that
// prose such as "and/or" never becomes a link.
const PATH_TOP = new Set(['lib', 'docs', 'test', 'config', 'priv', 'scripts', '.github'])
const ROOT_FILES = /^(mix\.exs|mix\.lock|README\.md|AGENTS\.md|CHANGELOG\.md|LICENSE|mise\.toml)$/

// Inline chips sometimes hold a struct literal: %Zocam.Point{…}. The
// module name inside it is still a valid reference, so we cut it out.
function normalize(text: string): string {
  let t = text.trim()
  if (t.startsWith('%')) t = t.slice(1)
  const brace = t.indexOf('{')
  if (brace >= 0) t = t.slice(0, brace)
  return t
}

/** Build the resolvers for one site: its manifest plus its identity. */
export function createApiLinks(allModules: ApiModules, site: SiteOptions) {
  const packageDocs = site.packageDocs ?? {}

  // The boundary is enforced HERE, at construction: a manifest row under a
  // foreign package root is stale generated data (the ingest no longer
  // writes it), and keeping it would leak local links to pages this site
  // does not build. Foreign roots contribute nothing — not a page, not an
  // alias, not an owner.
  const modules: ApiModules = Object.fromEntries(
    Object.entries(allModules).filter(([name]) => !packageDocs[name.split('.')[0]!]),
  )
  const bySlug = new Map(Object.values(modules).map((m) => [m.slug, m]))

  // The alias index: every proper dotted tail of a module name points to
  // it — "Point" and "Point.ComposeError" for "Zocam.Point.ComposeError".
  // A tail that two modules share is ambiguous; null marks it dead.
  const aliases = new Map<string, string | null>()
  for (const name of Object.keys(modules)) {
    const parts = name.split('.')
    for (let i = 1; i < parts.length; i++) {
      const tail = parts.slice(i).join('.')
      aliases.set(tail, aliases.has(tail) ? null : name)
    }
  }

  // The owner index: an entry name maps to the ONE module that has it.
  // A name that many modules have (t, new!) is ambiguous; null marks it.
  const owners = new Map<string, ApiModule | null>()
  for (const mod of Object.values(modules)) {
    for (const name of [...Object.keys(mod.types), ...Object.keys(mod.functions)]) {
      const prev = owners.get(name)
      if (prev === undefined) owners.set(name, mod)
      else if (prev !== mod) owners.set(name, null)
    }
  }

  function findModule(ref: string): ApiModule | null {
    if (modules[ref]) return modules[ref]!
    const target = aliases.get(ref)
    return target ? modules[target]! : null
  }

  // "name()" reads as a type, "name/2" and bare ".name" read as a
  // function. When the preferred kind is absent, the other kind still
  // answers: the reader lands on the right page either way.
  function anchorFor(mod: ApiModule, name: string, prefer: 'type' | 'function'): string | null {
    const first = prefer === 'type' ? mod.types[name] : mod.functions[name]
    const second = prefer === 'type' ? mod.functions[name] : mod.types[name]
    return first ?? second ?? null
  }

  // A module under a foreign package root (site.packageDocs) links to that
  // project's published reference. Anchors differ by style:
  //   hexdocs  functions "#name/arity", types "#t:name/arity"
  //   site     "#name" without punctuation — an APPROXIMATION of the
  //            heading slug; a punctuated duplicate ("compose!" next to
  //            "compose") lands on the first of the pair. Only the owning
  //            site knows its exact ids, and this stays inside the
  //            repository boundary instead of reading them across it.
  function packageUrl(mod: string, fun?: string, suffix?: string): string | null {
    const docs = packageDocs[mod.split('.')[0]!]
    if (!docs) return null
    if (docs.style === 'hexdocs') {
      const page = `${docs.base}/${mod}.html`
      if (!fun) return page
      if (suffix === '()') return `${page}#t:${fun}/0`
      if (suffix?.startsWith('/')) return `${page}#${fun}${suffix}`
      return page
    }
    const page = `${docs.base}/api/${moduleSlug(mod)}`
    return fun ? `${page}#${fun.replace(/[!?]$/, '')}` : page
  }

  function stdlibUrl(mod: string, fun?: string, suffix?: string): string | null {
    if (!STDLIB_ROOTS.has(mod.split('.')[0]!)) return null
    if (!fun && !mod.includes('.')) return null
    const page = `https://hexdocs.pm/elixir/${mod}.html`
    if (!fun) return page
    if (suffix === '()') return `${page}#t:${fun}/0`
    if (suffix?.startsWith('/')) return `${page}#${fun}${suffix}`
    return page
  }

  function resolvePathRef(text: string): string | null {
    const trimmed = text.trim()
    const t = trimmed.replace(/\/$/, '')
    if (ROOT_FILES.test(t)) return `https://github.com/${site.repoFor(t)}/blob/main/${t}`
    // "lib/" — one segment with a closing slash is the folder itself.
    if (/^[\w.-]+\/$/.test(trimmed)) {
      return PATH_TOP.has(t) ? `https://github.com/${site.repoFor(t)}/tree/main/${t}` : null
    }
    if (!/^[\w.-]+(\/[\w.{}*,-]+)+$/.test(t)) return null
    let segments = t.split('/')
    // "/3" is an arity, not a folder; numeric segments mean "not a path".
    if (segments.some((s) => /^\d+$/.test(s))) return null
    if (!PATH_TOP.has(segments[0]!)) return null
    let kind = /\.[a-z]+$/i.test(segments[segments.length - 1]!) ? 'blob' : 'tree'
    // A glob ("docs/adr-*.md") links to the folder that holds the matches.
    const glob = segments.findIndex((s) => /[*{]/.test(s))
    if (glob === 0) return null
    if (glob > 0) {
      segments = segments.slice(0, glob)
      kind = 'tree'
    }
    return `https://github.com/${site.repoFor(t)}/${kind}/main/${segments.join('/')}`
  }

  /** The target for one reference, or null when it names nothing we know. */
  function resolveApiRef(text: string, currentPath: string): string | null {
    const t = normalize(text)
    const q = t.match(QUALIFIED)

    // 1. A foreign package owns its root by rule; generated data can
    //    never claim the name back (a stale manifest row would 404).
    if (q) {
      const pkg = packageUrl(q[1]!, q[2], q[3])
      if (pkg) return pkg
    }

    // 2. Our own modules: exact name, then alias.
    const mod = q ? findModule(q[1]!) : null
    if (q && mod) {
      const page = `/api/${mod.slug}`
      if (!q[2]) return page === currentPath ? null : page
      const anchor = anchorFor(mod, q[2], q[3] === '()' ? 'type' : 'function')
      if (anchor) return page === currentPath ? `#${anchor}` : `${page}#${anchor}`
      // The module knows no such entry. Behind an ALIAS that can mean the
      // alias guessed wrong — "Task.async/1" resolves to S7r.Task, but the
      // author meant Elixir's Task. Give the stdlib the member before we
      // settle for the module page.
      const viaAlias = !modules[q[1]!]
      const std = viaAlias ? stdlibUrl(q[1]!, q[2], q[3]) : null
      if (std) return std
      return page === currentPath ? null : page
    }

    // 3. The stdlib, shadowed by our aliases (see the ladder above).
    if (q) {
      const std = stdlibUrl(q[1]!, q[2], q[3])
      if (std) return std
    }

    // 4. A bare entry: the current page's module, then the single owner.
    const local = t.match(LOCAL)
    if (local) {
      const prefer = local[2] === '()' ? 'type' : 'function'
      const slug = currentPath.match(/^\/api\/([\w-]+)$/)?.[1]
      const page = slug ? bySlug.get(slug) : undefined
      if (page) {
        const anchor = anchorFor(page, local[1]!, prefer)
        if (anchor) return `#${anchor}`
      }
      const owner = owners.get(local[1]!)
      if (owner && owner !== page) {
        const anchor = anchorFor(owner, local[1]!, prefer)
        if (anchor) return `/api/${owner.slug}#${anchor}`
      }
    }

    // 5. A repository path.
    return resolvePathRef(t)
  }

  /** Find every linkable reference range inside the joined fence text. */
  function findRefRanges(text: string, currentPath: string): Range[] {
    const ranges: Range[] = []
    const overlaps = (s: number, e: number) => ranges.some((r) => s < r.end && e > r.start)

    for (const m of text.matchAll(QUAL_SCAN)) {
      // The char before the match must not extend an identifier ("~T[…]").
      const before = text[m.index - 1]
      if (before && /[\w.]/.test(before)) continue
      const suffix = (m[1] ? '.' + m[1] : '') + (m[2] ?? '')
      const moduleName = suffix ? m[0].slice(0, -suffix.length) : m[0]
      const href = resolveApiRef(m[0], currentPath) ?? resolveApiRef(moduleName, currentPath)
      if (!href) continue
      ranges.push({ start: m.index, end: m.index + m[0].length, href })
    }
    for (const m of text.matchAll(LOCAL_SCAN)) {
      const start = m.index + m[0].length - m[1]!.length - m[2]!.length
      const end = m.index + m[0].length
      if (overlaps(start, end)) continue
      const href = resolveApiRef(m[1]! + m[2]!, currentPath)
      if (href) ranges.push({ start, end, href })
    }
    for (const m of text.matchAll(PATH_SCAN)) {
      const start = m.index + m[0].length - m[1]!.length
      const end = m.index + m[0].length
      if (overlaps(start, end)) continue
      const href = resolvePathRef(m[1]!)
      if (href) ranges.push({ start, end, href })
    }
    return ranges
  }

  /**
   * Wrap every known reference inside a rendered <code> element in a link.
   * Client-only: call it after the fence is in the DOM. `navigate` receives
   * the target route, so clicks stay inside the SPA router.
   */
  function linkifyCodeElement(
    codeEl: HTMLElement,
    currentPath: string,
    navigate: (to: string) => void,
  ): void {
    if (codeEl.closest('a')) return

    // One pass to map every text node to its offset in the joined string.
    const nodes: { node: Text; start: number }[] = []
    let text = ''
    const walker = document.createTreeWalker(codeEl, NodeFilter.SHOW_TEXT)
    for (let n = walker.nextNode(); n; n = walker.nextNode()) {
      nodes.push({ node: n as Text, start: text.length })
      text += n.textContent ?? ''
    }

    // Wrap back-to-front: splitting a text node keeps its head in place, so
    // earlier offsets stay valid while we mutate the tail of the document.
    const ranges = findRefRanges(text, currentPath).sort((a, b) => b.start - a.start)
    for (const range of ranges) {
      for (let i = nodes.length - 1; i >= 0; i--) {
        const { node, start } = nodes[i]!
        const len = node.textContent?.length ?? 0
        const from = Math.max(0, range.start - start)
        const to = Math.min(len, range.end - start)
        if (from >= to) continue
        if (node.parentElement?.closest('a')) continue
        if (to < len) node.splitText(to)
        const piece = from > 0 ? node.splitText(from) : node
        if (piece !== node) nodes.splice(i + 1, 0, { node: piece, start: start + from })
        const a = document.createElement('a')
        a.href = range.href
        a.className = 'code-ref'
        if (range.href.startsWith('http')) {
          // External target (GitHub, hexdocs): a plain link in a new tab.
          a.target = '_blank'
          a.rel = 'noopener'
        } else {
          a.addEventListener('click', (e) => {
            if (e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return
            e.preventDefault()
            navigate(range.href)
          })
        }
        piece.parentNode?.insertBefore(a, piece)
        a.appendChild(piece)
      }
    }
  }

  return { resolveApiRef, resolvePathRef, findRefRanges, linkifyCodeElement }
}

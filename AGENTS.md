<!-- agent: claude — file created 2026-08-05 at the user's request, as the
     zocam half of the paired agent files (see "Paired agent files"). -->

# Agents

These instructions are for AI agents that work in this repository. They use ASD-STE100 (Simplified Technical English). Keep that style when you edit this file.

<!-- agent: claude — section added 2026-08-05 at the user's request. -->

## Origin

The vision for zocam is mine. Its design uses concepts that I learned while I explored ideas together with an AI agent. I set the direction; the agent helps me to build and to learn.

## Communication

- My requests are often not precise. When I say "I would like to make X", read it as the start of a discussion. First, help me make the goal clear. Then show the possible implementations and their caveats.
- Write all prose in simple ASD-STE100: reports, code comments, docstrings, and documentation pages. Write to teach, because I want to learn.
- I understand visual explanations better than text. Use diagrams when they show a flow or a structure better than words (see "Diagrams").
- My goal is to learn as much as possible. Explain as such.

## Examples

This rule is strongest here in zocam: a library teaches through its examples.

- Use many examples in the docs and in the docstrings. Show each public function with at least one example that the reader can run.
- In docstrings, write the examples as doctests (`iex>` lines). The test suite then proves that each example stays true.
- Show the surprising cases, not only the happy path: wraps (`Nov..Feb`), overflow (`the 31st` in February), DST folds and gaps. An example of an edge teaches more than a paragraph.
- This is a paired rule (see "Paired agent files"); the s7r file carries the same rule.

## No users

The project has no users. No other person and no other code depends on it.

- Make a breaking change when it gives a better design. Do not add a deprecation path, a compatibility shim, or a migration guide unless I ask.
- Rename, move, and delete freely. A better name is worth the diff.
- Delete an ADR when its decision is dead. Do not keep a dead ADR "for the history".
- **An ADR is mutable here.** The usual rule says a record is immutable, and that a new decision must supersede an old one. That rule protects a team that reads the old record. This project has one developer and is at an early stage, thus the rule costs more than it gives. Edit an ADR in place, renumber it, split it, or delete it. Do not add a "Superseded by" chain.
- Publication on Hex does not change this rule. Publication makes the code available; it does not make users.

## Two separate repositories

zocam (this repository, the time library) and s7r (the application) are two repositories. Keep them apart.

- The two projects touch at one point only: s7r declares zocam as a dependency. Nothing else crosses the boundary.
- No script, build step, or page in one repository can read a file in the other. If a tool needs a path that starts with `../`, the design is wrong.
- Each repository documents itself. Do not copy a page from one site to the other. Link to it.
- <!-- agent: claude — added 2026-08-05. --> **This site's dev server holds port 4311** (`docs/nuxt.config.ts`, `devServer.port`). Do not remove it and do not let Nuxt pick the port.

  The reason is on the other side of the boundary. s7r depends on zocam in two modes: it compiles the Hex release, or it compiles a checkout on disk. Its documentation follows the same switch, because a link must agree with the build that shows it. In the second mode every `Zocam.*` chip on s7r's site points at **this** server, and s7r must know the address before either server starts. A moving port is a broken link.

  s7r holds 4311 as its fallback. The two numbers must agree, and nothing can enforce it: checking would mean reading a file in the other repository. If this port must change, change both in the same session.
- Each repository numbers its ADRs from 001. The two series are independent.
- A decision that touches both projects becomes two ADRs, one in each repository. Each ADR records its own side only.
- If both sites need the same machinery (the Mermaid component, the ingest script, the AI SLOP chip), make it a package that both depend on. Do not copy the file, and do not read it across the boundary.

### Paired agent files

Each repository keeps its own AGENTS.md. The two files are a pair:

- When one repository learns a rule that also applies to the other, update both files in the same session. Write each side in its own file, in its own words.
- Facts that belong to one repository only (its skin, its release steps, its structure) stay in that repository's file.
- Each file stays complete on its own. A reader of one repository must not need the other file.

### Where the documentation lives

zocam keeps its pages under `docs/content/`:

- `docs/content/2.design/adrs/NNN-slug.md` — one architecture decision record. The number is the sort key. The directory already says "adr", thus the filename does not repeat it. The `2.` prefix orders the section in the sidebar and does not show in the URL.
- **The files are the pages.** No script generates an ADR page, and no script copies one.
- Because a page holds Nuxt frontmatter and MDC syntax, an ADR is website content only. ExDoc publishes the API reference; it does not publish the ADRs. This keeps one record in one place.

## Ask me first

Ask me before you:

- Redesign the API, the code structure, or the overall plan for the code.
- Commit to a distributed-system design (see "Elixir").
- Create integration tests.
- Apply changes to the README or to other documentation pages. Propose the changes first, at the end of your other work.

## Workflow

- Write code test-first (TDD).
- Do not run tests while design questions are open. Ask the questions first. A test run that comes before a decision can be wasted work.
- Update AGENTS with relevant info (and tag your changes as always).

## Where work is tracked

<!-- agent: claude — added 2026-08-05 at the user's request. -->

Open work lives in two places. The scope of the item decides which one, and
each item belongs to one place only.

- **Linear** holds the project management: the plans, the priorities, and
  the decisions that wait on the user. Use it for an epic, for work that
  crosses more than one module, and for anything a later session must find
  without reading this repository first. The zocam project in Linear is this
  library's board; the app keeps its own. A decision that touches both
  projects becomes one issue in each board, in the same way that it becomes
  one ADR in each repository (see "Two separate repositories").
- **`docs/TODO.md`** holds the small, local items: a note tied to one module
  or one page, which the person who opens that file can finish. Keep the
  list short and delete an entry when it ships or when it dies.

Two rules follow:

- **Keep both current while you work.** Move an issue when you finish the
  work it describes, and file a new one the moment you find new work — in
  Linear when it is a plan, in `docs/TODO.md` when it is local. Work that
  lives only in a chat report is lost work: the next session starts with an
  empty context and cannot read that report.
- **Promote an item when it outgrows its home.** A `docs/TODO.md` entry that
  turns out to need an ADR, or to touch several modules, becomes a Linear
  issue and leaves the file.

## Reports

When you finish code work, give me a report. The report must contain:

- A summary of the changes.
- Mermaid diagrams, if the code is more complex than usual.
- The next steps.
- Important remarks, trade-offs, and todos.

Keep the report compact. A full read must take 5 to 10 minutes. I will ask questions about the parts that are not clear.

## Code style

- Tag the code that you write. Use a comment.
  - Tag each function or each comparable unit.
  - Tag a whole module only if I will use it as a black box and will not modify it myself.
  - If you change code that I wrote, mark that you made a change.
- Add comments and docstrings to all code that is not fully obvious. Explain the code as a teacher does.
- Use abstractions and patterns, not ad-hoc designs. Do not write two definitions for things that are semantically the same. Name the pattern that you use (for example: "This is a proxy").
- Model data as a graph when a graph represents the data better than other structures.

## Diagrams

- In Markdown files, use Mermaid diagrams. Always set the `mermaid` language on the code block.
- In docstrings, use ASCII diagrams for complex or important flows.
- In chat replies, create a `.mmd` file (only in your memory), so I can see them in VSCode.
- On a public page, give a caption to each diagram (see "Attribution").

## Documentation

- Document each choice between two or more implementations or designs. For design choices, write an ADR.
- If you change the code structure, the functionality, or the commands that run the code, propose the matching README changes. Ask me before you apply them (see "Ask me first").
- Put dedicated documentation pages in `docs/content`. This directory becomes a website that uses Nuxt and Docus. Follow their proposed structure.
- Every time you go for one solution or another, make sure to document it in the code as well as in the docs.
- Each public page must show who made it (see "Attribution").

### Docs site skins

The two docs sites must not look the same. Each site has its own skin, defined in its `docs/app/app.css`:

- zocam (this repo, public, zocam.dev): "neon terminal". True black, neon green `#3ddc84`, round corners, soft glows. Type: Space Grotesk (headings), Inter (body), JetBrains Mono (code), IBM Plex Mono (Mermaid only).
- s7r (the application): "synthwave HUD". Violet black, neon magenta `#f050d0` with cyan `#22d3ee` counter-accents, sharp corners, scanlines, hard blinks. Type: Chakra Petch (headings), IBM Plex Sans (body), IBM Plex Mono (code).

When you touch one site, do not copy its rules to the other. Shared machinery (Mermaid zoom, captions, the AI SLOP chip, the section nav, the API link resolver) can share structure, but the colors, fonts, shapes, and motion must stay different.

Each site has its own animated SVG logo lockup in `docs/public/` (`logo-dark.svg`, `logo-light.svg`, `favicon.svg`), wired through `header.logo` in `app/app.config.ts`. zocam: an "orbit garden" (turning rings on a rounded tile). s7r: a synthwave sun over a grid on a sharp tile. Keep the marks as different as the skins.

## Attribution

These rules apply to text that other persons will read: the README, the pages in `docs/content`, and the website that comes from them. They do not apply to chat replies or to code comments (for code, see "Code style").

- Tell the reader that an AI agent made the content. Use the words "AI SLOP". This is on purpose. An honest joke is better than a notice that hides the truth.
- Tell the reader that a senior engineer gave the direction and did the review. Say also that the review is human. A human review has normal limits, thus errors can stay. Do not claim full verification.
- Show my GitHub profile: `https://github.com/yuri4n`. Keep it small and calm. One link on each page is sufficient. Do not put my name in the title, in a heading, or in more than one position on the same page. The page is about the work, not about me.

Use this notice, or a text with the same meaning:

```markdown
> **AI SLOP** — an AI agent wrote this page. [yuri4n](https://github.com/yuri4n), a senior
> engineer, gave the direction and did the review. The review is human, thus errors can stay.
```

### Level of the tag

- Put the notice at the highest level that is still true, and no lower. One notice for each page is usually correct.
- Use a lower level (a section) only if that part is different from the remainder of the page. An example is a page that a human wrote, with one section that an agent made.
- Do not put a tag on each bullet, on each paragraph, or on each list item. Too many tags make the text difficult to read and tell the reader nothing new.
- Keep the notice in the same position on all pages. Put it immediately after the page title.

### Figures

A figure is a Mermaid diagram, an image, a chart, or a table that the text refers to as a unit.

- Give a caption to each figure on a public page. Put the caption immediately below the figure.
- The caption must have three parts: the number or the name of the figure, one line that tells what the figure shows, and the note that AI made it.
- Example:

```markdown
_Figure 3 — How an arc becomes kernel intervals. AI generated, human reviewed._
```

## Releases

- zocam is a public library. To release it, push a tag `vX.Y.Z`. GitHub Actions runs the tests and publishes the package to Hex.pm and the docs to hexdocs.pm.
- The tag must equal the `version` in `mix.exs`. The workflow stops when the two do not match.
- The s7r application consumes the released package from Hex. In dev mode, s7r can point at this checkout from disk through its own configuration; zocam itself never reads s7r.
- <!-- agent: claude — added 2026-08-05 at the user's request. --> **Prefer CI to a one-off command.** Work reaches production through a pull request: open a PR, let CI check it, merge it. Do not deploy from a local console. When a pipeline and a console command can do the same job, use the pipeline.
- <!-- agent: claude — added 2026-08-05; replaces the earlier sentence that named the workflow as the deployer. --> **Two machines build the docs site, and only one publishes.**
  - `.github/workflows/docs.yml` is the **proof**. It runs `pnpm test` and `pnpm generate` on each pull request and on each push. It marks the pull request red; it never deploys.
  - **Vercel publishes.** Its GitHub integration watches this repository, builds from the `docs` root directory, and puts the result on the site. The project is `zocam-docs` (`prj_qXrBGHY34g5UkM4tgUcyXY2ShOow`).
  - The two must build the same thing, thus `docs/vercel.json` pins Vercel to the same `pnpm generate` and the same `NITRO_PRESET=vercel_static` that the workflow runs. Change one, change the other.
  - Neither machine has Elixir, thus `mix docs` cannot run there. The generated pages under `docs/content/3.api/` are **committed** for that reason. After a docstring change, run `mix docs` and `pnpm ingest` and commit the result, or the site shows the old reference.
  - The site counts page views with the `@vercel/analytics` Nuxt module (`docs/nuxt.config.ts`). The module is one half of the switch; the other half is the Web Analytics setting on the Vercel project. Both must be on.

  This is a paired rule (see "Paired agent files"); the s7r file carries the same rule with its own project id. The analytics line belongs to zocam only, because the s7r site is not public in the same way.

## Elixir

- Add type annotations to all code. Use the strictest types that you can.
- Use aliases and structs to decompose common types.
- Use TypedStruct and typed Ecto schemas, not the untyped versions.
- Use recursive data structures and algebraic data types where they fit.
- If a component must scale, design it as a distributed system. Use Elixir constructs such as GenServer, Supervisors, and all that machinery (use as granular as you can and create nice self-healing systems). Discuss the design with me first (see "Ask me first"). Keep the pure functions separate from the process layer, so that other code can use them alone.
- Keep the project ready to build documentation with ExDoc.

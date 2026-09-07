# Solopreneur Agent Template

A 12-agent "company" for Claude Code: a full software dev team plus the business departments around it. Drop it into any project.

---

## Install

**Per project** (agents scoped to one repo, checked into git):

```bash
cp -r solopreneur-agents/.claude your-project/
cd your-project && claude
```

**Global** (available in every project on your machine):

```bash
cp -r solopreneur-agents/.claude/agents/* ~/.claude/agents/
```

> If `~/.claude/agents/` did not exist before your session started, restart Claude Code once. A running session doesn't detect a newly created `agents` directory.

The subfolders (`engineering/`, `growth/`, …) are for your benefit only — Claude Code scans recursively and identifies agents by the `name` field, not the path.

---

## The org chart

| Agent | Dept | Model | Writes code? | Owns |
|---|---|---|---|---|
| `ceo` | Leadership | opus | No | What to build next, what to kill, trade-offs |
| `architect` | Engineering | opus | No | System design, data modeling, ADRs |
| `frontend-engineer` | Engineering | sonnet | Yes | Components, routing, state, styling, a11y |
| `backend-engineer` | Engineering | sonnet | Yes | APIs, business logic, auth, integrations |
| `database-engineer` | Engineering | sonnet | Yes | Schema, migrations, indexes, query perf |
| `qa-engineer` | Engineering | sonnet | Yes | Tests, edge cases, security review |
| `devops-engineer` | Engineering | sonnet | Yes | Build, CI/CD, deploy, env vars, monitoring |
| `product-manager` | Product | sonnet | No | Specs, scope, acceptance criteria |
| `designer` | Product | sonnet | No | UX flows, visual system, interface copy |
| `marketing` | Growth | sonnet | No | Positioning, landing copy, launch, SEO |
| `sales` | Growth | sonnet | No | Pricing, conversion, outreach, objections |
| `finance-legal` | Operations | sonnet | No | Unit economics, runway, ToS, privacy, licenses |

### You asked for lean — here's how to get there

These 8 are the core. Delete the other 4 if you want a tighter roster:

**Core 8:** `ceo` · `architect` · `frontend-engineer` · `backend-engineer` · `database-engineer` · `qa-engineer` · `devops-engineer` · `product-manager`

**Trim first:** `designer` (fold into `frontend-engineer`), `sales` (fold into `marketing`), `finance-legal` (only matters once you charge money), `marketing` (only matters once you launch).

Deleting an agent is just deleting its `.md` file. Adding one back is copying it in. Nothing else references them by name except the handoff hints inside each prompt.

---

## Using them

**Let Claude route automatically.** Every `description` starts with the trigger conditions, so Claude delegates on its own:

```
Add a "duplicate project" button to the project list
```

**Name one explicitly** when you want a specific perspective:

```
Use the architect subagent to design the notification system
Have qa-engineer review what I just wrote
```

**Guarantee it with @-mention** — type `@` and pick from the typeahead, or write it directly:

```
@agent-database-engineer add a soft-delete column to projects
```

**Run a whole session as one agent** when you're heads-down in one mode:

```bash
claude --agent frontend-engineer
```

### Chaining is where this earns its keep

```
Use product-manager to spec the invite flow, then architect to design it,
then have the engineers build it, then qa-engineer to review.
```

Each one runs in its own context window, so the spec discussion never crowds out the implementation.

---

## Cost notes

Subagents each carry their own context. A subagent-heavy session can burn several times the tokens of a single-threaded one — that's the trade you're making for a clean main context.

Two levers:

- `ceo` and `architect` are set to `opus` because they're judgment calls. Everything else is `sonnet`. Change the `model:` field freely.
- Force every subagent onto one model for a session: `CLAUDE_CODE_SUBAGENT_MODEL=claude-haiku-4-5 claude`

---

## Memory is on

Each agent has a `memory:` scope, so it accumulates knowledge across sessions:

- **`project`** → `.claude/agent-memory/<agent>/` — engineering agents, commit these
- **`user`** → `~/.claude/agent-memory/<agent>/` — `ceo`, `marketing`, `sales`, `finance-legal` (business context follows you between projects)

Get value out of it by asking directly:

```
Check your memory before reviewing this — have we hit this bug pattern before?
Save what you learned about the auth flow to your memory.
```

Remove the `memory:` line from any agent you'd rather keep stateless.

---

## Two things that will surprise you

**Subagents can't ask you questions.** The `AskUserQuestion` tool is stripped from every subagent. That's why `product-manager` and `designer` are instructed to pick a default, state it as an assumption, and flag it — instead of blocking. Expect assumptions in their output and correct them in one line.

**Background subagents get fewer tools.** Subagents usually run in the background, where the built-in toolset is reduced to essentials (Read, Grep, Glob, Bash, Edit, Write, WebFetch, WebSearch, and a few more). The agents here only use tools that survive that filter, so they work in either mode.

---

## Customizing

Each agent is a plain markdown file: YAML frontmatter on top, system prompt below. Edit freely.

Frontmatter fields worth knowing:

```yaml
name: backend-engineer      # required, lowercase-hyphens, no colons, must be unique
description: ...            # required — this is what drives auto-delegation
tools: Read, Write, Edit    # allowlist; omit to inherit everything
disallowedTools: Write      # denylist, applied before `tools`
model: sonnet               # sonnet | opus | haiku | fable | full ID | inherit
memory: project             # user | project | local
color: green                # display color in the task list
permissionMode: default     # default | acceptEdits | auto | dontAsk | plan
maxTurns: 20                # cap agentic turns
skills: [api-conventions]   # preload skill content at startup
```

**The `description` field is the highest-leverage thing to tune.** Claude reads it to decide when to delegate. Vague description, no delegation. If an agent isn't firing when you expect, rewrite its description with more concrete triggers before touching anything else.

Files are hot-reloaded within a few seconds — no restart needed for edits to existing agents.

---

## What's in the box

```
solopreneur-agents/
├── README.md                    ← you are here
├── CLAUDE.md.template           ← project context, rename to CLAUDE.md
├── docs/
│   └── WORKFLOWS.md             ← chaining recipes for common tasks
└── .claude/
    ├── settings.json.example    ← optional session defaults
    └── agents/
        ├── leadership/ceo.md
        ├── engineering/{architect,frontend-engineer,backend-engineer,
        │                database-engineer,qa-engineer,devops-engineer}.md
        ├── product/{product-manager,designer}.md
        ├── growth/{marketing,sales}.md
        └── operations/finance-legal.md
```

Reference: https://code.claude.com/docs/en/sub-agents

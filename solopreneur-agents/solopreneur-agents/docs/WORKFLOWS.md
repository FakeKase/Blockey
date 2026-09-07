# Workflow recipes

Copy-paste starting points. Each chains agents so no single context window carries the whole job.

---

## New feature, end to end

```
Use product-manager to spec <feature>, then architect to design it,
then the engineers to build it, then qa-engineer to review before I commit.
```

Expect the spec to contain stated assumptions — subagents can't ask you questions mid-task. Correct them in one line and continue.

---

## "Should I build this at all?"

```
Use the ceo subagent: I'm considering <thing>. Worth the next two weeks?
```

Returns a decision, the runner-up, and what you're explicitly giving up.

---

## Starting a project from zero

```
1. Use ceo to confirm the smallest v1 worth shipping
2. Use product-manager to write the v1 spec
3. Use architect to design the data model and pick the stack
4. Use database-engineer to build the schema
5. Use backend-engineer for the API
6. Use frontend-engineer for the UI
7. Use devops-engineer to get it deployed
8. Use qa-engineer before launch
```

Run these as separate turns, not one prompt. You want to read each output before the next agent builds on it.

---

## Bug, root cause unknown

```
Use qa-engineer to reproduce and locate the cause of <bug>,
then hand the fix to whichever engineer owns that layer.
```

---

## Before you merge anything

```
@agent-qa-engineer review my uncommitted changes
```

---

## Pre-launch

```
1. Use qa-engineer for a security and edge-case pass
2. Use devops-engineer to verify deploy, rollback, and error monitoring
3. Use finance-legal for terms, privacy policy, and dependency licenses
4. Use marketing for the landing page and launch post
5. Use sales for pricing tiers and the conversion path
```

---

## Pricing a product

```
Use finance-legal to model unit economics at <price>,
then sales to structure the tiers and write the pricing page.
```

`finance-legal` runs real arithmetic in Bash and returns three scenarios rather than one falsely-confident number.

---

## Parallel research

```
Research how the auth module, the billing module, and the notification module
work — use separate subagents in parallel.
```

Independent read-only investigations are the cheapest possible use of subagents.

---

## Two habits worth building

**Ask agents to consult memory before they start:**

```
Check your memory first — have we solved something like this before?
```

**Ask them to write to it after:**

```
Save what you learned about this codebase to your memory.
```

Over a few weeks this is what turns the roster from twelve prompts into twelve colleagues who know your project.

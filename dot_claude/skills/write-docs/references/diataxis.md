# Diátaxis Quadrant Rules

## Contents

1. [Tutorial](#tutorial)
2. [How-To Guide](#how-to-guide)
3. [Explanation](#explanation)
4. [Quadrant boundary rules](#quadrant-boundary-rules)

---

## Tutorial

### What a tutorial is

A tutorial is a **lesson**. The reader is a learner. You are the instructor. Your job is
to bring them safely through a concrete, working example — not to teach them every feature,
not to explain the underlying theory, not to prepare them for every future task. One lesson,
one outcome.

The learner does not yet know what questions to ask. They need a reliable guide. Every
decision in a tutorial removes a decision from the learner.

### What a tutorial is not

A tutorial is not a how-to guide with an introduction. The difference is who controls the
path. In a tutorial, the instructor controls the path. The learner follows. In a how-to,
the reader controls the path. The guide assists.

A tutorial is not a product tour. A product tour shows features. A tutorial builds
understanding through doing.

### Structure

```
Title:          Verb phrase describing what the learner will build/do
                "Build a webhook receiver in Node.js"
                NOT "Introduction to webhooks"

Introduction:   Three things only:
                1. What the learner will accomplish (concrete outcome)
                2. What they will learn by doing it
                3. Prerequisites (be specific — versions, assumed knowledge)

Steps:          Numbered. Each step:
                - Has a heading that states what happens ("Configure the database connection")
                - Includes the exact command or code to run
                - Shows the expected output
                - Explains what just happened (one sentence, past tense)

Conclusion:     What the learner built. What they can do next. Links to how-to guides
                for the tasks they'll need immediately.
```

### Rules

**Do** write every command in full. Never abbreviate.

**Do** show expected output after every command. The learner needs to know what success
looks like.

**Do** explain what just happened after each step — one sentence, past tense. This anchors
the action to meaning without becoming a lecture.

**Do** give the learner a working environment. If they need a sample repo, provide one.
If they need sample data, provide it. Do not make them source their own.

**Do not** explain how things work in depth. A brief aside ("We use HTTPS here because
it encrypts the request") is acceptable. A paragraph on TLS is not — link to an
explanation instead.

**Do not** offer alternatives or variations. "You could also use X" introduces decisions
the learner is not ready to make. Save alternatives for how-to guides.

**Do not** apologise for simplifications. "This is a simplified example — in production
you'd also want to..." undermines confidence. Trust the learner to grow.

**Do not** make steps dependent on unreachable prerequisites. If step 4 requires
something the learner hasn't set up, either add it to prerequisites or add it as a step.

### Good example — Tutorial step

```markdown
## Step 2 — Start the development server

Run the following command from your project root:

    npm run dev

You will see output similar to this:

    > myapp@1.0.0 dev
    > vite

      VITE v4.3.1  ready in 312 ms

      ➜  Local:   http://localhost:5173/
      ➜  Network: use --host to expose

Vite started a local HTTP server and is watching your files for changes.
Open http://localhost:5173/ in your browser before continuing.
```

**Why this works:** The step heading says what happens. The command is complete and
copy-pasteable. The expected output is shown verbatim. The closing sentence explains
what occurred and gives the next action.

### Bad example — Tutorial step

```markdown
## Development Server

You can start the dev server with npm. Vite is the underlying tool — it's fast because
it uses ES modules natively instead of bundling during development. You might also use
`vite --port 3000` if port 5173 is taken on your machine, or configure a different port
in `vite.config.js`. Once it's running, open localhost in your browser.
```

**Why this fails:**
- No command shown in full
- No expected output
- Offers alternatives ("you might also use...") — the learner isn't ready for this
- Explains the *why* of Vite's architecture — that belongs in an explanation doc
- The closing instruction is vague ("open localhost")

---

## How-To Guide

### What a how-to guide is

A how-to guide helps a **competent user accomplish a specific goal**. The reader already
understands the tool. They have a task. They need the fastest path to completing it.

You are not teaching. You are not explaining. You are guiding someone who knows where
they're going but wants efficient directions.

### What a how-to guide is not

A how-to guide is not a tutorial. The reader is not learning — they're working.

A how-to guide is not an explanation. You may include a single-sentence rationale for a
non-obvious step, but never a conceptual detour.

### Structure

```
Title:          "How to [accomplish specific goal]"
                "How to configure rate limiting with Redis"
                NOT "Rate limiting guide"

Introduction:   Two sentences maximum:
                1. What this guide does
                2. Prerequisites or assumed state (one line)

Steps:          Numbered. Each step:
                - Imperative verb heading ("Add the Redis connection string")
                - Command or code
                - One-line explanation only for non-obvious steps

Result:         One sentence confirming the task is complete.
                Optional: what to do if something went wrong (link to troubleshooting).
```

### Rules

**Do** use imperative mood throughout. "Run", "Open", "Add", "Set". Not "You should run"
or "The next thing to do is run".

**Do** include every command the reader needs. Do not say "install the dependencies"
without showing the exact command.

**Do** show file paths in full from the project root.

**Do** use code blocks for all commands, config values, and file contents.

**Do not** explain how the technology works. If a reader needs that, they should read
an explanation doc. Link to it; don't inline it.

**Do not** add background on why the tool was designed this way.

**Do not** start with "In this guide, we will explore...". State the goal, then do it.

**Do not** add a "Further reading" section that lists tangentially related docs. Link
directly to the next logical action only.

### Good example — How-To Guide introduction

```markdown
# How to Add Authentication to an Express API

This guide shows you how to add JWT-based authentication to an existing Express API
using the `express-jwt` middleware.

**Prerequisites:** An Express app with at least one protected route. Node.js 18+.
```

**Why this works:** Title is imperative. Introduction is two sentences. Prerequisites
are specific — versions are given, assumed state is clear. No scene-setting.

### Bad example — How-To Guide introduction

```markdown
# Authentication Guide

Authentication is a critical part of any web application. Before users can access
protected resources, we need to verify their identity. There are many approaches to
authentication — session-based, token-based, OAuth, and more. In this guide, we'll
focus on JWTs (JSON Web Tokens), which are a popular choice for stateless APIs because
they encode claims directly in the token rather than requiring server-side session
storage. We'll be using the express-jwt library.

Let's get started!
```

**Why this fails:**
- Title doesn't say what the reader will accomplish
- First four sentences are explanation — belongs in a separate doc
- "Let's get started!" is filler — it delays the reader
- The word "we'll" twice before a single step has been taken

### Good example — How-To Guide step

```markdown
## 3. Protect a route

Add the `requireAuth` middleware to any route you want to protect:

```javascript
app.get('/profile', requireAuth, (req, res) => {
  res.json({ user: req.auth });
});
```

Requests without a valid token now return `401 Unauthorized`.
```

**Why this works:** Imperative heading. Complete code. One-sentence confirmation of
the outcome. No explanation of JWT internals.

### Bad example — How-To Guide step

```markdown
## 3. Adding Route Protection

Now that we have our middleware set up, we need to think about which routes should be
protected. In most applications, you'll want to protect routes that return user-specific
data. The `requireAuth` middleware we created earlier will check the Authorization header
for a Bearer token. If the token is valid, it sets `req.auth` to the decoded payload —
which is why we can access `req.auth` in the route handler below. If not, express-jwt
will throw an error which we'll handle in the next step.

You can add it like this (but make sure you've completed step 2 first):

```javascript
app.get('/profile', requireAuth, (req, res) => {
  res.json({ user: req.auth });
});
```
```

**Why this fails:**
- Heading is passive ("Adding") not imperative
- First three sentences explain how JWT middleware works — belongs in explanation
- "which is why we can access" — conceptual explanation mid-step
- Parenthetical aside undermines trust ("make sure you've completed step 2 first" — the
  reader is following numbered steps; of course they have)

---

## Explanation

### What an explanation is

An explanation builds a **mental model**. The reader is studying, not working. They want
to understand why something is the way it is, how its parts relate, what the tradeoffs
are, what alternatives exist and why this one was chosen.

Explanation answers: *Why? How does this work? What are the tradeoffs? What should I
understand before I proceed?*

### What an explanation is not

An explanation is not a tutorial. It does not walk through steps.

An explanation is not a how-to. It does not help the reader accomplish a task right now.

An explanation does not need to be comprehensive. It needs to build the right mental
model for the reader's next action.

### Structure

```
Title:          Noun phrase or concept question
                "How the plugin resolution system works"
                "Why we use connection pooling"
                "Understanding event loop phases"

Introduction:   What this document explains and why understanding it matters.
                Two to four sentences.

Body:           Prose sections with descriptive headings.
                No numbered steps. No commands (unless illustrating a concept).
                Build concepts in order — each section assumes the previous.

Conclusion:     Optional. What the reader now understands. Where to go next
                (tutorial to apply it, how-to to use it).
```

### Rules

**Do** write in prose. Explanation is the one quadrant where flowing paragraphs are
correct. Bullet lists fragment concepts that need to be understood in relation to each
other.

**Do** explain tradeoffs honestly. "This approach is fast but uses more memory" is more
useful than a one-sided endorsement.

**Do** use analogies when they genuinely clarify. Drop them when they strain.

**Do** link to tutorials and how-to guides at the end — explanation without a path to
action leaves the reader floating.

**Do not** include step-by-step instructions. If you find yourself writing "First, run...",
you've drifted into how-to territory.

**Do not** write to be comprehensive. Write to build the model the reader needs right now.
An explanation that tries to cover everything teaches nothing.

**Do not** use hedging language: "it's worth noting that", "it's important to understand
that", "as you might expect". Say the thing directly.

**Do not** start sections with "In this section, we will discuss...". Start with the
concept itself.

### Good example — Explanation opening

```markdown
# How the Plugin Resolution System Works

When you call `app.use(plugin)`, the framework doesn't execute the plugin immediately.
It registers the plugin in a resolution graph and defers execution until all plugins have
been registered. This two-phase approach — register then resolve — is what makes circular
plugin dependencies possible without deadlocks.

The resolution graph is a directed acyclic graph (DAG). Each plugin is a node. Each
declared dependency is an edge. During resolution, the framework performs a topological
sort to determine execution order.
```

**Why this works:** Opens immediately with the concept, not a preamble. Explains the
*why* (two-phase approach enables circular dependency handling). Introduces the data
structure (DAG) because it's necessary for the mental model. No steps, no commands.

### Bad example — Explanation opening

```markdown
# Plugin System

Plugins are a core part of the framework. In this document, we'll explain how they work.
It's important to understand the plugin system before you start building your application.

To use a plugin, you first call `app.use()`. This adds the plugin to the system. Then
when your application starts, the plugins are executed. There are several types of
plugins: authentication plugins, database plugins, and utility plugins. Each type has
different behavior.
```

**Why this fails:**
- "It's important to understand" — hedging filler
- "In this document, we'll explain" — meta-commentary, not content
- Slides into how-to territory ("To use a plugin, you first call `app.use()`")
- The taxonomy at the end ("several types of plugins") is reference content, not
  explanation
- Nothing in these four sentences builds a mental model

---

## Quadrant Boundary Rules

These are the most common violations. Treat them as hard stops.

### Tutorial violations

| What you wrote | Why it's wrong | What to do |
|---|---|---|
| "You could also use X instead of Y" | Introduces a decision the learner can't make yet | Remove it, or add a link at the end |
| Two paragraphs on why TLS matters | Explanation content in a tutorial | Move to an explanation doc, add a one-line note + link |
| "In production, you should also..." | Out of scope for the tutorial's outcome | Remove, or write a separate how-to |
| Prerequisites buried in step 3 | Breaks the learner's trust | Move to the prerequisites section |

### How-to violations

| What you wrote | Why it's wrong | What to do |
|---|---|---|
| An opening paragraph on background | Delays the reader | Cut to two sentences or remove |
| "This works because JWT tokens are..." | Explanation in a how-to | One sentence max, link to explanation |
| Steps that assume context not in prerequisites | Reader will fail silently | Add to prerequisites or add a step |
| "You might want to also consider..." | The reader has a goal; don't distract them | Remove or link separately |

### Explanation violations

| What you wrote | Why it's wrong | What to do |
|---|---|---|
| Numbered steps in an explanation | Turns explanation into a how-to | Remove steps, describe the process in prose |
| "Run `npm install` to see this in action" | Action-oriented — belongs in how-to | Link to a how-to guide instead |
| A full API parameter list | Reference content | Move to reference documentation |
| "To summarise the above points:" + bullets | Bullet summary fragments the mental model | Write a concluding paragraph instead |

### When a request spans quadrants — what to say

State the problem clearly. Do not silently pick one quadrant and proceed.

> "This request mixes tutorial and explanation content. A tutorial walks through a
> specific worked example; an explanation builds a mental model of how the system works.
> Mixing them produces a document that does neither well.
>
> I'd suggest two separate documents:
> - **Explanation:** How the authentication system works (concepts, tradeoffs)
> - **Tutorial:** Build a login flow with the auth system (step-by-step, working example)
>
> Which do you want first?"

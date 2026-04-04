# Style and Register Rules

## Contents

1. [Reader model](#reader-model)
2. [Voice and tone](#voice-and-tone)
3. [Sentence and paragraph rules](#sentence-and-paragraph-rules)
4. [Formatting conventions](#formatting-conventions)
5. [Words to use and avoid](#words-to-use-and-avoid)
6. [Structure conventions](#structure-conventions)
7. [Common style violations](#common-style-violations)

---

## Reader model

The reader is a **competent developer under time pressure**. Model every writing decision
against this person.

They know what they're doing. They don't need concepts explained unless the concept is
genuinely non-obvious or specific to this system. They will not read a preamble. They
will not read a section that doesn't move them toward their goal.

**They will leave** if the document:
- Opens with three sentences before stating its purpose
- Explains things they already know
- Hedges, qualifies, or apologises
- Buries the command inside a paragraph
- Makes them hunt for the next step

**They will stay** if the document:
- States its purpose in the first sentence
- Gives them the exact command they need
- Shows what success looks like
- Respects that they can handle direct language

This is not a reader who needs encouragement. It is not a reader who needs tone
softened. It is a reader who needs precision and speed.

---

## Voice and tone

### Friendly but formal

The register is **friendly but formal** — the same register DigitalOcean uses in their
tutorials. This means:

- No jargon used for effect
- No emoji
- No jokes or memes
- No sarcasm
- No slang
- No exclamation points used for enthusiasm ("Let's get started!")

Friendly means: direct without being cold, confident without being dismissive, clear
without being condescending.

Formal means: no first person singular ("I think", "I'd suggest"). Use second person
("you will configure") or first person plural where genuinely collaborative ("we'll
look at three approaches").

### Outcome-focused language

Write toward what the reader will accomplish, not what the document will discuss.

**Correct:**
> In this tutorial, you will build a rate-limited API endpoint using Redis.

**Incorrect:**
> This tutorial covers rate limiting with Redis.

The first version puts the reader in the action. The second describes the document as
an object. Write the first way.

### No meta-commentary

Do not comment on the document from inside the document.

**Cut these phrases entirely:**
- "In this section, we will..."
- "As mentioned above..."
- "It's worth noting that..."
- "It's important to understand that..."
- "Before we continue..."
- "At this point, you should..."
- "Now that we've covered X, let's move on to Y"

These phrases add words and remove information. Replace them with the information itself.

---

## Sentence and paragraph rules

### Active voice

Use active voice. Subject performs the action.

| Passive (avoid) | Active (use) |
|---|---|
| "The configuration file is read by the server" | "The server reads the configuration file" |
| "An error will be thrown if the token is invalid" | "An invalid token throws a 401 error" |
| "The database connection should be closed" | "Close the database connection" |

Passive voice is acceptable when the actor genuinely doesn't matter or is unknown:
"The token is signed with HS256" is fine. "The configuration should be set" is not.

### Sentence length

Aim for sentences under 25 words. Long sentences slow scanning. When a sentence has
more than one clause, consider splitting it.

**Too long:**
> When the server starts, it reads the configuration file from the path specified in the
> `CONFIG_PATH` environment variable, and if that variable is not set, it falls back to
> `./config.json` in the current working directory.

**Better:**
> On startup, the server reads the configuration file from `CONFIG_PATH`. If that
> variable is not set, it falls back to `./config.json`.

### Paragraph length

Keep paragraphs to three to five sentences in explanation docs. In how-to guides and
tutorials, most "paragraphs" between steps are one to two sentences. A single sentence
between a heading and a code block is correct — do not pad it.

### Numbers

Write numbers one through nine as words. Use numerals for 10 and above, and always
for versions, ports, counts in technical context, and anything in code.

---

## Formatting conventions

### Headings

Use sentence case for all headings. Not title case.

**Correct:** `## Configure the database connection`
**Incorrect:** `## Configure the Database Connection`

How-to and tutorial step headings use imperative verbs:
`## Add the environment variable` not `## Adding the environment variable`

Explanation headings use noun phrases or concept questions:
`## How connection pooling works` not `## Connection pooling`

Never use a heading as the first line of a document. Write an introduction first.

### Code blocks

Use fenced code blocks (triple backtick) for all commands, code, config, and output.
Always include the language identifier.

```bash
npm install express-rate-limit
```

```javascript
const rateLimit = require('express-rate-limit');
```

```json
{
  "port": 3000,
  "rateLimit": 100
}
```

For shell output, use a plain block or label it `output`:

```output
Added 1 package in 0.8s
```

Do not put commands inside paragraphs unless referencing them by name. "Run
`npm install`" inline is acceptable when explaining what a step does. Giving the
actual command to run always gets a code block.

### Inline code

Use backtick inline code for:
- Command names: `npm`, `git`, `curl`
- File names: `config.json`, `.env`
- Environment variables: `DATABASE_URL`
- Function and method names: `app.use()`, `res.json()`
- Values that the reader will type or see exactly: `localhost:3000`, `200 OK`

Do not use inline code for:
- General technical terms: "the server", "the middleware", "the token"
- Product names: Express, Redis, Node.js (unless in code context)

### Callout blocks

Use callout blocks sparingly. One or two per document maximum. Use them only when
missing the information would cause the reader to fail or cause data loss.

**Note** — information that helps but isn't critical:
> **Note:** This setting only applies to the production environment.

**Warning** — information that, if missed, will cause failure or data loss:
> **Warning:** Running this command deletes all data in the database. Make a backup first.

Do not use callouts to repeat information already in the main text. If something
needs a callout, it belongs in the main text, not the callout.

### File paths

Always write file paths in full from the project root. Never use relative paths
without context.

**Correct:** `config/database.js`
**Incorrect:** `the config file` or `./database.js` (without establishing the working directory)

### Variables the reader must replace

Mark variables the reader must substitute in their own values. Use angle brackets in
code blocks:

```bash
export DATABASE_URL=<your-connection-string>
```

Define the variable immediately after the block:
> Replace `<your-connection-string>` with the connection string from your database
> provider's dashboard.

---

## Words to use and avoid

### Use

| Word/phrase | Notes |
|---|---|
| "you" | Direct address — keeps focus on the reader |
| "run" | For terminal commands |
| "open" | For files, URLs, tools |
| "add", "create", "set", "remove" | For config/code changes |
| "returns", "outputs", "prints" | For describing what code produces |
| "if X, then Y" | For conditional situations — direct and testable |

### Avoid

| Word/phrase | Why | Replace with |
|---|---|---|
| "simply", "just", "easily" | Condescending when the reader is stuck | Remove or rewrite |
| "of course", "obviously" | Condescending | Remove |
| "straightforward" | Rarely true for the reader in difficulty | Remove |
| "leverage" | Business jargon | "use" |
| "utilize" | Always weaker than "use" | "use" |
| "in order to" | Verbose | "to" |
| "please" | Overly deferential in instructions | Remove |
| "feel free to" | Padding | Remove |
| "Let's" (at section start) | Conversational filler | State the action directly |
| "Note that" | Weak callout | Use a proper Note block, or state directly |
| "It should be noted" | Passive hedge | Say the thing directly |
| "As we can see" | Implies shared experience | "The output shows" or just state it |

### Tense conventions

- **Tutorial steps:** Present or future: "The server starts on port 3000."
- **Post-step confirmations:** Past: "Vite compiled your project and started a dev server."
- **How-to steps:** Imperative: "Add the middleware before your route definitions."
- **Explanation:** Present: "The resolution graph is a DAG."

---

## Structure conventions

### Titles

Titles must say what the reader will accomplish or understand — not what the document
contains.

| Quadrant | Title pattern | Example |
|---|---|---|
| Tutorial | Verb phrase — what they will build | "Build a CLI tool with Commander.js" |
| How-To | "How to [accomplish goal]" | "How to Add Request Logging to Express" |
| Explanation | Noun phrase or concept question | "How the event loop handles I/O" |

**Titles to avoid:**

| Bad title | Why | Better |
|---|---|---|
| "Getting Started with Redis" | Vague — what will they do? | "Store Session Data with Redis" (tutorial) |
| "Authentication Overview" | Describes document type, not content | "How JWT Authentication Works" (explanation) |
| "Rate Limiting" | Noun only — no orientation | "How to Add Rate Limiting to an API" (how-to) |

### Introductions

Every document opens with an introduction, not a heading.

**Tutorial introduction — three elements:**
1. What the reader will build (concrete noun — "a webhook receiver", "a CLI tool")
2. What they will learn through building it
3. Prerequisites (specific versions, assumed knowledge)

Length: three to five sentences.

**How-to introduction — two elements:**
1. What this guide accomplishes (one sentence)
2. Prerequisites or assumed state

Length: one to three sentences. If you're writing more than three sentences, you're
explaining — move it to an explanation doc.

**Explanation introduction — two elements:**
1. What concept or system this explains
2. Why understanding it matters for the reader's work

Length: two to four sentences.

### Prerequisites

Tutorials and how-to guides require a prerequisites section. Place it after the
introduction, before step 1.

Be specific:

**Correct:**
```
## Prerequisites

- Node.js 18 or higher installed (`node --version` to check)
- An Express app with at least one route defined
- A Redis instance running locally or a connection string from a hosted provider
```

**Incorrect:**
```
## Prerequisites

- Basic knowledge of Node.js
- Express installed
- Redis
```

"Basic knowledge" is unmeasurable. "Express installed" is ambiguous — installed where?
"Redis" tells the reader nothing about what state it needs to be in.

---

## Common style violations

These are the patterns that appear most often in first drafts. Check for all of them
before finishing.

### 1. The motivational opener

```
❌  Authentication is a critical part of any web application. Without it, your users'
    data is at risk and your API is exposed to abuse.
```

The reader knows why authentication matters. They came here for the guide, not the
sales pitch. Cut to the task.

### 2. The false "we"

```
❌  In this tutorial, we'll explore how to configure Redis.
```

"We'll explore" is vague and evasive. You know exactly what you're going to do. Say it.

```
✓  In this tutorial, you will configure Redis as a session store for your Express app.
```

### 3. The buried command

```
❌  Once you've opened your terminal and navigated to your project directory, you'll
    want to install the required dependencies by running npm install express-rate-limit.
```

The command is inside a sentence. The reader has to parse the sentence to find it.
Put it in a code block.

```
✓  Install the dependency:

    npm install express-rate-limit
```

### 4. The defensive qualification

```
❌  Note: This is a simplified example. In a real production environment, you would
    also need to handle token refresh, implement proper error boundaries, add request
    logging, set up monitoring, and consider using a dedicated auth service.
```

This tells the reader their work is inadequate before they've done it. If these things
matter for the current task, add them as steps or link to a how-to. If they don't
matter for the current task, remove them entirely.

### 5. The passive instruction

```
❌  The environment variable should be set before the server is started.
```

Who sets it? When?

```
✓  Set `DATABASE_URL` before you start the server.
```

### 6. The unexplained magic command

```
❌  Run the following command:

    openssl rand -base64 32 | tr -d '\n' > .secret
```

One sentence on what this does — not how OpenSSL works, but what the command produces
and why it matters here:

```
✓  Generate a random secret key for signing tokens:

    openssl rand -base64 32 | tr -d '\n' > .secret

    This writes a 32-byte base64-encoded key to `.secret`. Keep this file out of
    version control.
```

### 7. The assumption that success is obvious

After a non-trivial step, always tell the reader what success looks like. Either show
expected output, describe the visible change, or state the condition that confirms the
step worked. A reader who doesn't know if they succeeded will not move forward
confidently.

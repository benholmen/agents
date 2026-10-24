---
description: Six reserved headings and one footer mark every message the user must act on; nothing else gets a heading
---

# Chat vocabulary

A run produces a lot of text, and little of it needs the user. This rule reserves six headings
and one footer for the text that does. The user reads the heading and knows what you want. A
message that carries neither a heading nor the footer needs no reply, so the user can read it
later.

Two facts from real runs set this rule. 448 of 1,303 user-role turns were automated worker
signals, which the user never typed. No marker anywhere meant "reply needed", so 13 questions
vanished under the next automated turn.

Declined: a `references/chat-vocabulary.md` adapter. A missing convention fails silently, and
`README.md` gives that as the test for a rule rather than a reference.

## Rule of thumb

**A reserved heading marks a message the user must act on. Nothing else carries one.**

Four of the six headings block and wait for a reply. `Landed` asks the user to read a milestone
result, and `Running` reports where the run is. Neither one stops the run.

The heading works only while it stays rare. One heading on a message that asks nothing teaches
the user to read every turn again.

## Default policy

- **Default:** Send no heading, and send no footer.
- **Cadence:** In an `/implement` run, speak on your own initiative on five occasions only.
- **The five occasions:** a gate, a wave join, a milestone landing, an escalation, and a failure.
- **Every other skill:** speak where the skill's own steps say to speak. A `/research` file report
  is one such message, and it carries no heading.
- **Global parts:** the six headings and the footer hold in every skill. The cadence above holds
  in `/implement` alone.
- **Fencing:** Fence every block that sits under a reserved heading.
- **Recommendation:** Every question that offers options carries one. An `Approve` proposal is its
  own; every other such question states one explicitly. A question offering none carries none.
- **Exceptions:** A direct reply to the user's own question needs no heading.

## The reserved vocabulary

```
**Approve — <topic>**     a gate. Nothing proceeds without a reply.
**Deciding — <topic>**    a question the user must answer, with or without options.
**Running — <milestone>** the wave state of a milestone that has not landed yet.
**Landed — <milestone>**  a milestone shipped. PR URLs, gates, ledger.
**Blocked — <what>**      work stopped and needs the user.
**Failed — <what>**       something broke that the orchestrator cannot resolve.
⏸ waiting on you: <x>     the last line of every message that waits.
```

Each heading carries exactly one meaning, and no heading carries a second. Nothing else in a run
gets a heading. `Approve`, `Deciding`, `Blocked`, and `Failed` each stop the run and wait for the
user. `Landed` reports a milestone and `Running` reports its waves, and the run continues.

**`Running` covers the whole milestone, not the wave that ended.** It names every wave, with the
state of each task. A block that covers one wave leaves the reader asking again ten minutes
later.

**The narration ban does not reach it.** That ban cites 78% of one run's assistant turns, and
that figure counted one message per worker. One milestone here ran five waves and ten workers, so
the block costs half the messages. It also answers a question no narration answered.

## Approve versus Deciding

Both stop the run, and the difference is what the user must do. `Approve` asks the user to
sanction a proposal you already formed. You state the proposal, and the user says yes or changes
it. `Deciding` asks the user to answer a question you cannot answer yourself.

**`Deciding` covers two shapes.** The first offers options. You state them and your recommendation,
and the user picks one. The second offers none, because you hold nothing to offer. A skill's first
question is commonly that shape: `What should I plan?` names no options, and inventing some would
be worse than asking.

Pick by that test alone, never by how large the question feels. A roster you assembled is an
`Approve`. A tradeoff only the user can settle is a `Deciding`, and so is an open prompt for
input.

**An `Approve` proposal is its own recommendation.** The message states one course and asks the
user to sanction it. You did the ranking work, and the user can read it. An `Approve` therefore
satisfies the mandatory recommendation without a separate line, and it may still carry one.

A `Deciding` message that offers options needs an explicit recommendation, because it presents
options you did not rank. So does a `Blocked` message that lists options. Neither one ranks
anything by itself, and both leave the user the work this rule removes. A `Deciding` that offers no
options carries no recommendation, because it holds nothing to rank.

## The footer

The footer is the last line of a message that waits for the user:

```
⏸ waiting on you: <the one thing you wait for>
```

Its presence is the signal, and its absence means nothing is outstanding. Name one thing, never
two. Add no bold sentinel beside it, because bold marks emphasis everywhere else in a message.

**Which messages carry the footer.** Every message that waits for the user carries it, whether or
not it carries a heading. `Approve`, `Deciding`, `Blocked`, and `Failed` therefore all carry it. So
does a question that carries no heading of its own.

**A question opens the gate it belongs to.** A skill's first question is that gate's opening
message. The questions after it are follow-ups inside the same open gate. `/implement` invoked with
no arguments asks which plan to run. That question opens a gate rather than standing outside one. So
"inside an open gate" covers a first question too, and no waiting message falls outside this rule.

**Which messages do not.** `Landed` and `Running` carry no footer, because the run continues. A
report, a narration, and a direct answer to the user's own question carry none. None of the three
waits, and waiting is the whole test. Whether a message carries a heading decides nothing here.

## Fence every blocking block

Fence every block that sits under a reserved heading. Unfenced, the roster gate reached a median
of 286 columns and the finding block 327. At that width the terminal wrapped both, and neither
read as a table any more. Real runs fenced the roster gate 5 times out of 13, and the
per-finding block 13 of 25.

A question that offers nothing to rank has no block, so it fences nothing.

## The taken glyphs stay taken

Each glyph below already carries one meaning. Never give one of them a second.

```
→   a call and what it returns
✓   a task committed
▶   a task running
⚠   a task escalated
⊘   a task blocked behind another
☐   an open work item
─   separates a repository from its evidence
·   separates a model from its effort
⏸   the footer, and nothing else
```

A reader who learns two meanings for one glyph trusts neither. Use a word rather than a new
glyph.

## The question shape

Every question takes this shape, and this rule states it once. A skill points here rather than
restating it.

1. The reserved heading, on the gate's opening message only: `Deciding` for a question you cannot
   answer yourself, `Approve` for a proposal. Each follow-up question inside that open gate carries
   no heading.
2. A fenced context block, carrying the three things below.
3. One short question, and a recommendation. The recommendation is mandatory. An `Approve`
   proposal is its own, so it needs no separate line.
4. The footer, as the last line of a prose question. A question the tool delivers needs
   none, because the tool blocks on its own.

**A question that offers nothing to rank drops part 2 and the recommendation.** It has no option to
cost and nothing to recommend. The heading, the question, and the footer are the whole message.
The first question of `/plan` and `/research` is that shape. `/implement`'s lists the active
plans, so it offers options and takes the full shape.

The context block carries what you found, why the user must choose, and the cost of each option:

```
found:      <what you found, and where>
decision:   <why this needs the user, rather than a lookup you can run>
<option A>  <what it costs, and what it forecloses>
<option B>  <what it costs, and what it forecloses>
```

Ask one question per message. Never batch two, because the user answers the first and the second
one disappears.

Real runs justify each part. 43 of 273 questions carried no recommendation, and two runs
recommended nothing at all. 78 of 273 arrived with no prose around them, and 12 calls batched
more than one question.

## Which surface carries a question

A heading names what a message is. It does not say how that message reaches the user, and this
rule now says both.

**A `Deciding` that offers options goes through the interactive question tool.** The tool renders
selectable options and waits. A `Deciding` is a choice you cannot rank, which is the shape the
tool exists for.

**Everything else is prose.** `Approve`, `Running`, `Landed`, `Blocked`, and `Failed` stay in the
message text. An `Approve` proposes one course, and a user often answers with a refinement rather than a
pick. A fixed option set would remove that refinement.

**A `Deciding` that offers nothing to rank is prose too.** The tool needs two options or more, and
that question has none.

Map the shape onto the tool:

```
part 1, the heading          the prose above the call
part 2, the context block    the prose above the call
each option and its cost     that option's description
part 3, the question         the question field
the recommendation           the first option, labelled (Recommended)
part 4, the footer           omit it, because the tool waits on its own
```

**Put the context above the call, never inside the options.** One run answered a rejected question
on the second try, once the background arrived first. The user said so: "The context was helpful.
Represent the question." An option carries its own cost, and the situation belongs above them all.

Real runs justify this section. One session sent 23 tool calls, and 8 reached the clarify path.
That is 35 percent, against a 6 percent baseline across 273 questions. Every one of those 8 packed
the situation into the options.

## Anti-patterns

| Anti-pattern | Why it fails |
|---|---|
| A heading on a message the user need not act on | The heading stops marking an action, so the user reads every turn again |
| A heading on each follow-up question inside one open gate | Twelve questions become twelve headings, and the heading stops staying rare |
| A blocking message with no footer | Its absence means nothing is outstanding, so the user reads an all-clear |
| `Approve` on a choice you cannot rank | The user sanctions a proposal nobody made, and the real question stays unasked |
| `Deciding` on a proposal you already formed | The user ranks options you invented to fill the shape |
| An unfenced roster or finding block | Real runs reached 286 and 327 columns, and neither block read as a table |
| A question that offers options and no recommendation | The user does the ranking work you were able to do first |
| Two questions in one message | The user answers the first, and the second one disappears |
| A bold sentinel in place of the footer | Bold marks emphasis everywhere else, so it marks nothing here |
| A new glyph for a meaning a taken glyph holds | A reader learns two symbols for one fact and trusts neither |
| Narrating each worker completion | Worker traffic drove 78% of assistant responses in one run, and none needed a reply |
| A wave block that reports only the wave that ended | The reader asks where the run is again, before the next wave joins |

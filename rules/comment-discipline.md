---
description: Comments are disallowed by default; after the implementation, propose only the few that pass the admission test
---

# Comment discipline

Code states what it does. This rule **disallows a comment by default**, and you never add one on your own judgment. You finish the implementation first. Then you assess the finished code, and you propose the few comments that pass every test. The user approves each one before it reaches the code. Every unapproved comment goes out of date and then misleads the next reader. This rule governs whether a comment exists.

## Rule of thumb

**Write no comment. Propose one only when all three tests below pass and the user approves it.**

The tests ask whether the code can hold the fact, and whether a reviewer breaks the code without it. A comment that repeats the code creates two copies of one fact, and only one copy stays true. All three tests must pass. Expect most finished code to need no comment at all.

## Default policy

- **Default:** Write no comment. The code states the meaning.
- **Timing:** Never pause the implementation to propose a comment. Finish the code, then assess it.
- **Approval:** Raise every proposal in one batch, ranked most important first. Wait for the user.
- **Approval scope:** One approval covers one comment. It never covers the file, the diff, or the batch.
- **Scope:** Comments and docstrings in code you write or change, and the documentation that describes that code.
- **Admissible:** All three tests below pass. A comment a tool reads — a pragma, a directive, or a license header — needs no approval.
- **Exceptions:** Documentation the user asked for, and documentation that is itself the deliverable.

## The admission test

A comment passes only when **all three** tests pass. Apply them to the finished code, never to code you are still writing.

**Test one: no code construct can hold the fact.** Try a name, a named constant, a type, an assertion, and a test. Each one holds the fact where the compiler or the test suite keeps it true. A comment holds it where nothing does. Go on only when all five fail.

**Test two: the fact matches one of exactly three cases.**

- **A non-obvious constraint.** The constraint comes from outside the repository, and no reader reaches it by reading the code: `// The API rejects more than 500 ids per call.`
- **A deliberate deviation from the obvious alternative.** A competent author writes that alternative, and it fails. Name both: `// Sequential on purpose: the endpoint limits by connection, not by key.`
- **A value that looks wrong and is correct.** A reader who lacks the comment corrects the value: `// 4096, not 4095: the header counts the trailing NUL.`

**Test three: you can name the change that breaks.** State the specific edit a future author makes without the comment, and the failure it causes. `A reader understands it faster` is not a failure. When you cannot name the broken edit, this test fails.

## Proposing a comment

Assess the finished code once, and raise every proposal in one batch. Rank the batch most important first, so the user reads the strongest case before the weakest. Say so plainly when the batch is empty, which is the expected result.

Each proposal carries four parts:

- The file and the line.
- The code the comment sits above, quoted. Quote the smallest snippet that shows the problem.
- The exact comment text.
- The case from test two, and the broken edit from test three.

Then stop and wait. Never write a comment into a file before the user approves it.

Propose nothing when any test fails. A rejected proposal is a correct outcome, and a proposal you cannot justify is noise the user has to read.

## What a comment must never do

- **Restate the code.** `// increment the counter` above `counter++` gives you a second place to maintain.
- **Carry background.** Design history, the reason for the whole approach, and links to a discussion belong in documentation or the commit message.
- **Narrate the change.** A comment must make sense to a reader who never saw your diff. `// now uses the new client` is commit-message content.

## Removing a comment

Delete a comment only when it sits inside code you are already changing. Delete it when it is wrong, when the code already says it, or when it narrates a change. Do not search for comments to delete, in this file or any other. A comment outside your declared paths is not yours to touch.

## When to change the documentation

Update documentation on two triggers only. The first is a documented claim that your change made false. The second is behavior a reader cannot infer from the code. Without one of these two triggers, leave the documentation as you found it.

Documentation the user asked for is outside this rule, and so is documentation that is itself the deliverable. Neither one needs a trigger.

## Example

One proposal, raised after the implementation:

**Prefer:**

```
1 of 1 — client.py:88

    for attempt in range(2):
        response = self._send(request)

Comment: "// Two retries only: the gateway drops the connection on the third attempt."
Case: a non-obvious constraint.
Breaks: an author raises the range to 4, and the gateway drops every third call.
```

**Avoid:** Writing `// Retry the request. Added retries here because the API was flaky, see the ticket for the background.` into the file.

## Anti-patterns

| Anti-pattern | Why it fails |
|---|---|
| A comment written into the file without approval | The default is no comment, and the user never got the choice |
| Pausing the implementation to propose a comment | The code is not finished, so nobody can judge what it fails to say |
| Proposals raised one at a time as you find them | The user cannot rank a proposal against the ones still coming |
| A proposal without the code it sits above | The user has to open the file to judge a claim you already read |
| A fact a named constant could hold | The constant stays true through a refactor, and the comment does not |
| `Breaks: the reader understands it more slowly` | Slow reading is not a failure, so test three did not pass |
| Treating one approval as approval for the batch | Each comment carries its own cost, so each one needs its own decision |
| Proposing a comment to look thorough | The user reads a proposal you already know fails a test |
| `// increment the counter` above `counter++` | Two copies of one fact, and only the comment can go out of date |
| `// now uses the new client` | A reader who never saw the diff cannot tell what changed |
| A paragraph of design history above a function | The documentation and the commit message already hold it |
| A comment deleted outside the code you changed | An unrelated hunk that every reviewer has to read |
| A docstring that lists the parameter names again | The signature already carries them |
| Documentation updated because the file was already open | No falsified claim and no new behavior, so nothing to record |

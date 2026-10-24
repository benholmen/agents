---
description: Build for the present need; defer what is cheap to add later
---

# YAGNI

Build what the present need requires and no more. A more general solution may well be worth building. It is a **proposal**, not a starting point. Complexity you add today needs a grounded reason, not an imagined future caller.

This rule governs code, process, and artifacts. In code, it governs abstractions, config surfaces, and extension points. In process, it governs extra phases, enforcement tooling, and scripts. In artifacts, it governs a template section written for a hypothetical future reader. It does not govern requirements. It is never an argument that the user asked for more than they need.

## Rule of thumb

**Defer what is cheap to add later; do not defer what is expensive to retrofit.**

A security model, a data model, and a published contract are all expensive to retrofit. Decide those now. A second config knob, a strategy seam, or a plugin hook is cheap to add later. Add each one the day a second caller exists. You can be wrong in both directions, and the cost differs in each direction. This rule is therefore an argument about cost, not an argument for doing less.

## Default policy

- **Default:** Build for the need at hand: the caller that exists, the case you have, the reader who is there.
- **Generality:** Name a more general design as an option. Leave it unbuilt until a second real case arrives.
- **Exceptions:** Some structures are expensive to retrofit. Design those up front: security boundaries, data models, published contracts, and storage formats.

## What this does not license

Correctness, error handling, security, and tests for the code you write now are part of the need at hand. To decline them is a **defect, not restraint**. The present need includes code that works, fails safely, and passes its tests.

## Disclosure, not offer

Naming a deliberately declined alternative is disclosure, not an offer of adjacent work. When you choose a simpler path over a more general one you considered seriously, name that alternative. Put the name in **one line at the point of the decision**. Never invent an alternative so that you have something to offer.

During planning that same disclosure belongs in the plan's `## What We're NOT Doing` section rather than in chat.

## Example

One caller needs one path resolved:

**Prefer:** A function that takes the one path its caller has. Add a second parameter the day a second caller needs one.

**Avoid:** A `PathResolver` interface with one `LocalPathResolver` implementation, selected through config, in case someone wants a remote resolver later.

## Anti-patterns

| Anti-pattern | Why it fails |
|---|---|
| A config option with a single caller | The call site is the configuration, and the knob adds a surface with no second value |
| A strategy interface with one implementation | Nobody knows yet where the boundary belongs, and the second implementation rarely fits the first cut |
| Enforcement tooling for a policy that has not been written | The script encodes a rule nobody agreed to, and then the script becomes the rule |
| A template section serving a hypothetical reader | Every real reader skips it, and somebody still has to maintain it |

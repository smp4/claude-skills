# Domain Language Guide — Operational Rules

## Naming conventions

- Glossary terms: plain English ("Archive Todo")
- Python DSL: snake_case (`TodoDSL.archive_todo`)
- TypeScript DSL: camelCase (`TodoDSL.archiveTodo`)
- The glossary `**DSL mapping**` field bridges the gap — it holds the
  exact code identifier, not a conceptual approximation

## Source of truth progression

1. **During /domain-interview**: DOMAIN.md glossary is authoritative.
   The domain expert approved these terms.
2. **During /new-plan**: DSL must match glossary — not the other way
   around. If you need a different name, ask the user to confirm.
3. **After both exist**: conflicts are flagged to the user, never
   auto-resolved. Neither DOMAIN.md nor DSL silently overrides the other.
4. **Code vs DSL**: code must match DSL. If code uses a different name
   than the DSL interface, the code is wrong.

## Adding a term

- [ ] Term appears in DOMAIN.md (as part of a business rule or example)
- [ ] Glossary entry created with definition and example
- [ ] DSL interface method added (or `TODO` marked if not yet implemented)
- [ ] Glossary DSL mapping field updated
- [ ] All drivers updated to implement the new method
- [ ] Doc-sync validates in /new-task before PR submission

## Removing a term

- [ ] Confirm with domain expert that the concept no longer applies
- [ ] Remove DSL interface method
- [ ] Mark glossary entry `DEPRECATED — removed YYYY-MM-DD — reason`
  (do not delete — preserve audit trail)
- [ ] Update DOMAIN.md if it referenced the term in a business rule
- [ ] Remove from all drivers and acceptance tests

## Bounded context isolation

If the same word appears in two bounded contexts with different meanings,
both DOMAIN.md glossary sections must have the term with a clear note
explaining the difference. Different meanings = different DSL methods.

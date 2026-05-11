# mergo + TOML Compatibility Research

> Date: 2026-04-26
> Sources: mergo GitHub (darccio/mergo), BurntSushi/toml docs, gopkg.in/yaml.v3 docs, mergo issues #54 and #190

## Question

Does `dario.cat/mergo` deep merge work correctly with data structures produced by `github.com/BurntSushi/toml`?

## Answer: Yes, with one critical caveat

### What works

- **map[string]interface{}**: BurntSushi/toml produces `map[string]interface{}` for unstructured decode. mergo handles this correctly with recursive merge. mergo's own test suite includes `TestJSONMaps`, `TestIfcMap`, `TestIfcMapWithOverwrite` validating this.
- **Table-arrays**: TOML table-arrays parse into `[]map[string]interface{}` or slices of structs. mergo can merge these.
- **Typed values**: TOML integers, floats, datetimes convert to native Go types (`int`, `float64`, `time.Time`). mergo handles via reflection.

### Critical caveat: zero-value override

**mergo treats empty/zero values as "unset" and skips them, even with `mergo.WithOverride`.**

This means:
- An **empty string `""`** in the incoming layer will NOT override a non-empty string in the existing layer
- A **zero integer `0`** will NOT override a non-zero integer
- A **false boolean** may not override a true boolean

This is a semantic mismatch with AFB's stated merge rule "incoming wins at leaf." For empty/zero values, incoming silently loses.

**Relevant issues**: mergo #54 (WithOverride inconsistency), mergo #190 (empty strings not overriding)

**Mitigation options**:
1. `mergo.WithOverwriteWithEmptyValue` — documented as handling this, but issue reports suggest inconsistent behavior
2. Characterization tests for every zero-value combination before trusting it
3. Custom post-merge fixup for known zero-value fields
4. Custom merge function (mergo supports `mergo.WithTransformers`) for leaf override

### YAML comparison

- gopkg.in/yaml.v3 is marginally better tested with mergo (mergo's own test suite uses yaml.v3)
- YAML produces `map[interface{}]interface{}` (not `map[string]interface{}`), but mergo handles both. Newer yaml.v3 can produce `map[string]interface{}` with appropriate tags
- **The zero-value problem affects both TOML and YAML equally** — it's a mergo behavior, not a format issue

### Recommendation

Stick with TOML. The zero-value issue must be addressed regardless of format choice. Required actions:

1. Write characterization tests for mergo with all zero-value combinations BEFORE writing composition logic
2. Test `WithOverwriteWithEmptyValue` specifically — verify it actually works for: empty string, 0, false, empty slice, empty map, nil
3. If `WithOverwriteWithEmptyValue` is unreliable, implement a custom `mergo.WithTransformers` that forces leaf override
4. Document in architecture.md that mergo zero-value behavior is a known constraint with tested mitigation

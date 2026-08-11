# The graph artifact

Every build, Zerk resolves your module's whole dependency graph in order to emit code. `Zerk.graph.json` is that graph, written down instead of thrown away.

This page covers what is in it, where it is, why it is not a build product you can depend on, and what it is useful for. For the command that prints it on demand, see [`ZerkCLI`](ZerkCLI.md).

## Why it exists

Nothing else can produce it.

A runtime container knows what was *registered*; it cannot tell you what the compiler *resolved* — which of three providers won a key, what each one actually depends on once values and defaults are folded in, how long each instance lives. Reading `Zerk.generated.swift` back gives you syntax, and you would be re-deriving decisions the plugin already made.

So the graph is a description of the emitted code, produced by the same pass that emits it. Every fact in it is one the generator acted on.

## Where it is

Beside the generated Swift, in the plugin's work directory:

```bash
find . ~/Library/Developer/Xcode/DerivedData -name Zerk.graph.json
```

Under SwiftPM that is `.build/plugins/outputs/<package>/<target>/destination/ZerkPlugin/Zerk.graph.json`; under Xcode, the equivalent path in DerivedData.

**It is deliberately not a declared build output.** SwiftPM routes a declared output it cannot compile into the target's *resource bundle*, which would ship the file — absolute developer paths and all — inside every app using Zerk, and conjure a `Bundle.module` for targets that previously had no resources. So the file is written but not declared. Nothing is lost by that: the same invocation writes both files, and the `.swift` output already forces it to rerun whenever an input changes.

The practical consequence is that `Zerk.graph.json` is a **development artifact, not a product**. Do not link a build step to it, and do not expect it in a release pipeline that only fetches build products.

## What is in it

One entry per key, one per value, and the edges between them.

```json
{
  "formatVersion" : 1,
  "keys" : [
    {
      "key" : "Caching",
      "displayName" : "Caching",
      "isExported" : false,
      "isGeneric" : false,
      "isImported" : false,
      "primaryMember" : "sessionCache",
      "providers" : [
        {
          "typeName" : "SessionCache",
          "memberName" : "sessionCache",
          "kind" : "initializer",
          "lifetime" : "scoped",
          "scope" : "session",
          "isAsync" : false,
          "isThrowing" : false,
          "isPrimary" : true,
          "location" : { "file" : "…/SessionCache.swift", "line" : 9, "column" : 1 },
          "dependencies" : [
            {
              "parameterName" : "baseURL",
              "typeName" : "String",
              "source" : "value",
              "key" : "String",
              "valueName" : "baseURL"
            }
          ]
        }
      ]
    }
  ],
  "values" : [ … ]
}
```

### Keys

| field | meaning |
|---|---|
| `key` | The canonical key, as Zerk matches it — `any` stripped, sugar expanded. This is the identity; two spellings of one type share it |
| `displayName` | The key as written in generated code, which keeps `any` |
| `isExported` | `@Injectable(public: true)` — the generated members are `public` |
| `isImported` | Satisfied by another module through `@ImportedInjectable`, so nothing here builds it |
| `isGeneric` | Registered under a [key shape](../Features/Generics.md) rather than a concrete type |
| `primaryMember` | The member backing `inject()`, or absent when the key is imported |

### Providers

`lifetime` is `transient`, `scoped` or `singleton`, and `scope` names the scope for a scoped one. `isolation` names the global actor a provider constructs on, and is absent when nonisolated. `memberName` is what the generated member is called — which is also what its [interjection point](../Testing/Interjection.md) is named after, so it is the string you would reach for in a test.

`isPrimary` marks the one provider backing `inject()`. A key with several providers has exactly one.

### Dependencies

One entry per provider parameter, in declaration order, each saying what satisfies it:

| `source` | meaning |
|---|---|
| `injectable` | Another key in the graph, named by `key`. This is the edge worth walking |
| `value` | An `@InjectableValue`, named by `valueName`. Values are matched by name *and* key, so the key alone would not identify which one was chosen |
| `caller` | Nothing in the module resolves it, so it bubbles up as a parameter of the generated member. Not a hole in the graph — it is the graph's boundary |

## Stability

`formatVersion` is the contract. Fields may be added within a version; removing or repurposing one bumps it. Ignore unknown fields rather than failing on them.

**Optional fields are omitted, not written as `null`.** A transient provider has no `scope` key at all. `jq` and `Codable` treat the two alike; if you index a dictionary directly, ask for the key rather than subscript it.

**Encoding is deterministic.** Every collection is sorted and nothing records a timestamp, so two builds of identical sources produce byte-identical JSON. That is not tidiness — a build output that changed every build would dirty every diff that touched it.

Paths are recorded exactly as the compiler was given them, which for a SwiftPM build is absolute. Relativize against your own root rather than expecting Zerk to guess it.

## The whole package at once

The artifact above is per target. [`swift package zerk graph`](ZerkCLI.md) is the
on-demand counterpart: it resolves every target and prints them together, with the edges
between modules drawn in. That page covers invoking it; what follows is what it adds to the
data.

### The cross-module view

This is the thing the per-target artifact structurally cannot give you.

Zerk resolves one module at a time — that isolation is what keeps the plugin cheap and correct. A module knows a key is `@ImportedInjectable` and nothing more. Something looking at every target at once can say *which* module answers that import:

```json
"imports" : [
  { "key" : "ApiServicing", "consumer" : "Feature", "providers" : ["Core"] }
],
"unresolvedImports" : [
  { "key" : "NotInThisPackage", "consumer" : "Feature" }
]
```

The whole document is a `modules` array of the per-module shape above, plus those two lists. `--format dot` and `--format mermaid` render the same thing as a picture — see [the formats](ZerkCLI.md#the-formats).

Three rules govern the matching:

- **Only exported keys match.** A key crosses a module boundary only with `@Injectable(public: true)`, because that is what makes its generated members `public`. A same-named key that is not exported has not answered the import.
- **Unmatched imports are reported, not dropped** — as `unresolvedImports`. Usually benign, since the key may live in another *package*, which this command cannot see. Occasionally it is a real mistake, and it is only visible if unmatched imports are shown.
- **Two exporters of one key are both listed.** Which one a consumer actually imported is decided by its `import` statements, which Zerk never sees, so neither is silently picked.

**This is presentation, not resolution.** The stitching runs after every module has already been resolved and generated independently, feeds back into no build, and produces no diagnostics. Cross-module *inference* remains deliberately unbuilt; nothing here depends on it or brings it closer.

## What it is for

Some things it answers that nothing else does:

Against the per-target artifact:

```bash
G=$(find .build -name Zerk.graph.json | head -1)

# Which providers won their keys?
jq -r '.keys[] | "\(.key) -> \(.primaryMember // "«imported»")"' "$G"

# What is kept alive, and for how long?
jq -r '.keys[].providers[] | select(.lifetime != "transient")
       | "\(.lifetime)\(.scope | if . then "(.\(.))" else "" end)\t\(.typeName)"' "$G"

# What does this key transitively depend on?
jq -r '.keys[] | select(.key == "Caching") | .providers[].dependencies[]
       | "\(.source)\t\(.key // .typeName)"' "$G"

# Which keys nothing else depends on? (candidate dead registrations)
jq -r '[.keys[].providers[].dependencies[].key] as $used
       | .keys[] | select([.key] - $used == [.key]) | .key' "$G"
```

That last one is worth calling out: an **unused registration** is invisible to the compiler, because a generated member nobody calls is still valid code. The graph is the only place it shows up.

Against the whole package the same queries work one level down — `.modules[].keys[]` — with `imports` and `unresolvedImports` alongside. And for rendering there is nothing to write: `--format dot` and `--format mermaid` do it.

---

[← Table of contents](../TableOfContents.md)

**See also:** [`ZerkCLI`](ZerkCLI.md) · [Generated code](GeneratedCode.md) · [How it works](HowItWorks.md) · [Diagnostics](Diagnostics.md) · [`@Scoped`](../Macros%20and%20Markers/Scoped.md) · [Interjection](../Testing/Interjection.md)

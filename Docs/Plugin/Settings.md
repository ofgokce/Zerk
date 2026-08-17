# Settings

`ZerkSettings.json` restates the parts of your build configuration that the plugin cannot read for itself. This page covers where the file goes, every key it accepts, and the rule that bounds what it can do.

## Where it goes

`ZerkSettings.json`, in your target's directory or at the package root (the target wins). The plugin declares it as a build input, so edits trigger regeneration. `//` and `/* */` comments are supported. Every key is optional; the defaults below describe a stock Swift 6 target.

An Xcode target has no directory of its own, so under the Xcode plugin the file is looked for alongside the target's sources first and at the project root last — the same precedence, the target's own file winning. Where the sources span several directories, the shallowest wins, and two at the same depth are ordered by path; a file meant for a whole target sits at the root of its sources, and the sort is what keeps the answer from depending on the order Xcode happened to enumerate the files in.

No file at all is not an error — Zerk falls back to the defaults.

## The keys

```jsonc
{
  "version": 1,

  // Must match SWIFT_DEFAULT_ACTOR_ISOLATION. If the two disagree, Zerk infers
  // the wrong isolation and the generated code will not compile.
  //   "nonisolated" | "MainActor" | any custom global actor name
  "defaultActorIsolation": "nonisolated",

  // How @InjectableValue declarations reach their value when they do not say.
  // Mirrors no build setting — it is Zerk's own default, overridden per value
  // by @InjectableValue(.copied) / @InjectableValue(.referenced).
  //   "copied" | "referenced"
  "valueInjectionMethod": "copied",

  // Language mode, mirroring SWIFT_VERSION — not the toolchain version.
  //   "5" | "6"
  "swiftVersion": "6",

  // Mirrors SWIFT_STRICT_CONCURRENCY. Only consulted under "5"; Swift 6
  // language mode is complete checking by definition.
  //   "minimal" | "targeted" | "complete"
  "strictConcurrency": "minimal",

  // Mirrors SWIFT_UPCOMING_FEATURE_ISOLATED_DEFAULT_VALUES (SE-0411).
  // Under "5", either this or "strictConcurrency": "complete" is what allows
  // an isolated provider to resolve a same-domain isolated dependency.
  "isolatedDefaultValues": false
}
```

That is every key the plugin reads. Each one in more detail:

### `version`

Schema version of the file. `1` is the only version this build understands; a file declaring a higher one is rejected outright rather than partially honored.

### `defaultActorIsolation`

The ambient isolation Zerk assumes for declarations that state none. Mirrors `SWIFT_DEFAULT_ACTOR_ISOLATION`. Default `"nonisolated"`.

`"nonisolated"` is Swift's own default. `"MainActor"` is Xcode 26 "Approachable Concurrency" (SE-0466), where every declaration that states no isolation of its own — including your `@Injectable` types — is `@MainActor`, and Zerk mirrors that onto the generated members; mark providers `nonisolated` where you want DI callable from anywhere. Any other string is treated as the name of a custom global actor.

### `valueInjectionMethod`

`"copied"` (default) or `"referenced"`. Applies to a value whose own declaration does not say — `@InjectableValue(.copied)` and `@InjectableValue(.referenced)` override it per declaration, and `.default` on a declaration is the explicit spelling of "defer to this setting".

`copied` inlines the declaration's body into the generated member, which then never reads the original, so a later write to the source is invisible to injection. `referenced` makes the generated member read through to the declaration, so runtime updates propagate and a settable source produces a settable member that writes back; the source must be visible to the generated file, so `private` and `fileprivate` declarations cannot be referenced.

### `swiftVersion`

`"5"` or `"6"`. The target's language mode, mirroring `SWIFT_VERSION` — not the toolchain version. Default `"6"`. A Swift 5 target under a current toolchain is fully supported; the only construct it cannot express is the one `isolatedDefaultValues` describes. Written as a JSON number it is read as the equivalent string.

### `strictConcurrency`

`"minimal"` (default), `"targeted"`, or `"complete"`. Mirrors `SWIFT_STRICT_CONCURRENCY`. Only consulted under `"5"`; Swift 6 language mode is complete checking by definition. `"complete"` implies `isolatedDefaultValues`.

### `isolatedDefaultValues`

`false` by default. Mirrors `SWIFT_UPCOMING_FEATURE_ISOLATED_DEFAULT_VALUES`, the opt-in for SE-0411.

Zerk resolves a dependency into a default argument. SE-0411 evaluates that expression in the *callee's* domain, which is what makes it legal for an isolated member to default an argument to a dependency in the **same** domain. Without SE-0411 the expression is evaluated at the caller and rejected. Swift 6 language mode has this always; a Swift 5 target gets it from either this upcoming feature or `strictConcurrency: "complete"`, independently.

This affects exactly one construct. An isolated provider whose dependency is nonisolated, or is in a different domain, or is a `@Singleton`, needs nothing here. If Zerk does need it and this says the target lacks it, you get a build error naming the providers instead of code that cannot compile.

## Comments and errors

Comment stripping is string-aware: a `//` inside a JSON string literal — a URL, say — is left alone, and escape sequences are honoured so a string ending in `\\` still terminates correctly. Line numbers are preserved, so a JSON parser error still points at the right line.

Unknown keys are ignored, so a file written for a newer Zerk stays loadable. A malformed *known* key is an error rather than a silent fallback to the default, and the failure is reported against the file itself.

## What it cannot do

The file governs how Zerk **reads** your source. It never governs what Zerk **writes** — every generated member is pinned with explicit isolation regardless.

---

[← Table of contents](../TableOfContents.md)

**See also:** [How it works](HowItWorks.md) · [Generated code](GeneratedCode.md) · [Diagnostics](Diagnostics.md) · [Concurrency](../Features/Concurrency.md) · [@InjectableValue](../Macros%20and%20Markers/InjectableValue.md) · [@Isolated](../Macros%20and%20Markers/Isolated.md) · [@Singleton](../Macros%20and%20Markers/Singleton.md)

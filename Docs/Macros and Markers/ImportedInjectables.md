# Imported injectables

Zerk resolves within one module. `@ImportedInjectable` and `@ImportedInjectableValue` describe
a key, or a value, that another module declares, so this module's graph can resolve against it;
Imports are copied into the generated file so it can see the names
involved.

## `@ImportedInjectable`

**`@ImportedInjectable`** — declares a key that lives in another module, so this module's graph
can resolve against it.

Zerk resolves within one module. `@Injectable(public: true)` makes a key's members public, but
the consuming module still has no idea the key exists, what it needs, or what effects and
isolation it carries. This states all of that:

```swift
private enum ZerkImports {
    @ImportedInjectable
    static func session(baseURL: URL) -> Session

    @ImportedInjectable
    @MainActor
    static func router() throws -> Routing
}
```

Only the shape matters. The return type is the key, the parameters are what the foreign provider
needs, and `async`/`throws`/global-actor annotations state its effects and isolation. The
declaration's name, visibility, and whether it is global, `static`, or an instance method make no
difference — **nothing ever calls it**.

### Without a body

Written **without a body**, the macro synthesises `Zerk<Key>.inject(…)`, and that expansion is
the check: if the key is not exported, or its signature differs, the declaration itself fails to
compile.

### With a body

Written **with a body**, the body names which member the key resolves through instead of the
primary. It must be a single `Zerk` expression and nothing else, because Zerk inlines it at every
use site:

```swift
@ImportedInjectable
static func session() -> Session { Zerk<Session>.staging }
```

### What an import generates

An imported key satisfies local parameters and generates **no members** — what it resolves is
built in the other module, so `extension Zerk<Key>` and `inject()` belong there. One import per
key; a key that is both imported and declared `@Injectable` locally is an error, as is importing
one twice.

Given a key import and a value import side by side:

```swift
protocol Session {}

private enum ZerkImports {
    @ImportedInjectable
    static func session() -> Session

    @ImportedInjectableValue
    static var baseURL: String { Zerk<String>.baseURL }
}

@Injectable
final class Repo {
    @InjectableProviding
    init(session: Session, baseURL: String) {}
}
```

Zerk generates (macro-shim preamble elided):

```swift
extension Zerk<Repo> {
    nonisolated static func repo(session: Session = Zerk<Session>.inject(), baseURL: String = Zerk<String>.baseURL) -> Repo {
        if let interjected = _$interjected(for: \.`repo`) {
            return interjected
        }
        return Repo(session: session, baseURL: baseURL)
    }

    nonisolated static var repo: Repo {
        repo()
    }

    nonisolated static func inject() -> Repo {
        repo()
    }

}

extension Zerk<Repo>.Interjection {
    nonisolated var `repo`: Void {}
}
```

There is no `extension Zerk<Session>` and no `extension Zerk<String>` in that file. Both
imports appear only as defaults on the consumer's member.

### Effects and isolation

What the declaration states is what the graph plans for. An `async throws` import resolves with
`try await` and carries the effects onto everything downstream of it; a body-form import is
inlined as written:

```swift
private enum ZerkImports {
    @ImportedInjectable
    static func session() async throws -> Session

    @ImportedInjectable
    static func staging() -> Routing { Zerk<Routing>.staging }
}

@Injectable
final class Repo {
    @InjectableProviding
    init(session: Session, router: Routing) {}
}
```

```swift
extension Zerk<Repo> {
    nonisolated static func repo(session: Session, router: Routing = Zerk<Routing>.staging) -> Repo {
        if let interjected = _$interjected(for: \.`repo`) {
            return interjected
        }
        return Repo(session: session, router: router)
    }

    nonisolated static func repo(router: Routing = Zerk<Routing>.staging) async throws -> Repo {
        repo(session: try await Zerk<Session>.inject(), router: router)
    }

    nonisolated static func inject() async throws -> Repo {
        try await repo()
    }

}
```

An imported value's isolation reaches resolution the same way: a `@MainActor` import read from a
nonisolated provider crosses a domain, so it resolves in the body with an `await` rather than in
a default, and `inject()` becomes `async`.

The generated file sees the foreign types through the imports Zerk copies from this file.

## `@ImportedInjectableValue`

**`@ImportedInjectableValue`** — the same for an `@Injectable` **value**.

Values are matched by key *and name* together, which is what stops two unrelated `String`s from
being interchangeable. `@ImportedInjectable` registers its key's primary and so would discard the
name, letting one imported `String` answer for every `String` parameter in the module — hence a
separate marker, on a property rather than a function:

```swift
private enum ZerkImports {
    @ImportedInjectableValue
    static var baseURL: String { Zerk<String>.baseURL }

    @ImportedInjectableValue
    static var apiKey: String { Zerk<String>.apiKey }
}
```

Both are imported under the one key `String` and stay distinct, because a parameter has to be
*named* `baseURL` to match the first. Importing as many values of a type as you like is the
normal case; only a repeated **name** is a conflict.

The type annotation is the key, the declaration's own name is what parameters must be called, and
the getter names the foreign member. Since those last two are separate, an import can be
**renamed**:

```swift
@ImportedInjectableValue
static var apiBaseURL: String { Zerk<String>.baseURL }   // matches `apiBaseURL:`
```

The getter is required — unlike the key form there is nothing to synthesise, because there is no
"primary `String`" to fall back on — and must be a single `Zerk` expression, since Zerk inlines it
at every use site. That getter is also the check: naming a value the other module did not export
fails to compile right at the declaration. Imported values are **read-only**, and
`= Zerk<String>.baseURL` is refused because it would capture the value once instead of reading it
per resolution.

## Imports are automatic

The generated file names types it did not declare — a key written `@Injectable<CLLocation>`, a provider parameter typed `Date` — and reading syntax cannot tell which module a name came from. So Zerk copies the imports of every file it reads into the file it writes.

That is correct by construction rather than by diligence: a declaration mentioning `Date` sits in a file that imports `Foundation`, or that file would not compile, so the set can only ever be a superset of what the generated file needs. There is nothing to declare and nothing to keep in step.

Only the files that need to, though. A file whose registrations name nothing but types this module declares has already been seen by the compiler here, so its imports buy the generated file nothing and are left out — a module in scope for no reason is a name the generated file could trip over that it never needed. Narrowing is per *file* rather than per name, because which module a name came from is exactly what syntax cannot tell.

Two things are not copied. `@testable import` belongs to the test target that wrote it. Access-level modifiers and attributes are dropped — a plain `import` is what the generated file needs, and `internal import X` states a boundary about *that* file. A guarded import keeps its guard, so a debug-only module stays debug-only; see [Conditional compilation](../Features/ConditionalCompilation.md).

If two imported modules export the same name, write the module out — `@Injectable<ModuleA.Config>`. Zerk normally strips a module qualifier, since `Core.Service` and `Service` are one type, but not for a name two modules both produce: those are two types and stay two keys, and the generated file says `extension Zerk<ModuleA.Config>`.

## Diagnostics

The macros check one declaration each; the plugin checks the module. In Zerk's own words:

| what you wrote | error |
|---|---|
| `@ImportedInjectable` on something other than a function | `@ImportedInjectable can only be applied to a function.` |
| an import with no return type | `@ImportedInjectable must declare the type it imports as its return type.` |
| a body that is not a single `Zerk` expression | `@ImportedInjectable's body must be a single Zerk expression, e.g. 'Zerk<Session>.staging'. Zerk inlines it wherever the dependency is resolved, so it cannot contain other logic.` |
| a key imported and declared locally | `'Session' is both imported and declared @Injectable in this module. Remove the import, or the local declaration.` |
| one key imported twice | `'Session' is imported more than once (also at …). Keep the one you meant.` |
| `@ImportedInjectableValue` on a function | `@ImportedInjectableValue can only be applied to a property. Use @ImportedInjectable to import a key.` |
| a value import with no type annotation | `@ImportedInjectableValue needs an explicit type — it is the injection key, and Zerk reads syntax so it cannot infer one.` |
| `= Zerk<String>.baseURL` instead of a getter | `@ImportedInjectableValue reads the other module's value on every resolution, so it needs a getter rather than an assignment. Write '{ Zerk<String>.baseURL }'.` |
| no getter at all | `@ImportedInjectableValue must name the member it imports, e.g. 'static var apiKey: String { Zerk<String>.apiKey }'. There is no primary value for a key to fall back on.` |
| a getter that is more than one `Zerk` expression | `@ImportedInjectableValue's getter must be a single Zerk expression, e.g. 'Zerk<String>.apiKey'. Zerk inlines it wherever the value is resolved, so it cannot contain other logic.` |
| one name imported twice | `'baseURL' is imported more than once as a 'String' value (also at …). Values are matched by name, so rename one of them.` |
| an import colliding with a local value | `'baseURL' is imported as a 'String' value, but this module already declares one (…). Rename the import, or drop the local declaration.` |

---

[← Table of contents](../TableOfContents.md)

**See also:** [`@Injectable`](Injectable.md) · [`@InjectableValue`](InjectableValue.md) · [Key aliases](ZerkAlias.md) · [Foreign types](../Features/ForeignTypes.md) · [Concurrency](../Features/Concurrency.md) · [How it works](../Plugin/HowItWorks.md) · [Generated code](../Plugin/GeneratedCode.md) · [Limitations](../Plugin/Limitations.md) · [Diagnostics](../Plugin/Diagnostics.md)

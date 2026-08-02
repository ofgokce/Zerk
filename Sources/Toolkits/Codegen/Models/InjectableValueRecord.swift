//
//  InjectableValueRecord.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 27.07.2026.
//

/// An `@Injectable` *value* — a static property rather than a type, e.g.
/// `@Injectable static var apiKey: String`.
///
/// Values are matched to parameters by type key **and name** together, which is
/// what stops two unrelated `String` values from being interchangeable.
/// `bodyText` is the accessor's source, re-emitted into the generated member so
/// the value is recomputed per resolution rather than captured once.
struct InjectableValueRecord {
    let name: String
    /// `var` so the alias pass can fold it onto its group's representative.
    var typeKey: String
    let typeName: String
    /// How the key is written in the generated file: the canonical spelling with
    /// `any` as the developer wrote it. `nil` falls back to the key itself.
    var keyDisplayName: String? = nil
    let bodyText: String?
    let location: AttributeLocation
    /// Values participate in the isolation model exactly like type providers:
    /// the body may touch isolated state, and under an ambient `MainActor`
    /// default an unannotated `@Injectable var` is `@MainActor`.
    var isolation: ProviderIsolation = .nonisolated
    /// Whether the generated member copies the declaration's body or reads
    /// through to it. Already resolved against `ZerkSettings` — never
    /// `.default` by this point.
    var injectionMethod: ValueInjectionMethod = .copied
    /// Dot-joined names of the enclosing types, e.g. `"AppConstants"`, or `nil`
    /// for a top-level declaration.
    ///
    /// `.referenced` needs it to qualify the read: a bare name inside
    /// `extension Zerk<T>` resolves to the generated member itself, so an
    /// unqualified reference would recurse. Top-level values have no qualifier
    /// available and go through a file-scope thunk instead.
    var enclosingTypePath: String? = nil
    /// Whether the source can be assigned — a `var` that is stored or has a
    /// setter. Only then does the generated member get a setter.
    var isSettable: Bool = false

    /// The spelling every `Zerk<Key>` naming this value uses, so the extension
    /// declaring the member and the expressions reading it agree.
    var keyText: String { keyDisplayName ?? typeKey }
}

//
//  ZerkMacrosPlugin.swift
//  Zerk
//
//  Created by Ömer Faruk Gökce on 2.12.2025.
//

import SwiftCompilerPlugin
import SwiftSyntaxMacros

/// The compiler plugin hosting Zerk's attached macros.
///
/// Almost every macro here expands to *nothing*. Zerk generates its injection
/// code from the build-tool plugin (`ZerkPlugin` → `ZerkCodegen`), which parses
/// the whole module and so can resolve dependencies across files — something an
/// attached macro, which only ever sees one declaration, cannot do.
///
/// These macros exist for two other reasons: they make the attribute legal
/// Swift so the plugin has something to read, and they report the errors that
/// *are* decidable from a single declaration (a missing provider, a
/// contradictory annotation) immediately at the declaration site rather than
/// later from the generator. `InjectedMacro` is the one exception that expands.
@main
struct ZerkMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        InjectableMacro.self,
        InjectableValueMacro.self,
        InjectableValuesMacro.self,
        NonInjectableMacro.self,
        InjectedMacro.self,
        InjectedDynamicallyMacro.self,
        ProvidingMacro.self,
        SingletonMacro.self,
        ScopedMacro.self,
        IsolatedMacro.self,
        InjectableAliasMacro.self,
        ImportedInjectableMacro.self,
        ImportedInjectableValueMacro.self,
        InterjectMacro.self,
        InjectableAliasDeclarationMacro.self,
    ]
}

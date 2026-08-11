# `ZerkCLI`

`swift package zerk` — Zerk's command-line surface.

This page covers how to get it, every command and option, what the exit codes mean, and the one permission you may need. For what the graph it prints actually *contains*, see [Graph artifact](GraphArtifact.md).

## It is a command plugin, not a build one

Zerk ships two plugins and they are used in opposite ways:

| | `ZerkPlugin` | `ZerkCLI` |
|---|---|---|
| kind | build tool | command |
| when | every build | when you ask |
| setup | attached to each target that declares injectables | nothing |

You never add `ZerkCLI` to a target's `plugins:`. Depending on the Zerk package is enough for the verb to exist:

```bash
swift package plugin --list
# ‘zerk’ (plugin ‘ZerkCLI’ in package ‘Zerk’)
```

In Xcode the same commands appear under the project's plugin menu.

## `swift package zerk`

One verb, with subcommands under it — SwiftPM allows a plugin exactly one verb, so anything finer arrives as an argument. Run bare, it prints the list:

```
Usage: swift package zerk <command> [options]

Commands:
  graph     Export the resolved dependency graph for this package.
  help      Show this message.

Run 'swift package zerk <command> --help' for a command's options.
```

`help`, `--help` and `-h` are all accepted, at either level:

```bash
swift package zerk                # usage
swift package zerk help           # usage
swift package zerk help graph     # the graph command's options
swift package zerk graph --help   # the same
```

## `zerk graph`

Resolves every target's dependency graph and prints it, [joined across module boundaries](GraphArtifact.md#the-cross-module-view).

```bash
swift package zerk graph                                   # every target, JSON, to stdout
swift package zerk graph --format mermaid                  # paste into a README or PR
swift package zerk graph --target AppCore --target Networking --format dot | dot -Tpng -o graph.png
swift package zerk graph --format json --output /tmp/graph.json
```

| Option | Meaning |
|---|---|
| `--target <name>` | Only this target. Repeat for several; the default is all of them |
| `--format <format>` | `json` (default), `dot`, or `mermaid` |
| `--output <path>` | Write to a file instead of stdout. See [permissions](#writing-a-file) |
| `-h`, `--help` | Show the command's options |

### The formats

**`json`** is the [`ZerkPackageGraph`](GraphArtifact.md#the-cross-module-view) — every module's keys and values, plus the resolved and unresolved imports between them. Pipe it into `jq`.

**`dot`** and **`mermaid`** draw the same picture: one cluster per module, one node per key, solid edges for dependencies within a module and **dashed** ones where an import is answered by another module. Node labels carry the lifetime when there is one worth naming — a transient node is unannotated, because most of them are.

```mermaid
graph LR
    subgraph Core
        m0k0["ApiServicing<br/>singleton"]
    end
    subgraph Feature
        m1k0["ApiServicing<br/>imported"]
        m1k1["FeedViewModel"]
    end
    m1k1 --> m1k0
    m1k0 -.-> m0k0
```

Mermaid renders in GitHub and most Markdown viewers, so it is the one to reach for in a PR. DOT is for `dot -Tpng`, `-Tsvg`, and anything else Graphviz can do.

## It re-runs codegen

The command does **not** read the [`Zerk.graph.json` files a build leaves behind](GraphArtifact.md#where-it-is). It runs `ZerkCodegen` itself, once per target, into its own work directory.

That is deliberate. Those files only exist after a successful build, they are undeclared outputs so nothing guarantees where they are, and finding them means guessing at build-directory layout. Running codegen here instead means the command works on a clean checkout and depends on nothing but your sources.

The cost is small: a codegen pass is parsing plus resolution, not compilation.

## Writing a file

Output goes to **stdout** by default, which pipes and needs no permission at all.

`--output` writes a file. A plugin runs sandboxed, so writing *inside the package* needs SwiftPM's flag:

```bash
swift package zerk graph --format json --output /tmp/graph.json          # outside: fine
swift package --allow-writing-to-package-directory zerk graph \
    --format dot --output ./graph.dot                                    # inside: needs the flag
```

`ZerkCLI` deliberately does **not** declare `permissions:` in its manifest. Doing so would prompt every user for package-write access on every invocation, when the default path never writes anything. Forgetting the flag is not a mystery either — the error names it:

```
error: could not write ./graph.dot: You don't have permission to save the file “graph.dot”…
If that path is inside the package, the plugin needs permission: swift package --allow-writing-to-package-directory zerk graph …
```

## Exit codes

Every failure exits non-zero with a named cause, so the command is usable in CI:

| | Exit |
|---|---|
| success, or any help output | `0` |
| unknown command — `zerk nonsense` | `1` |
| unknown option — `zerk graph --bogus` | `1` |
| unknown target — `zerk graph --target Nope` | `1` |
| missing option value — `zerk graph --format` | `1` |
| codegen failed for a target | `1` |
| refused write | `1` |

A codegen failure prints the same diagnostics a build would, pointing at your source rather than at generated code.

---

[← Table of contents](../TableOfContents.md)

**See also:** [Graph artifact](GraphArtifact.md) · [How it works](HowItWorks.md) · [Generated code](GeneratedCode.md) · [Diagnostics](Diagnostics.md)

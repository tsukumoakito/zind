<!--
SPDX-FileCopyrightText: 2026 TSUKUMO Akito <tsukumoakito99@duck.com>
SPDX-License-Identifier: MIT
-->

# Zind User Manual (v1.0.9 / 2026-09-06)

**Zind** - Dynamic structural API indexer for Zig.

---

## SYNOPSIS

`zind [STD_PATH] [OPTIONS...]`

---

## DESCRIPTION

**Zind** is a structural API indexing tool designed for the rapidly evolving Zig programming language. Unlike static documentation generators, Zind performs direct **AST (Abstract Syntax Tree)** analysis on the actual Zig source code installed on your system.

### Universal Version Support

While optimized for Zig 0.16.0, **Zind is inherently version-agnostic.** Since it extracts the "Ground Truth" directly from the source code, it will correctly visualize the logical structure of any Zig version you provide.

---

## STRATEGIC NAVIGATION (TIPS)

To effectively navigate any version of the Zig standard library, follow this recommended workflow:

1. **Understand the Big Picture**: Start by using `--top-level` or `--top-level-sub` to visualize the overall namespace hierarchy of your current Zig environment.
2. **Drill Down**: Once the structure is identified, use `--scope`, `--depth-scope`, `--probe`, and `--depth-probe` to narrow the focus and inspect specific API mechanics, logic flows, and implementation details.
3. **Version Migration**: Use `--flagged-deprecated` to identify breaking changes and logic shifts during version upgrades. Combine this with the probing flags to deep-dive into recommended alternatives.
4. **Version-Specific Groups**: Predefined `--groups` presets are strictly optimized for Zig 0.16.0 (with internal mapping for 0.15.2). For any other versions, presets may drift; always use the top-level discovery flags on your specific Zig version to verify its unique logical layout.

---

## Official Resources & Toolchain

Zind focuses on deep source analysis, while the official toolchain manages your development workflow.

* **Toolchain Operations**: Run `zig help` to explore built-in commands like `build`, `run`, `test`, and `env`. Zind relies on the output of `zig env` to detect your environment.
* **Language Specs**: Visit [https://ziglang.org/](https://ziglang.org/) for the official language reference and release notes.

---

## CORE OPTIONS (Global)

| Option | Description |
| :--- | :--- |
| `--std-path <path>` | Explicitly specifies the Zig standard library path. If omitted, Zind detects it via the `zig` binary in your PATH. |
| `--lang <en\|ja>` | Sets the display language for help messages, overriding environment variables. Core output remains in English. |
| `--root-path <path>` | Specifies the project root directory for project-aware analysis. |
| `--color <auto\|always\|none>` | Configures ANSI color output. Default is `auto`. |
| `--debug` | Enables performance and buffer metrics report for the analysis engine. |
| `--libc`, `--no-libc` | Simulates the presence or absence of C library linkage for conditional compilation evaluation. |
| `--target-os <os>` | Overrides the host OS to simulate API definitions for different targets (e.g., linux). |
| `--target-arch <arch>` | Overrides the host Architecture to simulate API definitions (e.g., x86_64). |

---

## LIBRARY INDEXING & FILTERS

| Option | Description |
| :--- | :--- |
| `--scope <namespaces>` | Restricts analysis to specific namespaces (e.g., `std.mem,std.fs`). |
| `--depth <N\|unlimited>` | Sets the recursion depth limit. `0` shows only the target; `unlimited` crawls every member. |
| `--depth-scope <N> <scope>` | Atomic flag to apply a specific depth limit to a specific scope. |
| `--merge` | Merges multiple scan tasks into a single sorted index output. |
| `--no-counts` | Disables discovery of nested/hidden items count for faster processing. |
| `--summary-only` | Displays only entry counts and module statistics without individual symbols. |
| `--file <path>` | Directly indexes a specific file instead of following the FQN logic. |
| `--show-private` | Forces the display of internal implementation elements (private fields/tags). |

---

## DISCOVERY & DEEP INSPECTION

| Option | Description |
| :--- | :--- |
| `--search <keywords>` | Performs a keyword search across FQNs, doc comments, and constant values. Sets depth to `unlimited`. |
| `--probe <fqn>` | Extracts the full implementation lineage and actual source code snippets. Sets depth to 1 by default. |
| `--depth-probe <N> <fqn>` | Atomic specification of recursion depth and probe target. |
| `--flagged-deprecated` | Extracts only symbols marked with 'Deprecated' semantics. |

---

## MODULE GROUPS

Predefined groups optimized for Zig 0.16.0 / 0.15.2. Use `--group-<ID>` or `--group-<name>`.

* **1: core**
    `mem, heap, Thread, atomic, meta, builtin, simd, options, Options, start`
* **2: data-struct**
    `ArrayList, MultiArrayList, array_list, HashMap, ArrayHashMapUnmanaged, AutoArrayHashMapUnmanaged, StringArrayHashMapUnmanaged, AutoHashMap, StringHashMap, hash_map, array_hash_map, BufMap, static_string_map, BufSet, bit_set, BitStack, Deque, PriorityQueue, PriorityDequeue, Treap, enums, DoublyLinkedList, SinglyLinkedList, StaticBitSet, DynamicBitSet`
* **3: system-io**
    `Io, fs, http, Uri, process, DynLib, time, tz, Tz`
* **4: data-proc**
    `json, zon, fmt, ascii, unicode, base64, leb, compress, zip, tar`
* **5: math-sec**
    `math, Random, sort, crypto, hash`
* **6: dev-tool**
    `zig, Build, SemanticVersion, testing, debug, log, Progress`
* **7: agnostic-spec**
    `dwarf, pie, Target, gpu`
* **8: os-linux-posix**
    `os.linux, posix, elf`
* **9: os-windows**
    `os.windows, coff, pdb`
* **10: os-macos**
    `macho`
* **11: os-other**
    `wasm, os.wasi, os.emscripten, os.uefi, os.plan9`
* **12: external-c-tool**
    `c, valgrind`
* **app-dev-core**
    `General application logic (Merged Groups 1-7).`

---

## FILTER OPTIONS

| Option | Description |
| :--- | :--- |
| `--filter-layer1` | Excludes low-level OS/C primitives (`std.c`, `std.os`, `std.posix`). |
| `--only-layer1` | Restrict output to OS-specific primitives only. |
| `--top-level` | Alias for `--depth-scope 1 std`. Shows only primary members. |
| `--top-level-sub` | Alias for `--depth-scope 2 std`. Includes children of primary members. |

---

## EXPERIMENTAL / ROADMAP

The following options are part of the Project Mode development roadmap. In `v1.0.0`, using these will display a warning and terminate the analysis as they are not yet available.

| Option | Description |
| :--- | :--- |
| `--mode project` | Specifies project-local symbol indexing instead of the library. |
| `--include <file1,...>` | Whitelists specific files for project analysis. |
| `--exclude <file1,...>` | Blacklists specific files or directories from analysis. |
| `--skeleton` | Generates a logic hierarchy and call graph skeleton. |
| `--users <symbol>` | Lists all references and call sites of a specific symbol. |
| `--trace-up <symbol>` | Traces logic propagation from a target back to entry points. |

---

## OUTPUT NOTATION

Zind uses a high-density notation to convey implementation semantics:

* **Lineage Tracing (`>>>`)**: `A = B >>> C` indicates that symbol A is an alias for B, which is ultimately defined at C.
* **Conditional Definitions (`[...]`)**: `std.posix.Stat [native_os is linux]` clarifies the environment conditions required for the definition to be active.
* **Hidden Item Counts**:
    * `(+n items)`: Public members omitted due to depth settings.
    * `{+n items}`: Private internal members, indicating structure complexity.

---

## EXAMPLES

**Analyze the current Zig environment's top-level structure:**

```bash
zind --top-level
```

**Search for all ArrayList related symbols in any provided std:**

```bash
zind --search ArrayList
```

**Probe std.ArrayList with depth 2 to see immediate members:**

```bash
zind --depth-probe 2 std.ArrayList
```

**List all deprecated APIs in the current environment:**

```bash
zind --flagged-deprecated
```

---

## EXIT STATUS

* **0**: Success.
* **1**: Fatal error (path not found, invalid arguments, or AST parsing failure).

---

## AUTHOR

TSUKUMO Akito <tsukumoakito99@duck.com>

## SEE ALSO

* **Official Repository (Codeberg)**: [https://codeberg.org/tsukumoakito/zind](https://codeberg.org/tsukumoakito/zind)

* **Mirror Repository (GitHub)**: [https://github.com/tsukumoakito/zind](https://github.com/tsukumoakito/zind)

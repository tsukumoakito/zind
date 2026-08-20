const std = @import("std");
const Io = std.Io;
const Writer = Io.Writer;
const builtin = @import("builtin");
const build_options = @import("build_options");

const Types = @import("Types.zig");
const Config = Types.Config;

pub fn printHelp(writer: *Writer, target_version: []const u8, std_path: []const u8) !void {
    const zind_version = build_options.version;
    const target_zig = std.fmt.comptimePrint("{d}.{d}.{d}", .{
        builtin.zig_version.major,
        builtin.zig_version.minor,
        builtin.zig_version.patch,
    });

    try writer.print("Zind - Zig Structural API Indexer\n\n", .{});
    try writer.print("Usage: zind [path_to_std] [options]\n\n", .{});

    try writer.print("Environment Status:\n", .{});
    try writer.print("  Indexer Engine : {s} (Targeting Zig {s})\n", .{ zind_version, target_zig });
    try writer.print("  Target Library : {s}\n", .{std_path});
    try writer.print("  Target Version : {s}\n\n", .{target_version});

    try writer.print("Core Configuration:\n", .{});
    try writer.print("  --mode lib|library           Standard library indexing (Default)\n", .{});
    try writer.print("  --std-path <path>            Explicitly specify Zig standard library path\n", .{});
    try writer.print("  --root-path <path>           Specify project root directory\n", .{});
    try writer.print("  --lang <en|ja>               Sets the display language for help messages, overriding environment variables. Core output remains in English.\n", .{});
    try writer.print("  --color <auto|always|none>   Configure ANSI color output (Default: auto)\n", .{});
    try writer.print("  --no-color                   Force disable ANSI color output\n", .{});
    try writer.print("  --debug                      Enable performance & buffer metrics report\n", .{});
    try writer.print("  --libc                       Assume libc is linked for conditional parsing\n", .{});
    try writer.print("  --no-libc                    Assume libc is NOT linked for conditional parsing\n", .{});
    try writer.print("  --target-os <os>             Override target OS for conditional parsing\n", .{});
    try writer.print("  --target-arch <arch>         Override target Arch for conditional parsing\n", .{});

    try writer.print("\nLibrary Indexing & Semantic Analysis:\n", .{});
    try writer.print("  --scope <namespace>          Restrict analysis to specific namespaces (e.g., std.mem,std.fs)\n", .{});
    try writer.print("  --depth <N|unlimited>        Set recursion depth limit (0 = self only)\n", .{});
    try writer.print("  --depth-scope <N> <scope>    Atomic specification of depth and scope\n", .{});
    try writer.print("  --merge                      Merge multiple scan tasks into a single sorted index\n", .{});
    try writer.print("  --no-counts                  Disable discovery of nested/hidden items count\n", .{});
    try writer.print("  --summary-only               Show only entry counts and module statistics\n", .{});
    try writer.print("  --file <path>                Directly index a specific file instead of FQN\n", .{});

    try writer.print("\nDiscovery & Deep Inspection:\n", .{});
    try writer.print("  --search <keywords>          Search FQN, comments, and values for keywords\n", .{});
    try writer.print("  --probe <fqn>                Extract source code and implementation lineage for an FQN\n", .{});
    try writer.print("  --depth-probe <N> <fqn>      Atomic specification of depth and probe target\n", .{});
    try writer.print("  --flagged-deprecated         Extract all symbols with 'deprecated' semantics\n", .{});
    try writer.print("  --show-private               Force display of all internal structure elements (fields/tags)\n", .{});

    try writer.print("\nLibrary Module Groups (--group-<name> or --groups <ID>):\n", .{});
    try writer.print("  1:  core                     Core fundamentals (mem, heap, atomic, Thread, meta)\n", .{});
    try writer.print("  2:  data-struct              Data structures (ArrayList, HashMap, Deque, enums)\n", .{});
    try writer.print("  3:  system-io                System and IO (fs, net, http, Uri, process, time)\n", .{});
    try writer.print("  4:  data-proc                Data processing (json, zon, fmt, ascii, unicode, zip)\n", .{});
    try writer.print("  5:  math-sec                 Math and Security (math, Random, sort, crypto, hash)\n", .{});
    try writer.print("  6:  dev-tool                 Developer tools (zig, Build, debug, log, testing)\n", .{});
    try writer.print("  7:  agnostic-spec            Platform agnostic specs (dwarf, Target, gpu)\n", .{});
    try writer.print("  8:  os-linux-posix           Linux / POSIX primitives (os.linux, posix, elf)\n", .{});
    try writer.print("  9:  os-windows               Windows specifics (os.windows, coff, pdb)\n", .{});
    try writer.print("  10: os-macos                 macOS specifics (macho)\n", .{});
    try writer.print("  11: os-other                 Other targets (Wasm, Wasi, UEFI, Plan9)\n", .{});
    try writer.print("  12: external-c-tool          C library & external tool interfaces (C, valgrind)\n", .{});
    try writer.print("      app-dev-core             General application logic (Merged Groups 1-7)\n", .{});

    try writer.print("\nFilter & Group Options:\n", .{});
    try writer.print("  --groups <ID1,ID2,...>       Enable module groups by numeric ID (1-12)\n", .{});
    try writer.print("  --group-<N>                  Enable a specific group by ID (e.g., --group-1)\n", .{});
    try writer.print("  --group-<name>               Enable a specific group by name (e.g., --group-core)\n", .{});
    try writer.print("  --filter-layer1              Exclude OS/C primitives (std.c, std.os, std.posix)\n", .{});
    try writer.print("  --only-layer1                Restrict output to OS-specific primitives\n", .{});
    try writer.print("  --top-level                  Show only primary namespace members (depth 1)\n", .{});
    try writer.print("  --top-level-sub              Include sub-containers of top-level members (depth 2)\n", .{});

    try writer.print("\nProject Analysis & Graphing (Experimental / Roadmap):\n", .{});
    try writer.print("  --mode project               Project-local symbol indexing\n", .{});
    try writer.print("  --include <file1,...>        Whitelist specific files for project analysis\n", .{});
    try writer.print("  --exclude <file1,...>        Blacklist specific files/directories\n", .{});
    try writer.print("  --skeleton                   Generate logic hierarchy and call graph skeleton\n", .{});
    try writer.print("  --users <symbol>             List all references and call sites of a symbol\n", .{});
    try writer.print("  --trace-up <symbol>          Trace logic propagation from target to entry points\n", .{});

    try writer.print("\nGlobal:\n", .{});
    try writer.print("  --help, -h                   Show this structural help message\n", .{});

    try writer.print("\nOfficial Resources:\n", .{});
    try writer.print("  zig help                     Check standard toolchain commands (build, test, env, etc.)\n", .{});
    try writer.print("  https://ziglang.org/         Zig Programming Language official portal\n", .{});
}

pub fn printHelpja(writer: *Writer, target_version: []const u8, std_path: []const u8) !void {
    const zind_version = build_options.version;
    const target_zig = std.fmt.comptimePrint("{d}.{d}.{d}", .{
        builtin.zig_version.major,
        builtin.zig_version.minor,
        builtin.zig_version.patch,
    });

    try writer.print("【Zind - Zig 構造的 API インデクサー】\n\n", .{});
    try writer.print("使用法: zind [stdパス] [オプション]\n\n", .{});

    try writer.print("実行環境ステータス:\n", .{});
    try writer.print("  解析エンジン   : {s} (ターゲット: Zig {s})\n", .{ zind_version, target_zig });
    try writer.print("  解析ライブラリ : {s}\n", .{std_path});
    try writer.print("  対象バージョン : {s}\n\n", .{target_version});

    try writer.print("基本設定:\n", .{});
    try writer.print("  --mode lib|library           標準ライブラリ解析モード (デフォルト)\n", .{});
    try writer.print("  --std-path <path>            Zig 標準ライブラリのパスを明示的に指定\n", .{});
    try writer.print("  --root-path <path>           プロジェクトのルートディレクトリを指定\n", .{});
    try writer.print("  --lang <en|ja>               ヘルプ等の表示言語を設定します。識別子との整合性のため、解析出力は英語のまま維持されます。\n", .{});
    try writer.print("  --color <auto|always|none>   ANSI カラー出力設定 (デフォルト: auto)\n", .{});
    try writer.print("  --no-color                   ANSI カラー出力を強制的に無効化\n", .{});
    try writer.print("  --debug                      パフォーマンスおよびバッファメトリクスを表示\n", .{});
    try writer.print("  --libc                       条件付きコンパイルの評価に libc リンクを想定\n", .{});
    try writer.print("  --no-libc                    条件付きコンパイルの評価に libc 非リンクを想定\n", .{});
    try writer.print("  --target-os <os>             ターゲット OS を上書きして条件付き定義を評価\n", .{});
    try writer.print("  --target-arch <arch>         ターゲット Arch を上書きして条件付き定義を評価\n", .{});

    try writer.print("\nライブラリ・インデックスおよび意味論解析:\n", .{});
    try writer.print("  --scope <namespace>          特定の名前空間に解析を制限 (例: std.mem,std.fs)\n", .{});
    try writer.print("  --depth <N|unlimited>        再帰の深さを指定 (0 は対象のみ)\n", .{});
    try writer.print("  --depth-scope <N> <scope>    特定のスコープに対して原子的に深さを指定\n", .{});
    try writer.print("  --merge                      複数のスキャンタスクを単一のソート済みインデックスに統合\n", .{});
    try writer.print("  --no-counts                  ネスト/隠し項目のカウントを無効化\n", .{});
    try writer.print("  --summary-only               エントリ数とモジュール統計のみを表示\n", .{});
    try writer.print("  --file <path>                FQN ロジックに従わず、特定のファイルを直接インデックス\n", .{});

    try writer.print("\n探索および詳細調査:\n", .{});
    try writer.print("  --search <keywords>          FQN、コメント、定数値からキーワードを検索\n", .{});
    try writer.print("  --probe <fqn>                指定した FQN のソースコードと実装系譜を抽出\n", .{});
    try writer.print("  --depth-probe <N> <fqn>      プローブ対象と再帰深度を原子的に指定\n", .{});
    try writer.print("  --flagged-deprecated         'deprecated'（非推奨）セマンティクスを持つシンボルを抽出\n", .{});
    try writer.print("  --show-private               内部実装要素（フィールド/タグ）を強制的に表示\n", .{});

    try writer.print("\nライブラリ・モジュールグループ (--group-<名前> または --groups <ID>):\n", .{});
    try writer.print("  1:  core                     基本要素 (mem, heap, atomic, Thread, meta)\n", .{});
    try writer.print("  2:  data-struct              データ構造 (ArrayList, HashMap, Deque, enums)\n", .{});
    try writer.print("  3:  system-io                システムおよび I/O (fs, net, http, Uri, process, time)\n", .{});
    try writer.print("  4:  data-proc                データ処理 (json, zon, fmt, ascii, unicode, zip)\n", .{});
    try writer.print("  5:  math-sec                 数学およびセキュリティ (math, Random, sort, crypto, hash)\n", .{});
    try writer.print("  6:  dev-tool                 開発者ツール (zig, Build, debug, log, testing)\n", .{});
    try writer.print("  7:  agnostic-spec            プラットフォーム非依存仕様 (dwarf, Target, gpu)\n", .{});
    try writer.print("  8:  os-linux-posix           Linux / POSIX プリミティブ (os.linux, posix, elf)\n", .{});
    try writer.print("  9:  os-windows               Windows 固有定義 (os.windows, coff, pdb)\n", .{});
    try writer.print("  10: os-macos                 macOS 固有定義 (macho)\n", .{});
    try writer.print("  11: os-other                 その他のターゲット (Wasm, Wasi, UEFI, Plan9)\n", .{});
    try writer.print("  12: external-c-tool          C ライブラリおよび外部ツールインターフェース (C, valgrind)\n", .{});
    try writer.print("      app-dev-core             一般的なアプリケーションロジック (グループ 1-7 の統合)\n", .{});

    try writer.print("\nフィルタおよびグループオプション:\n", .{});
    try writer.print("  --groups <ID1,ID2,...>       数値 ID (1-12) でモジュールグループを有効化\n", .{});
    try writer.print("  --group-<N>                  指定した ID のグループを有効化 (例: --group-1)\n", .{});
    try writer.print("  --group-<name>               指定した名前のグループを有効化 (例: --group-core)\n", .{});
    try writer.print("  --filter-layer1              低レイヤプリミティブ (std.c, std.os, std.posix) を除外\n", .{});
    try writer.print("  --only-layer1                OS 固有のプリミティブのみを出力制限\n", .{});
    try writer.print("  --top-level                  主要な名前空間メンバのみを表示 (深さ 1)\n", .{});
    try writer.print("  --top-level-sub              主要メンバとその子要素を含めて表示 (深さ 2)\n", .{});

    try writer.print("\nプロジェクト解析およびグラフ表示 (実験的 / ロードマップ):\n", .{});
    try writer.print("  --mode project               プロジェクトローカルのシンボルインデックス作成\n", .{});
    try writer.print("  --include <file1,...>        プロジェクト解析の対象ホワイトリストを指定\n", .{});
    try writer.print("  --exclude <file1,...>        解析対象から除外するファイル/ディレクトリを指定\n", .{});
    try writer.print("  --skeleton                   論理階層とコールグラフのスケルトンを生成\n", .{});
    try writer.print("  --users <symbol>             特定シンボルのすべての参照および呼び出し箇所をリスト化\n", .{});
    try writer.print("  --trace-up <symbol>          ターゲットからエントリポイントへのロジック伝播を追跡\n", .{});

    try writer.print("\nグローバル:\n", .{});
    try writer.print("  --help, -h                   この構造化ヘルプメッセージを表示\n", .{});

    try writer.print("\n公式リソース:\n", .{});
    try writer.print("  zig help                     標準ツールチェイン (build, test, env 等) のヘルプ確認\n", .{});
    try writer.print("  https://ziglang.org/         Zig プログラミング言語 公式ポータル\n", .{});
}

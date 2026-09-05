<!--
SPDX-FileCopyrightText: 2026 TSUKUMO Akito <tsukumoakito99@duck.com>
SPDX-License-Identifier: MIT
-->

# Zind 取扱説明書 (v1.0.8 / 2026-09-06)

**Zind** - Zig 向け動的構造的 API インデクサー

---

## 書式

`zind [STD_PATH] [オプション...]`

---

## 説明

**Zind** は、急速に進化する Zig プログラミング言語のために設計された、構造的 API インデックスツールです。静的なドキュメント生成ツールとは異なり、Zind はシステムにインストールされている実際の Zig ソースコードに対して直接 **AST（抽象構文木）解析** を行います。

### 汎用的なバージョンサポート

Zind は Zig 0.16.0 に最適化されていますが、**本質的にはバージョンに依存しません。** ソースコードから直接「唯一の真実（Ground Truth）」を抽出する性質上、提供されたあらゆる Zig バージョンの論理構造を正しく可視化します。

---

## 戦略的ナビゲーション（ヒント）

Zig 標準ライブラリを効率的に探索するために、以下のワークフローを推奨します：

1. **全体像の把握**: まず `--top-level` または `--top-level-sub` を使用して、現在の Zig 環境における名前空間全体の階層構造を可視化します。
2. **詳細へのドリルダウン**: 構造を特定したら、`--scope`、`--depth-scope`、`--probe`、`--depth-probe` を組み合わせて対象を絞り込み、特定の API の仕組み、ロジックの流れ、および実装の詳細を調査します。
3. **バージョン移行の補助**: `--flagged-deprecated` を使用して、バージョンアップに伴う破壊的変更やロジックの変遷を特定します。プローブ（調査）フラグと併用することで、推奨される代替案を深く掘り下げる。
4. **バージョン固有のグループ設定**: プリセットされた `--groups` は Zig 0.16.0（および 0.15.2 への内部マッピング）に厳格に最適化されています。それ以外のバージョンでは定義が乖離する可能性があるため、常にトップレベル探索フラグを使用して、そのバージョン固有の論理レイアウトを確認することを推奨します。

---

## 公式リソースとツールチェイン

Zind は詳細なソースコード解析に特化していますが、開発ワークフローの管理には公式ツールチェインを使用してください。

* **ツールチェインの操作**: `build`, `run`, `test`, `env` などの内蔵コマンドについては `zig help` を実行して確認してください。Zind は環境検出のために `zig env` の出力を利用します。
* **言語仕様**: 言語リファレンスやリリースノートについては、公式サイト [https://ziglang.org/](https://ziglang.org/) を参照してください。

---

## 基本オプション（グローバル）

| オプション | 説明 |
| :--- | :--- |
| `--std-path <path>` | Zig 標準ライブラリのパスを明示的に指定します。省略した場合、PATH 内の `zig` バイナリから自動検出します。 |
| `--lang <en\|ja>` | ヘルプ等の表示言語を設定します。識別子との整合性のため、解析出力は英語のまま維持されます。 |
| `--root-path <path>` | プロジェクトを認識した解析を行うための、ルートディレクトリを指定します。 |
| `--color <auto\|always\|none>` | ANSI カラー出力の設定。デフォルトは `auto` です。 |
| `--debug` | 解析エンジンのパフォーマンスおよびバッファメトリクスレポートを有効にします。 |
| `--libc`, `--no-libc` | C ライブラリとのリンクの有無をシミュレートし、条件付きコンパイルパスを評価します。 |
| `--target-os <os>` | ターゲット OS を上書きし、特定のプラットフォーム向けの定義をシミュレートします。 |
| `--target-arch <arch>` | ターゲットアーキテクチャを上書きし、特定の CPU 向けの定義をシミュレートします。 |

---

## ライブラリインデックスとフィルタ

| オプション | 説明 |
| :--- | :--- |
| `--scope <namespaces>` | 解析対象を特定の名前空間（例: `std.mem,std.fs`）に制限します。 |
| `--depth <N\|unlimited>` | 再帰の深さを指定します。`0` は対象のみ、`unlimited` は全メンバを走査します。 |
| `--depth-scope <N> <scope>` | 特定のスコープに対して、原子的に深さ制限を適用します。 |
| `--merge` | 複数のスキャンタスクを統合し、単一のソートされたインデックスとして出力します。 |
| `--no-counts` | ネストされた項目や隠し項目のカウントを無効化し、処理を高速化します。 |
| `--summary-only` | 個別のシンボルを表示せず、エントリ数とモジュール統計のみを表示します。 |
| `--file <path>` | FQN ロジックに従わず、特定のファイルを直接インデックスします。 |
| `--show-private` | 内部実装要素（非公開のフィールドやタグ）を強制的に表示します。 |

---

## 探索と詳細調査

| オプション | 説明 |
| :--- | :--- |
| `--search <keywords>` | FQN、ドキュメントコメント、および定数値に対してキーワード検索を行います。深度は自動的に `unlimited` になります。 |
| `--probe <fqn>` | 指定された FQN の完全な実装系譜と、実際のソースコードスニペットを抽出します。デフォルト深度は 1 です。 |
| `--depth-probe <N> <fqn>` | 再帰深度とプローブ対象を原子的に指定します。 |
| `--flagged-deprecated` | 'Deprecated'（非推奨）セマンティクスが付与されたシンボルのみを抽出します。 |

---

## モジュールグループ

Zig 0.16.0 / 0.15.2 に最適化されたプリセットグループです。`--group-<ID>` または `--group-<name>` で使用します。

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
    `一般的なアプリケーションロジック（グループ 1-7 の統合）`

---

## フィルタオプション

| オプション | 説明 |
| :--- | :--- |
| `--filter-layer1` | 低レイヤの OS/C プリミティブ（`std.c`, `std.os`, `std.posix`）を除外します。 |
| `--only-layer1` | OS 固有のプリミティブのみに出力を制限します。 |
| `--top-level` | `--depth-scope 1 std` のエイリアス。主要なメンバのみを表示します。 |
| `--top-level-sub` | `--depth-scope 2 std` のエイリアス。主要メンバとその子要素を含めます。 |

---

## 実験的機能・ロードマップ (EXPERIMENTAL / ROADMAP)

以下のオプションは Project Mode の開発ロードマップに含まれています。`v1.0.0` においては、これらを使用すると警告が表示され、実装待ちのため解析が中断されます。

| オプション | 説明 |
| :--- | :--- |
| `--mode project` | 標準ライブラリではなく、プロジェクトローカルのシンボルをインデックスします。 |
| `--include <file1,...>` | プロジェクト解析の対象となるファイルをホワイトリスト指定します。 |
| `--exclude <file1,...>` | 解析対象から特定のファイルやディレクトリを除外します。 |
| `--skeleton` | 論理階層およびコールグラフのスケルトンを生成します。 |
| `--users <symbol>` | 特定シンボルのすべての参照および呼び出し箇所をリスト化します。 |
| `--trace-up <symbol>` | ターゲットからエントリポイントへのロジック伝播を追跡します。 |

---

## 出力表記の読み方

Zind は、実装のセマンティクスを伝えるために高密度な表記を使用します：

* **実装系譜の追跡 (`>>>`)**: `A = B >>> C` は、シンボル A が B のエイリアスであり、最終的に C で定義されていることを示します。
* **条件付き定義 (`[...]`)**: `std.posix.Stat [native_os is linux]` は、その定義が有効になるために必要な環境条件を明示します。
* **隠し項目のカウント**:
    * `(+n items)`: 深度設定により省略された公開（pub）メンバの数。
    * `{+n items}`: 非公開の内部メンバの数。構造の複雑さの指標となります。

---

## 実行例

**現在の Zig 環境の全体構造を解析する:**

```bash
zind --top-level
```

**標準ライブラリ内から ArrayList に関連する全シンボルを検索する:**

```bash
zind --search ArrayList
```

**std.ArrayList の直下のメンバを深さ 2 で詳細調査（プローブ）する:**

```bash
zind --depth-probe 2 std.ArrayList
```

**現在の環境における非推奨 API を一覧表示する:**

```bash
zind --flagged-deprecated
```

---

## 終了ステータス

* **0**: 成功
* **1**: 致命的なエラー（パス未検出、引数エラー、AST 解析の失敗など）

---

## 著者

TSUKUMO Akito <tsukumoakito99@duck.com>

## 関連項目

* **公式リポジトリ (Codeberg)**: [https://codeberg.org/tsukumoakito/zind](https://codeberg.org/tsukumoakito/zind)

* **ミラーリポジトリ (GitHub)**: [https://github.com/tsukumoakito/zind](https://github.com/tsukumoakito/zind)

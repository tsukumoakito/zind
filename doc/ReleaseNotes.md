<!--
SPDX-FileCopyrightText: 2026 TSUKUMO Akito <tsukumoakito99@duck.com>
SPDX-License-Identifier: MIT
-->

# v1.0.10: Precision AST Indexing

We are pleased to announce the release of **Zind v1.0.10**.
This version marks a significant strategic milestone, ensuring that the ground truth of Zig 0.16.0 is accessible to all developers.

> **Note:** This release (v1.0.10) includes a critical documentation patch for the manual pages, updating versioning and metadata alongside the major license transition.

## 🚀 Major Change: Transition to MIT License

To foster wider adoption and integrate seamlessly into the modern Zig ecosystem, we have transitioned the license from AGPL-3.0 to the **MIT License**. Zind is now free for both personal and commercial use, empowering developers to build high-performance infrastructure without legal barriers.

## ✨ Key Features of Zind

- **Deep Semantic Analysis**: Tracks complex alias chains (`A = B >>> C`) across the entire Zig standard library.
- **Zig 0.16.0 Native**: Built specifically for the latest language specifications, ensuring compatibility with new syntax and VTable structures.
- **Zero-Waste Architecture**: High-speed indexing with a low memory footprint using optimized string pooling and LRU caching.
- **Anti-"Vibe Coding"**: Provides definitive source-of-truth mapping, helping developers move beyond AI-generated guesses to actual implementation logic.

## 📦 Installation

For Arch Linux users, Zind is available via **AUR**:

```bash
yay -S zind
```

## 🛠 Support & Consulting

If you require professional integration, or custom feature development, please reach out via: [tsukumoakito99@duck.com](mailto:tsukumoakito99@duck.com)

---

**Zind v1.0.10 リリースのお知らせ**

このバージョンは、Zig 0.16.0 のソースコード解析をすべての開発者にとってより身近なものにするための、重要な戦略的マイルストーンとなります。

> **補足:** 本リリース(v1.0.10)では、ライセンス移行に伴うマニュアル内のバージョン表記および日付の修正（パッチ）が含まれています。

## 🚀 主要な変更：MITライセンスへの移行

より広範な普及とモダンなZigエコシステムへの統合を促進するため、ライセンスを AGPL-3.0 から **MITライセンス** へ変更しました。個人・商用を問わず、法的な障壁なくZindをインフラやツールに組み込むことが可能になりました。

## ✨ Zind の主な特徴

- **高度な意味解析**: Zig標準ライブラリ全体の複雑なエイリアス連鎖 (`A = B >>> C`) を正確に追跡。
- **Zig 0.16.0 ネイティブ**: 最新の言語仕様に特化して構築されており、新しい構文やVTable構造にも完全対応。
- **究極の効率性**: 最適化されたストリングプールとLRUキャッシュにより、低メモリフットプリントで高速なインデックスを実現。
- **「Vibe Coding」への対抗**: AIによる不確かな推測を排し、実装ロジックに基づいた「唯一の真実（Ground Truth）」を提供。

## 📦 インストール

Arch Linuxユーザーの方は、**AUR** から導入可能です：

```bash
yay -S zind
```

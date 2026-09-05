# zind Makefile
# SPDX-FileCopyrightText: 2026 TSUKUMO Akito <tsukumoakito99@duck.com>
# SPDX-License-Identifier: MIT

ZIG_VER    ?= 0.16.0
PREFIX     ?= /usr
BINDIR      = $(DESTDIR)$(PREFIX)/bin
MANDIR      = $(DESTDIR)$(PREFIX)/share/man
DOCDIR      = $(DESTDIR)$(PREFIX)/share/doc/zind
LICENSEDIR  = $(DESTDIR)$(PREFIX)/share/licenses/zind

.PHONY: all build check-zig install uninstall clean

all: build

check-zig:
	@ZIG_CURRENT=$$(zig version); \
	case $$ZIG_CURRENT in \
		$(ZIG_VER)*) \
			echo "✅ Zig version $$ZIG_CURRENT detected."; \
			;; \
		*) \
			echo "❌ Error: Current zind version requires Zig $(ZIG_VER)."; \
			echo "   Currently using: $$ZIG_CURRENT."; \
			echo "   Please run your zig package manager such as 'zvm use $(ZIG_VER)' before building."; \
			exit 1; \
			;; \
	esac

build: check-zig
	zig build -Doptimize=ReleaseSafe

install:
	install -Dm755 zig-out/bin/zind "$(BINDIR)/zind"
	install -Dm644 zig-out/share/man/man1/zind.1 "$(MANDIR)/man1/zind.1"
	install -Dm644 zig-out/share/man/ja/man1/zind.1 "$(MANDIR)/ja/man1/zind.1"
	install -Dm644 zig-out/doc/MANUAL.md "$(DOCDIR)/MANUAL.md"
	install -Dm644 zig-out/doc/MANUAL_ja.md "$(DOCDIR)/MANUAL_ja.md"
	install -Dm644 README.md "$(DOCDIR)/README.md"
	install -Dm644 README_ja.md "$(DOCDIR)/README_ja.md"
	install -Dm644 LICENSE "$(LICENSEDIR)/LICENSE"

uninstall:
	rm -f "$(BINDIR)/zind"
	rm -f "$(MANDIR)/man1/zind.1"
	rm -f "$(MANDIR)/ja/man1/zind.1"
	rm -rf "$(DOCDIR)"
	rm -rf "$(LICENSEDIR)"

clean:
	rm -rf zig-out .zig-cache

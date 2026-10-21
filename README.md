# JayMark: Zig-Native Markdown Parser

![jaymark-logo](jaymark-256.png)

> [!TIP]
> Zig 0.17.x Required

- [Features](#tools-&-features)
  - [Parser Features](#parser-features)
- [Caveats](#caveats)
  - [Things I Will Not Support](#things-i-will-not-support)
- [Usage](#usage)

> [!NOTE]
> Github does not support this, but the above Table of Contents can be auto-generated using the
> `{toctree}` directive!

Jaymark is the core Markdown parser from [Zigdown](https://github.com/JacobCrabill/zigdown), split
off into an independent library for modularity. This zero-dependency parser can be used in an
application, used in a CLI, or even embedded in a browser!

> [!WARNING]
> This is not a CommonMark-compliant Markdown parser, nor will it ever be one!

## Features

### Parser Features

- [x] Headers
- [x] Basic text formatting (**Bold**, _italic_, ~strikethrough~)
- [x] Links
- [x] Quote blocks
- [x] Unordered lists
- [x] Ordered lists
- [x] Code blocks, including syntax highlighting using TreeSitter
- [x] Task lists
- [x] Tables
- [x] Autolinks
- [x] GitHub-Flavored Markdown Alerts
- [x] Table of Contents generation

## Caveats

Note that I am **not** planning to implement complete CommonMark specification support, or even full
Markdown support by any definition. Rather, the goal is to support "nicely formatted" Markdown,
making some simplifying assumptions about what constitutes a paragraph vs. a code block, for
example. The "nicely formatted" caveat simplifies the parser somewhat, enabling easier extension for
new features like special warnings, note boxes, and other custom directives.

In addition to my "nicely formatted" caveat, I am also only interested in supporting a very common
subset of all Markdown syntax, and ignoring anything I personally find useless or annoying to parse.

### Things I Will Not Support

- Setext headings
- Thematic breaks
- Indent-based code blocks (as opposed to fenced code blocks)
- Embedded HTML
  - I _might_ change my mind on this one

## Usage

### Building

The current version of Zig this code compiles with is
[0.17.0](https://ziglang.org/download/0.17.0/zig-x86_64-linux-0.17.0.tar.xz). I highly recommend
using the [Zig version manager](https://github.com/tristanisham/zvm) to install and manage various
Zig versions.

### Use in another Zig project

Fetch a specific version; this will update your `build.zig.zon`:

```sh
zig fetch --save https://github.com/JacobCrabill/jaymark/archive/<commit-sha>.tar.gz
```

Import the module in your `build.zig`:

```zig
const jaymark = b.dependency("jaymark", .{ .target = target, .optimize = optimize });
my_exe.root_module.addImport("jaymark", jaymark.module("jaymark"));
```

Use it in your code:

```zig
const jaymark = @import("jaymark");

// Parse to the Markdown syntax tree (returns the root Document block)
const ast = try jaymark.parse(gpa, "# Hello, World!\n");
ast.debugPrint(); // defaults to stderr; see `jaymark.debug.init()`

// Auto-format the document (returns a new heap-allocated string)
const formatted = try jaymark.format(io, gpa, "#   Hello, World!  \n", 90);
try std.testing.expectEqualStrings(" # Hello, World!\n", formatted);
```

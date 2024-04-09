# ZTUI

Libraries for a Zig Terminal User Interface.

This repository is divided into several projects all used to build out tooling for
making Terminal User Interfaces (TUI's) with Zig.

## Sub-Projects

### Tabby

`tabby` is a keyboard event library for handling keyboard events. It implements
the [Kitty Keybaord Protocol](https://sw.kovidgoyal.net/kitty/keyboard-protocol/), with
the exception that the progressive enhancement to report associated text is not supported.
(Keyboard Enhancement 0b1000).

### Tests
Included in this project are various tests and examples used as integration tests for other projects

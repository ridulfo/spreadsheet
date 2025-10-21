# Spreadsheet

A terminal based spreadsheet editor and calculator.

It allows you to quickly perform calculations on a spreadsheet - right in your terminal!

## How-to

### Basic Usage
Open a file: `./spreadsheet sheet.csv` (or without arguments for a new untitled spreadsheet).

**Navigation (normal mode):**
- Move cursor: arrow keys or vim keys (`hjkl`)
- Edit cell: press Enter
- Save: press `s`
- Quit: press `q`

**Editing cells (insert mode):**
- Type your value (integer, text, or formula starting with `=`)
- Press Enter to commit and return to normal mode
- Press ESC to cancel without saving
- Press Backspace to delete characters

**Cell picking (for formulas):**
While in insert mode, press Ctrl+Space to enter picking mode. This lets you visually select cells to insert into your formula:
1. Navigate to the cell you want (arrow keys or `hjkl`)
2. Press Enter once to mark the start of selection
3. For a single cell: press Enter again to insert it (e.g., `A1`)
4. For a range: navigate to the end cell, then press Enter to insert the range (e.g., `A1:B3`)
5. Press ESC to cancel picking and return to editing

## Functional cells
### Parsing
For fun, the parsing of the formulas is done using Odin's own [tokenizer](https://pkg.odin-lang.org/core/odin/tokenizer/) and [parser](https://pkg.odin-lang.org/core/odin/parser/). This means that you are actually writing a subset of Odin that is valid Excel Formula Language.

The parsing is simple, first `=` is stripped from the beginning of the expression. Then the expression is tokenized and fed into the parser. This produces an abstract syntax tree ([specified here](https://pkg.odin-lang.org/core/odin/ast/)), which is then evaluated using simple an AST walking interpreter.

How are ranges parsed, `A1:B3` isn't valid Odin?
To solve this, a pre-processing step is first performed to the formula, turning `A1:B3` into `range(A1, B3)`.

### Dependencies
Functional cells are evaluated in topological order. Meaning, the dependencies of a cell are evaluated before the dependent cell is evaluated.
In the following example
```
A1: 1
B1: =A1
C1: =B1
```
First B1 is evaluated, then C1.

A hand-rolled topological sort has been implemented for educational purposes, despite Odin having an [implementation in the standard library](https://pkg.odin-lang.org/core/container/topological_sort/).

## Features for MVP
- modal editing
    - [x] normal
    - [x] insert
    - [x] cell label picking
    - [x] visual + copy & paste
- [x] open csv files
- cell types
    - [x] integers
    - [x] formulas
    - [x] strings
    - [x] floats
- calculations
    - [x] evaluate formulas
    - [x] add support for ranges
    - [x] function calling

### Future features (?)
- [ ] undo/redo
- [ ] auto-fill (drag bottom right corner)
- [ ] relative (A1), absolute ($A$1), mixed ($A1, A$1) (needed by auto-fill)
- [ ] only reevaluate dependent cells
- [ ] multi-thread independent evaluation
- [ ] multiple sheets
- [ ] row filtering
- [ ] freeze rows/columns
- [ ] cell formatting (colors, font)
- [ ] cell manual width and height
- [ ] datetime cells
- open excel files
    - [ ] xls
    - [ ] xlsx



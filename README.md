# Spreadsheet

A terminal based spreadsheet editor and calculator.

It allows you to quickly perform calculations on a spreadsheet - right in your terminal!

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

## TODO
- [ ] modal editing
- [ ] add support for ranges
- [ ] add function calling
- [ ] add support for excel files (.xls & .xlsx)
- [ ] add more cell types (strings, dates)
- [ ] only reevaluate dependent cells
- [ ] multi-thread independent evaluation


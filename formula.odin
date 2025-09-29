package main
import "core:c"
import "core:fmt"
import "core:log"
import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:testing"


/* TODO: use Lua for formulas too */

validate_identifier :: proc(identifier: string) -> bool {
	return true
}

identifier_to_coordinates :: proc(identifier: string) -> (row: int, col: int, ok: bool) {
	// TODO: support for longer coordinates AA123
	col = int(identifier[0] - 'A')
	if 0 <= col && col <= 25 do return 0, 0, false
	row_num, parse_ok := strconv.parse_int(identifier[1:])
	if !parse_ok do return 0, 0, false
	row = row_num - 1 // Convert from 1-based to 0-based indexing
	ok = true
	return // Uses named parameters
}

evaluate_cell :: proc(grid: ^Grid, cell: CellFunc) -> (result: int, err: string) {
	assert(cell.formula[0] == '=', "Formula needs to start with a =")
	formula := cell.formula[1:]

	t := tokenizer.Tokenizer{}
	p := parser.Parser{}
	tokenizer.init(&t, formula, "formula")

	// Set up error handlers
	p.err = parser.default_error_handler
	p.warn = parser.default_warning_handler

	file := ast.File {
		src      = formula,
		fullpath = "formula",
	}

	// Parse as expression
	p.file = &file
	tokenizer.init(&p.tok, file.src, file.fullpath, p.err)

	// Initialize parser state
	parser.advance_token(&p)

	// Parse the expression
	expr := parser.parse_expr(&p, false)

	// Traverse and evaluate the AST
	return evaluate_ast_expr(expr, grid)
}

evaluate_ast_expr :: proc(expr: ^ast.Expr, grid: ^Grid) -> (result: int, err: string) {
	if expr == nil do return 0, ""

	#partial switch node in expr.derived {
	case ^ast.Ident:
		// Cell reference like "A2"
		if validate_identifier(node.name) {
			row, col, ok := identifier_to_coordinates(node.name)
			if !ok do return 0, "Failed to convert coordinates"

			// Check bounds
			if row < 0 || row >= grid.rows || col < 0 || col >= grid.cols {
				return 0, "Cell reference out of bounds"
			}

			cell := get_cell(grid, row, col)
			#partial switch c in cell {
			case CellInt:
				return c.value, ""
			case CellFunc:
				// Recursive evaluation
				return evaluate_cell(grid, c)
			case CellEmpty:
				return 0, ""
			case:
				return 0, "Unknown cell type"
			}
		}
		return 0, ""

	case ^ast.Basic_Lit:
		// Numeric literals
		#partial switch node.tok.kind {
		case .Integer:
			value, ok := strconv.parse_int(node.tok.text)
			if ok do return value, ""
		}
		return 0, "Unknown token kind"

	case ^ast.Binary_Expr:
		// Operations like +, -, *, /
		left, error_left := evaluate_ast_expr(node.left, grid)
		right, error_right := evaluate_ast_expr(node.right, grid)

		#partial switch node.op.kind {
		case .Add:
			return left + right, ""
		case .Sub:
			return left - right, ""
		case .Mul:
			return left * right, ""
		case .Quo:
			if right != 0 do return left / right, ""
			return 0, "Cannot divide by 0"
		case .Eq:
			return int(left == right), ""
		case:
			log.error("Unsupported binary operation:", node.op.kind)
			return 0, "Unsupported binary operation"
		}

	case ^ast.Unary_Expr:
		// Unary operations like -x
		operand, error := evaluate_ast_expr(node.expr, grid)
		#partial switch node.op.kind {
		case .Sub:
			return -operand, ""
		case .Add:
			return operand, ""
		case:
			log.error("Unsupported unary operation:", node.op.kind)
			return 0, "Unsupported unary operation"
		}

	case ^ast.Paren_Expr:
		// Parenthesized expressions
		return evaluate_ast_expr(node.expr, grid)

	case ^ast.Call_Expr:
		// Function calls like SUM(A1:A5)
		panic("Function calls not implemented yet")

	case:
		log.error("Unsupported AST node type:", expr.derived)
		panic("Unsupported AST node")
	}
}

evaluate_grid :: proc(grid: ^Grid) {
	for column in 0 ..< grid.cols {
		for row in 0 ..< grid.rows {
			cell := get_cell(grid, row, column)
			func_cell, ok := cell.(CellFunc)
			if !ok do continue

			value, error := evaluate_cell(grid, cell.(CellFunc))
			func_cell.value = value
			func_cell.error = error
			set_cell(grid, row, column, func_cell)
		}
	}}

@(test)
test_one_cell :: proc(t: ^testing.T) {
	grid := new_grid()
	defer delete_grid(grid)
	set_cell(grid, 0, 0, CellInt{value = 1})
	set_cell(grid, 0, 1, CellFunc{value = 0, formula = "=A1+1"})
	result, error := evaluate_cell(grid, get_cell(grid, 0, 1).(CellFunc))

	testing.expect(t, result == 2)
	testing.expect(t, error == "")
}

@(test)
test_binary_ops :: proc(t: ^testing.T) {
	grid := new_grid()
	defer delete_grid(grid)
	set_cell(grid, 0, 0, CellInt{value = 6})
	set_cell(grid, 0, 1, CellInt{value = 3})

	// Addition
	set_cell(grid, 1, 0, CellFunc{formula = "=A1+B1"})
	val, err := evaluate_cell(grid, get_cell(grid, 1, 0).(CellFunc))
	testing.expect(t, val == 9)
	testing.expect(t, err == "")

	// Subtraction
	set_cell(grid, 1, 1, CellFunc{formula = "=A1-B1"})
	val, err = evaluate_cell(grid, get_cell(grid, 1, 1).(CellFunc))
	testing.expect(t, val == 3)
	testing.expect(t, err == "")

	// Multiplication
	set_cell(grid, 1, 2, CellFunc{formula = "=A1*B1"})
	val, err = evaluate_cell(grid, get_cell(grid, 1, 2).(CellFunc))
	testing.expect(t, val == 18)
	testing.expect(t, err == "")

	// Division
	set_cell(grid, 1, 3, CellFunc{formula = "=A1/B1"})
	val, err = evaluate_cell(grid, get_cell(grid, 1, 3).(CellFunc))
	testing.expect(t, val == 2)
	testing.expect(t, err == "")
}

@(test)
test_division_by_zero :: proc(t: ^testing.T) {
	grid := new_grid()
	defer delete_grid(grid)
	set_cell(grid, 0, 0, CellInt{value = 10})
	set_cell(grid, 0, 1, CellInt{value = 0})
	set_cell(grid, 0, 2, CellFunc{formula = "=A1/B1"})

	val, err := evaluate_cell(grid, get_cell(grid, 0, 2).(CellFunc))
	testing.expect(t, val == 0, "Value should default to 0 on div/0")
	testing.expect(t, err != "", "Error should be set on div/0")
}

@(test)
test_unary_ops :: proc(t: ^testing.T) {
	grid := new_grid()
	defer delete_grid(grid)
	set_cell(grid, 0, 0, CellInt{value = 5})

	// Negation
	set_cell(grid, 0, 1, CellFunc{formula = "=-A1"})
	val, err := evaluate_cell(grid, get_cell(grid, 0, 1).(CellFunc))
	testing.expect(t, val == -5)
	testing.expect(t, err == "")

	// Plus (no-op)
	set_cell(grid, 0, 2, CellFunc{formula = "=+A1"})
	val, err = evaluate_cell(grid, get_cell(grid, 0, 2).(CellFunc))
	testing.expect(t, val == 5)
	testing.expect(t, err == "")
}

// TODO: Remove this test when support is added for more cells
@(test)
test_unknown_cell :: proc(t: ^testing.T) {
	grid := new_grid()
	defer delete_grid(grid)
	set_cell(grid, 0, 0, CellFunc{formula = "=Z99"}) // Out of range

	val, err := evaluate_cell(grid, get_cell(grid, 0, 0).(CellFunc))
	testing.expect(t, val == 0)
	testing.expect(t, err != "", "Should return error for bad reference")
}

@(test)
test_parentheses :: proc(t: ^testing.T) {
	grid := new_grid()
	defer delete_grid(grid)
	set_cell(grid, 0, 0, CellInt{value = 2})
	set_cell(grid, 0, 1, CellInt{value = 3})
	set_cell(grid, 0, 2, CellInt{value = 4})

	set_cell(grid, 1, 0, CellFunc{formula = "=(A1+B1)*C1"})
	val, err := evaluate_cell(grid, get_cell(grid, 1, 0).(CellFunc))

	testing.expect(t, val == (2 + 3) * 4)
	testing.expect(t, err == "")
}

@(test)
test_grid :: proc(t: ^testing.T) {
	grid := new_grid()
	defer delete_grid(grid)
	set_cell(grid, 0, 0, CellInt{value = 1})
	set_cell(grid, 0, 1, CellInt{value = 2})
	set_cell(grid, 0, 2, CellFunc{value = 0, formula = "=A1+B1"})
	evaluate_grid(grid)
	cell := get_cell(grid, 0, 2)
	func_cell, is_func_cell := cell.(CellFunc)

	testing.expect(t, is_func_cell, "Should be func cell")
	testing.expect(t, func_cell.value == 3, "Value of func cell should be 3")
	testing.expect(t, func_cell.error == "")
}

@(test)
test_cyclic_dependency :: proc(t: ^testing.T) {
	grid := new_grid()
	defer delete_grid(grid)
	set_cell(grid, 0, 0, CellFunc{value = 0, formula = "=B1"})
	set_cell(grid, 0, 1, CellFunc{value = 0, formula = "=A1"})
	evaluate_grid(grid)
	cell1, is_func_cell1 := get_cell(grid, 0, 0).(CellFunc)
	cell2, is_func_cell2 := get_cell(grid, 0, 1).(CellFunc)

	testing.expect(t, is_func_cell1, "Should be func cell")
	testing.expect(t, is_func_cell2, "Should be func cell")

	testing.expect(t, cell1.value == 0, "Value of func cell should be 0")
	testing.expect(t, cell1.error != "")
	testing.expect(t, cell2.value == 0, "Value of func cell should be 0")
	testing.expect(t, cell2.error != "")
}

@(test)
test_nested_parentheses :: proc(t: ^testing.T) {
	grid := new_grid()
	defer delete_grid(grid)
	set_cell(grid, 0, 0, CellInt{value = 2})
	set_cell(grid, 0, 1, CellInt{value = 3})
	set_cell(grid, 0, 2, CellInt{value = 4})
	set_cell(grid, 0, 3, CellInt{value = 5})

	set_cell(grid, 1, 0, CellFunc{formula = "=((A1+B1)*C1)/D1"})
	val, err := evaluate_cell(grid, get_cell(grid, 1, 0).(CellFunc))

	testing.expect(t, val == ((2 + 3) * 4) / 5)
	testing.expect(t, err == "")

	set_cell(grid, 1, 1, CellFunc{formula = "=(A1+(B1*C1))-D1"})
	val, err = evaluate_cell(grid, get_cell(grid, 1, 1).(CellFunc))

	testing.expect(t, val == (2 + (3 * 4)) - 5)
	testing.expect(t, err == "")
}

@(test)
test_complex_expressions :: proc(t: ^testing.T) {
	grid := new_grid()
	defer delete_grid(grid)
	set_cell(grid, 0, 0, CellInt{value = 10})
	set_cell(grid, 0, 1, CellInt{value = 5})
	set_cell(grid, 0, 2, CellInt{value = 2})

	set_cell(grid, 1, 0, CellFunc{formula = "=A1-B1+C1*2"})
	val, err := evaluate_cell(grid, get_cell(grid, 1, 0).(CellFunc))

	expected := 10 - 5 + 2 * 2 // Should follow operator precedence
	testing.expect(t, val == expected)
	testing.expect(t, err == "")

	set_cell(grid, 1, 1, CellFunc{formula = "=-A1+B1*-C1"})
	val, err = evaluate_cell(grid, get_cell(grid, 1, 1).(CellFunc))

	expected = -10 + 5 * -2
	testing.expect(t, val == expected)
	testing.expect(t, err == "")
}

@(test)
test_operator_precedence :: proc(t: ^testing.T) {
	grid := new_grid()
	defer delete_grid(grid)
	set_cell(grid, 0, 0, CellInt{value = 10})
	set_cell(grid, 0, 1, CellInt{value = 2})
	set_cell(grid, 0, 2, CellInt{value = 3})
	set_cell(grid, 0, 3, CellInt{value = 4})

	set_cell(grid, 1, 0, CellFunc{formula = "=A1+B1*C1"})
	val, err := evaluate_cell(grid, get_cell(grid, 1, 0).(CellFunc))
	testing.expect(t, val == 10 + 2 * 3)
	testing.expect(t, err == "")

	set_cell(grid, 1, 1, CellFunc{formula = "=A1*B1+C1"})
	val, err = evaluate_cell(grid, get_cell(grid, 1, 1).(CellFunc))
	testing.expect(t, val == 10 * 2 + 3)
	testing.expect(t, err == "")

	set_cell(grid, 1, 2, CellFunc{formula = "=A1/B1+C1*D1"})
	val, err = evaluate_cell(grid, get_cell(grid, 1, 2).(CellFunc))
	testing.expect(t, val == 10 / 2 + 3 * 4)
	testing.expect(t, err == "")

	set_cell(grid, 1, 3, CellFunc{formula = "=A1-B1*C1/D1"})
	val, err = evaluate_cell(grid, get_cell(grid, 1, 3).(CellFunc))
	testing.expect(t, val == 10 - (2 * 3) / 4)
	testing.expect(t, err == "")
}

@(test)
test_recursive_formula_evaluation :: proc(t: ^testing.T) {
	grid := new_grid()
	defer delete_grid(grid)

	set_cell(grid, 0, 0, CellInt{value = 5})
	set_cell(grid, 0, 1, CellFunc{formula = "=A1*2"})
	set_cell(grid, 0, 2, CellFunc{formula = "=B1+A1"})
	set_cell(grid, 0, 3, CellFunc{formula = "=C1-B1"})

	val, err := evaluate_cell(grid, get_cell(grid, 0, 1).(CellFunc))
	testing.expect(t, val == 5 * 2)
	testing.expect(t, err == "")

	val, err = evaluate_cell(grid, get_cell(grid, 0, 2).(CellFunc))
	testing.expect(t, val == (5 * 2) + 5)
	testing.expect(t, err == "")

	val, err = evaluate_cell(grid, get_cell(grid, 0, 3).(CellFunc))
	testing.expect(t, val == ((5 * 2) + 5) - (5 * 2))
	testing.expect(t, err == "")

	set_cell(grid, 1, 0, CellFunc{formula = "=D1*C1"})
	val, err = evaluate_cell(grid, get_cell(grid, 1, 0).(CellFunc))
	expected := (((5 * 2) + 5) - (5 * 2)) * ((5 * 2) + 5)
	testing.expect(t, val == expected)
	testing.expect(t, err == "")
}

@(test)
test_literal_numbers :: proc(t: ^testing.T) {
	grid := new_grid()
	defer delete_grid(grid)

	set_cell(grid, 0, 0, CellFunc{formula = "=42"})
	val, err := evaluate_cell(grid, get_cell(grid, 0, 0).(CellFunc))
	testing.expect(t, val == 42)
	testing.expect(t, err == "")

	set_cell(grid, 0, 1, CellFunc{formula = "=0"})
	val, err = evaluate_cell(grid, get_cell(grid, 0, 1).(CellFunc))
	testing.expect(t, val == 0)
	testing.expect(t, err == "")

	set_cell(grid, 0, 2, CellFunc{formula = "=123+456"})
	val, err = evaluate_cell(grid, get_cell(grid, 0, 2).(CellFunc))
	testing.expect(t, val == 123 + 456)
	testing.expect(t, err == "")

	set_cell(grid, 0, 3, CellFunc{formula = "=999*2-1"})
	val, err = evaluate_cell(grid, get_cell(grid, 0, 3).(CellFunc))
	testing.expect(t, val == 999 * 2 - 1)
	testing.expect(t, err == "")

	set_cell(grid, 1, 0, CellFunc{formula = "=10/2"})
	val, err = evaluate_cell(grid, get_cell(grid, 1, 0).(CellFunc))
	testing.expect(t, val == 10 / 2)
	testing.expect(t, err == "")
}

@(test)
test_identifier_to_coordinates :: proc(t: ^testing.T) {
	row, col, ok := identifier_to_coordinates("A1")
	testing.expect(t, row == 0) // A1 -> row 0, col 0
	testing.expect(t, col == 0)
	testing.expect(t, ok == true)

	row, col, ok = identifier_to_coordinates("B5")
	testing.expect(t, row == 4) // B5 -> row 4, col 1
	testing.expect(t, col == 1)
	testing.expect(t, ok == true)

	row, col, ok = identifier_to_coordinates("Z99")
	testing.expect(t, row == 98) // Z99 -> row 98, col 25
	testing.expect(t, col == 25)
	testing.expect(t, ok == true)

	row, col, ok = identifier_to_coordinates("C1")
	testing.expect(t, row == 0) // C1 -> row 0, col 2
	testing.expect(t, col == 2)
	testing.expect(t, ok == true)

	row, col, ok = identifier_to_coordinates("A")
	testing.expect(t, ok == false, "Single letter should fail to parse")

	row, col, ok = identifier_to_coordinates("123")
	testing.expect(t, ok == false, "Number-only identifier should fail")
}

@(test)
test_empty_cells :: proc(t: ^testing.T) {
	grid := new_grid()
	defer delete_grid(grid)

	set_cell(grid, 0, 0, CellFunc{formula = "=A2"})
	val, err := evaluate_cell(grid, get_cell(grid, 0, 0).(CellFunc))
	testing.expect(t, val == 0, "Empty cell should evaluate to 0")
	testing.expect(t, err == "", "Empty cell should not produce error")

	set_cell(grid, 0, 1, CellFunc{formula = "=B2+5"})
	val, err = evaluate_cell(grid, get_cell(grid, 0, 1).(CellFunc))
	testing.expect(t, val == 5, "Empty cell + 5 should equal 5")
	testing.expect(t, err == "")
}

@(test)
test_invalid_formulas :: proc(t: ^testing.T) {
	grid := new_grid()
	defer delete_grid(grid)

	set_cell(grid, 0, 0, CellInt{value = 10})
	set_cell(grid, 0, 1, CellInt{value = 0})

	set_cell(grid, 1, 0, CellFunc{formula = "=A1/B1"})
	val, err := evaluate_cell(grid, get_cell(grid, 1, 0).(CellFunc))
	testing.expect(t, val == 0, "Division by zero should result in 0")
	testing.expect(t, err != "", "Division by zero should produce error")

	set_cell(grid, 1, 1, CellFunc{formula = "=ZZ999"})
	val, err = evaluate_cell(grid, get_cell(grid, 1, 1).(CellFunc))
	testing.expect(t, val == 0, "Out of bounds reference should result in 0")
	testing.expect(t, err != "", "Out of bounds reference should produce error")
}

@(test)
test_mixed_cell_types :: proc(t: ^testing.T) {
	grid := new_grid()
	defer delete_grid(grid)

	set_cell(grid, 0, 0, CellInt{value = 10})
	set_cell(grid, 0, 1, CellFunc{formula = "=A1*2"})
	set_cell(grid, 0, 2, CellEmpty{})

	val, err := evaluate_cell(grid, get_cell(grid, 0, 1).(CellFunc))
	testing.expect(t, val == 20)
	testing.expect(t, err == "")

	set_cell(grid, 1, 0, CellFunc{formula = "=A1+B1+C1"})
	val, err = evaluate_cell(grid, get_cell(grid, 1, 0).(CellFunc))
	testing.expect(t, val == 10 + 20 + 0)
	testing.expect(t, err == "")
}

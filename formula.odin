package main
import "core:c"
import "core:container/queue"
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
	if 0 > col || col > 25 do return 0, 0, false
	row_num, parse_ok := strconv.parse_int(identifier[1:])
	if !parse_ok do return 0, 0, false
	row = row_num - 1 // Convert from 1-based to 0-based indexing
	ok = true
	return // Uses named parameters
}

// Turns a column index into a bijective base-26 number label
//
// Also known as Excel-style column labels
// `0 => A`, `1 => B`, `26 => AA`
column_to_column_label :: proc(index: int, allocator := context.allocator) -> string {
	index := index + 1
	buf: [8]u8 // enough for large column indices
	n := 0

	for index > 0 {
		index -= 1
		remainder := index % 26
		buf[n] = u8('A' + remainder)
		n += 1
		index /= 26
	}

	// Reverse the slice because we filled it backwards
	for i in 0 ..< (n / 2) {
		buf[i], buf[n - 1 - i] = buf[n - 1 - i], buf[i]
	}

	// Convert only the initialized part of the buffer
	return strings.clone(string(buf[:n]), allocator)
}

coordinates_to_identifier :: proc(row: int, col: int, allocator := context.allocator) -> string {
	builder: strings.Builder
	strings.builder_init(&builder)
	defer strings.builder_destroy(&builder)

	column := column_to_column_label(col, context.temp_allocator)
	strings.write_string(&builder, column)
	fmt.sbprintf(&builder, "%d", row + 1)

	return strings.clone(strings.to_string(builder), allocator)
}

parse_formula :: proc(formula: string) -> ^ast.Expr {
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
	return parser.parse_expr(&p, false)
}

evaluate_cell :: proc(grid: ^Grid, cell: CellFunc) -> (result: int, err: string) {
	assert(cell.formula[0] == '=', "Formula needs to start with a =")
	formula := cell.formula[1:]

	// Use temp allocator only for AST parsing to avoid leaks
	expr: ^ast.Expr
	{
		prev_allocator := context.allocator
		context.allocator = context.temp_allocator
		defer context.allocator = prev_allocator

		expr = parse_formula(formula)
	}

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

find_deps :: proc(grid: ^Grid) -> map[string][dynamic]string {
	rec_find :: proc(node: ^ast.Node, collect_deps: ^[dynamic]string) {
		#partial switch node in node.derived {
		case ^ast.Ident:
			if validate_identifier(node.name) {
				append(collect_deps, node.name)
			}
		case ^ast.Binary_Expr:
			rec_find(node.left, collect_deps)
			rec_find(node.right, collect_deps)
		case ^ast.Unary_Expr:
			rec_find(node.expr, collect_deps)
		case ^ast.Paren_Expr:
			rec_find(node.expr, collect_deps)
		case ^ast.Call_Expr:
			// Function calls like SUM(A1:A5)
			panic("Function calls not implemented yet")
		case:
			log.error("Unsupported AST node type:", node)
			panic("Unsupported AST node")
		}
	}

	graph := make(map[string][dynamic]string)

	for row in 0 ..< grid.rows {
		for column in 0 ..< grid.cols {
			func_cell := get_cell(grid, row, column).(CellFunc) or_continue
			all_deps := make([dynamic]string)
			formula := func_cell.formula[1:] // Strip the leading '='

			// Use temp allocator for AST parsing to avoid leaks
			{
				prev_allocator := context.allocator
				context.allocator = context.temp_allocator
				defer context.allocator = prev_allocator

				expr: ^ast.Node = parse_formula(formula)
				rec_find(expr, &all_deps)
			}

			graph[coordinates_to_identifier(row, column)] = all_deps
		}
	}
	return graph
}


topological_sort :: proc(deps: ^map[string][dynamic]string) -> ([dynamic]string, bool) {
	// Uses Kahn’s algorithm
	//
	// Use core:container/topological_sort if this is too slow. Hand rolled this to learn.
	//
	// Terminology:
	// A-->B: A is the dependency, B is the dependent
	//
	// 1. reverse the dependency map from dependent-->dependency to
	// dependency-->dependent. This will be used to easily update in-degree
	// 2. Initialize the queue with all nodes that do not have any
	// dependencies (i.e in-degree == 0)
	// 3. Pop the first queue element, add it to the order, decrease all its dependent's in-degree
	// 4. Repeat 3 while there are elements in the queue
	// 5. If at the end the length of the `order` isn't the same as the
	// total number of nodes, then there was a cycle.

	// This will be returned
	order := make([dynamic]string)

	// Number of nodes depending on a node
	indegree := make(map[string]int, context.temp_allocator)
	// dependency of --> cell, used to decrement in-degrees efficiently
	rev_deps := make(map[string][dynamic]string, context.temp_allocator)

	// Build indegree and reverse dependency list
	for node, node_dependencies in deps^ {
		if node not_in indegree do indegree[node] = 0

		for dependency in node_dependencies {
			// Ensure dependency is in indegree map (leaf nodes have indegree 0)
			if dependency not_in indegree do indegree[dependency] = 0

			if dependency not_in rev_deps {
				rev_deps[dependency] = make([dynamic]string, context.temp_allocator)
			}

			append(&rev_deps[dependency], strings.clone(node, context.temp_allocator))
			indegree[node] += 1
		}

	}

	node_queue: queue.Queue(string)
	queue.init(&node_queue, allocator = context.temp_allocator)
	for node, val in indegree {
		if val == 0 do queue.push_back(&node_queue, node)
	}

	for queue.len(node_queue) > 0 {
		node := queue.pop_front(&node_queue)
		append(&order, node)
		for dependant in (rev_deps[node] or_else [dynamic]string{}) {
			indegree[dependant] -= 1
			if indegree[dependant] == 0 {
				queue.push_back(&node_queue, dependant)
			}
		}
	}

	if len(order) != len(indegree) {
		return order, false
	}

	return order, true
}

// Evaluates a grid containing functinal cells
//
// First, an associative array is created keeping Cells --> dependencies.
// Second, the keys of this associative array are topologically sorted in order
// to determine the order that they need to be evaluated.
// Finally, the functions are evaluated in said order and the functional cell's
// value field is updated in-place.
evaluate_grid :: proc(grid: ^Grid) {
	dependencies := find_deps(grid)
	defer {
		for key, value in dependencies {
			delete(key)
			delete(value)
		}
		delete(dependencies)
	}

	order, ok := topological_sort(&dependencies)
	defer delete(order)

	// If there's a cycle, set error on all formula cells
	if !ok {
		for row in 0 ..< grid.rows {
			for column in 0 ..< grid.cols {
				cell := get_cell(grid, row, column)
				if func_cell, is_func := cell.(CellFunc); is_func {
					func_cell.error = "Cyclic dependency detected"
					func_cell.value = 0
					set_cell(grid, row, column, func_cell)
				}
			}
		}
		return
	}

	// Evaluate cells in topological order
	for identifier in order {
		row, col, parse_ok := identifier_to_coordinates(identifier)
		if !parse_ok do continue

		cell := get_cell(grid, row, col)
		if func_cell, is_func := cell.(CellFunc); is_func {
			value, error := evaluate_cell(grid, func_cell)
			func_cell.value = value
			func_cell.error = error
			set_cell(grid, row, col, func_cell)
		}
	}
}

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
test_coordinates_to_identifier :: proc(t: ^testing.T) {
	result1 := coordinates_to_identifier(0, 0, context.temp_allocator)
	testing.expect_value(t, result1, "A1")

	result2 := coordinates_to_identifier(4, 1, context.temp_allocator)
	testing.expect_value(t, result2, "B5")

	result3 := coordinates_to_identifier(98, 25, context.temp_allocator)
	testing.expect_value(t, result3, "Z99")

	result4 := coordinates_to_identifier(0, 2, context.temp_allocator)
	testing.expect_value(t, result4, "C1")
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

@(test)
test_topological_sort :: proc(t: ^testing.T) {
	// B depends on A, C
	// C depends on D
	// A depends on nothing
	// D depends on nothing

	deps: map[string][dynamic]string
	defer {
		for k, v in deps do delete(v)
		delete(deps)
	}
	deps["A"] = [dynamic]string{}
	deps["B"] = [dynamic]string{}
	deps["C"] = [dynamic]string{}
	deps["D"] = [dynamic]string{}
	append(&deps["B"], "A", "C")
	append(&deps["C"], "D")

	order, ok := topological_sort(&deps)
	defer delete(order)
	testing.expect_value(t, ok, true)

	// Create index lookup to make order deterministic
	index := map[string]int{}
	defer delete(index)
	for v, i in order {
		index[v] = i
	}

	expect_before := proc(t: ^testing.T, index: map[string]int, a, b: string) {
		testing.expect(t, index[a] < index[b], fmt.tprintf("%s should come before %s", a, b))
	}

	// Order constraints (allowing for equivalent valid topological orders)
	expect_before(t, index, "D", "C")
	expect_before(t, index, "A", "B")
	expect_before(t, index, "C", "B")

	// Check all nodes exist
	for name in ([]string{"A", "B", "C", "D"}) {
		_, ok := index[name]
		testing.expect_value(t, ok, true)
	}
}

@(test)
test_topological_sort_complex :: proc(t: ^testing.T) {
	// Graph layout:
	//   A → B → E
	//   A → C → D → E
	//   F → G
	//   H → (no deps)
	//
	// Two independent components: {A,B,C,D,E} and {F,G}, plus isolated H.

	deps: map[string][dynamic]string
	defer {
		for _, v in deps do delete(v)
		delete(deps)
	}

	// Initialize dependency lists
	deps["A"] = [dynamic]string{}
	deps["B"] = [dynamic]string{}
	deps["C"] = [dynamic]string{}
	deps["D"] = [dynamic]string{}
	deps["E"] = [dynamic]string{}
	deps["F"] = [dynamic]string{}
	deps["G"] = [dynamic]string{}
	deps["H"] = [dynamic]string{}

	// Build edges
	append(&deps["B"], "A")
	append(&deps["C"], "A")
	append(&deps["D"], "C")
	append(&deps["E"], "B", "D")
	append(&deps["G"], "F")

	order, ok := topological_sort(&deps)
	defer delete(order)
	testing.expect_value(t, ok, true)

	// Because multiple valid topological orders exist, we test constraints
	index := map[string]int{}
	defer delete(index)
	for v, i in order {
		index[v] = i
	}

	// Dependency order constraints
	expect_before := proc(t: ^testing.T, index: map[string]int, a, b: string) {
		testing.expect(t, index[a] < index[b], fmt.tprintf("%s should come before %s", a, b))
	}

	expect_before(t, index, "A", "B")
	expect_before(t, index, "A", "C")
	expect_before(t, index, "C", "D")
	expect_before(t, index, "B", "E")
	expect_before(t, index, "D", "E")
	expect_before(t, index, "F", "G")

	// H can appear anywhere, but should exist in the order
	found_H := false
	for v, _ in order {
		if v == "H" {
			found_H = true
			break
		}
	}
	testing.expect_value(t, found_H, true)
}

@(test)
test_topological_sort_cycle_detection :: proc(t: ^testing.T) {
	// Create a simple cycle: X → Y → X
	deps: map[string][dynamic]string
	defer {
		for _, v in deps do delete(v)
		delete(deps)
	}

	deps["X"] = [dynamic]string{}
	deps["Y"] = [dynamic]string{}
	append(&deps["Y"], "X")
	append(&deps["X"], "Y")

	_, ok := topological_sort(&deps)
	testing.expect_value(t, ok, false) // Should fail because of cycle
}

@(test)
test_index_to_column :: proc(t: ^testing.T) {
	col1 := column_to_column_label(0, context.temp_allocator)
	col2 := column_to_column_label(1, context.temp_allocator)
	col3 := column_to_column_label(26, context.temp_allocator)
	col4 := column_to_column_label(702, context.temp_allocator)
	col5 := column_to_column_label(703, context.temp_allocator)
	testing.expect_value(t, col1, "A")
	testing.expect_value(t, col2, "B")
	testing.expect_value(t, col3, "AA")
	testing.expect_value(t, col4, "AAA")
	testing.expect_value(t, col5, "AAB")
}

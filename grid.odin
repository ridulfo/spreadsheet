package main
import "core:fmt"
import "core:math"
import "core:strings"


CellInt :: struct {
	value: int,
}

CellEmpty :: struct {}

CellFunc :: struct {
	formula: string,
	value:   int,
}

Cell :: union {
	CellInt,
	CellFunc,
	CellEmpty,
}

// Grid of cells `Grid[row][column]`
Grid :: [dynamic][dynamic]Cell


MIN_GRID_SIZE :: 20

new_grid :: proc(n_rows := MIN_GRID_SIZE, n_columns := MIN_GRID_SIZE) -> Grid {
	grid := make(Grid, n_rows)
	for row in 0 ..< n_rows {
		grid[row] = make([dynamic]Cell, n_columns)
		for col in 0 ..< n_columns do grid[row][col] = CellEmpty{}
	}
	return grid
}


render_state := proc(state: State, grid: Grid) {
	buffer: strings.Builder
	strings.builder_init(&buffer)
	defer strings.builder_destroy(&buffer)

	// Clear screen and move cursor to home
	strings.write_string(&buffer, "\033[2J\033[H")

	grid := clone_grid(grid)
	defer {
		for row in grid do delete(row)
		delete(grid)
	}
	trim_grid(&grid, MIN_GRID_SIZE)

	// Add header
	header := make([dynamic]Cell, len(grid[0]))
	for _, i in header {
		header[i] = CellInt {
			value = i + 1,
		}
	}
	inject_at(&grid, 0, header)

	// Add left legend
	for row_idx in 0 ..< len(grid) {
		inject_at(&grid[row_idx], 0, CellInt{row_idx})
	}

	n_rows, n_columns := len(grid), len(grid[0])
	fmt.printfln("row %d, col %d", n_rows, n_columns)

	// Find the max width of a cell in a column
	column_widths := max_column_widths(&grid, state.cur_row, state.cur_col)
	defer delete(column_widths)

	// Write status line
	fmt.sbprintf(
		&buffer,
		"rows: %d | columns: %d | row: %d | col:%d | file: %s\n",
		n_rows,
		n_columns,
		state.cur_row + 1,
		state.cur_col + 1,
		state.file_path,
	)
	fmt.sbprintln(&buffer)

	strings.write_string(&buffer, "[Cell: ")
	curr_cell := grid[state.cur_row + 1][state.cur_col + 1]
	switch _ in curr_cell {
	case CellInt:
		fmt.sbprintf(&buffer, "%d", curr_cell.(CellInt).value)
	case CellFunc:
		strings.write_string(&buffer, curr_cell.(CellFunc).formula)
	case CellEmpty:
	}


	fmt.sbprintln(&buffer, " ]\n")

	// Write grid
	char_width := 0
	for col_width in column_widths {
		char_width += col_width + 3
	}
	strings.write_string(&buffer, "╔")
	for c in 1 ..< char_width {
		strings.write_string(&buffer, "═")
	}
	strings.write_string(&buffer, "╗")
	fmt.sbprintln(&buffer)

	for row in 0 ..< n_rows {
		for column in 0 ..< n_columns {
			strings.write_string(&buffer, column == 0 ? "║" : "│")
			cell := grid[row][column]

			is_header := row == 0 && column == state.cur_col + 1
			is_legend := column == 0 && row == state.cur_row + 1
			is_cur_cell := column == state.cur_col + 1 && row == state.cur_row + 1
			if (is_cur_cell || is_header || is_legend) {
				strings.write_string(&buffer, "[")
			} else {
				strings.write_string(&buffer, " ")
			}

			switch _ in cell {
			case CellInt:
				as_str := fmt.tprintf("%d", cell.(CellInt).value)
				for _ in 0 ..< (column_widths[column] - len(as_str)) {
					strings.write_string(&buffer, " ")
				}
				strings.write_string(&buffer, as_str)
			case CellFunc:
				as_str: string
				if is_cur_cell do as_str = cell.(CellFunc).formula
				else do as_str = fmt.tprintf("%d", cell.(CellFunc).value)

				for _ in 0 ..< (column_widths[column] - len(as_str)) {
					strings.write_string(&buffer, " ")
				}
				strings.write_string(&buffer, as_str)

			case CellEmpty:
				for _ in 0 ..< (column_widths[column]) {
					strings.write_string(&buffer, " ")
				}
			}

			if (is_cur_cell || is_header || is_legend) {
				strings.write_string(&buffer, "]")
			} else {
				strings.write_string(&buffer, " ")
			}
		}
		strings.write_string(&buffer, "║\n")
	}

	strings.write_string(&buffer, "╚")
	for c in 1 ..< char_width {
		strings.write_string(&buffer, "═")
	}
	strings.write_string(&buffer, "╝\n")
	// Output everything at once
	fmt.print(strings.to_string(buffer))
}

clone_grid :: proc(original: Grid) -> Grid {
	if len(original) == 0 do return make(Grid, 0)

	new_grid := make(Grid, len(original))

	for row_idx in 0 ..< len(original) {
		original_row := original[row_idx]
		new_row := make([dynamic]Cell, len(original_row))

		for col_idx in 0 ..< len(original_row) {
			new_row[col_idx] = original_row[col_idx]
		}

		new_grid[row_idx] = new_row
	}

	return new_grid
}

// Removes all the rows and columns that are all emtpy cells
//
// @param minimum the minimum number of rows and columns
trim_grid :: proc(grid: ^Grid, minimum := 0) {
	if len(grid) == 0 do return

	n_rows, n_columns := len(grid), len(grid[0])

	// Find the last row that has at least one value
	last_row, last_column: int
	for row in 0 ..< n_rows {
		for column in 0 ..< n_columns {
			cell := grid[row][column]
			switch _ in cell {
			case CellInt:
				if column > last_column do last_column = column
				if row > last_row do last_row = row
			case CellFunc:
				if column > last_column do last_column = column
				if row > last_row do last_row = row
			case CellEmpty:
				continue
			}
		}
	}
	for &row in grid {
		resize(&row, max(last_column + 1, minimum))
	}

	resize(&grid^, max(last_row + 1, minimum))
}

max_column_widths :: proc(grid: ^Grid, cur_row: int, cur_col: int) -> []int {
	n_rows, n_columns := len(grid), len(grid[0])

	column_widths := make([]int, n_columns)
	for column in 0 ..< n_columns {
		max_col_width: int = 1 // Min cell width
		for row in 0 ..< n_rows {
			fmt.printfln("row %d, col %d", row, column)
			cell := grid[row][column]
			is_cur_cell := column == cur_col + 1 && row == cur_row + 1
			switch _ in cell {
			case CellInt:
				as_str := fmt.tprintf("%d", cell.(CellInt).value)
				max_col_width = math.max(len(as_str), max_col_width)
			case CellFunc:
				length: int
				if is_cur_cell {
					length = len(cell.(CellFunc).formula)
				} else {
					as_str := fmt.tprintf("%d", cell.(CellFunc).value)
					length = len(as_str)
				}
				max_col_width = math.max(length, max_col_width)
			case CellEmpty:
				continue
			}
		}
		column_widths[column] = max_col_width
	}
	return column_widths
}


compute_grid :: proc(grid: ^Grid) {
	n_rows, n_columns := len(grid), len(grid[0])
	for row in 0 ..< n_rows {
		for column in 0 ..< n_columns {
			cell := grid[row][column]
			switch _ in cell {
			case CellFunc:
				break
			case CellInt:
				continue
			case CellEmpty:
				continue
			}

		}
	}
}

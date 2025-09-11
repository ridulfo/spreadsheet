package main
import "core:fmt"
import "core:strings"

// Grid of cells `Grid[row][column]`
Grid :: [dynamic][dynamic]Cell


CellInt :: struct {
	value: int,
}

CellEmpty :: struct {}

Cell :: union {
	CellInt,
	CellEmpty,
}
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

	// Add right legend
	for row_idx in 0 ..< len(grid) {
		inject_at(&grid[row_idx], 0, CellInt{row_idx})
	}

	n_rows, n_columns := len(grid), len(grid[0])

	// Find out the last row that has at least one value
	// Find the max width of a cell in a column
	column_widths := make([]int, n_columns, context.temp_allocator)
	for column in 0 ..< n_columns {
		longest_as_str: int = 1 // Min cell width
		for row in 0 ..< n_rows {
			cell := grid[row][column]
			#partial switch _ in cell {
			case CellInt:
				as_str := fmt.tprintf("%d", cell.(CellInt).value)
				if len(as_str) > longest_as_str {
					longest_as_str = len(as_str)
				}
			}
		}
		column_widths[column] = longest_as_str
	}

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

	// Write grid
	for row in 0 ..< n_rows {
		for column in 0 ..< n_columns {
			strings.write_string(&buffer, "|")
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
		strings.write_string(&buffer, "|\n")
	}

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

	// Find out the last row that has at least one value
	// Find the max width of a cell in a column
	last_row, last_column: int
	for column in 0 ..< n_columns {
		for row in 0 ..< n_rows {
			cell := grid[row][column]
			#partial switch _ in cell {
			case CellInt:
				if column > last_column do last_column = column
				if row > last_row do last_row = row
			}
		}
	}
	for &row in grid {
		resize(&row, max(last_column + 1, minimum))
	}

	resize(&grid^, max(last_row + 1, minimum))
}

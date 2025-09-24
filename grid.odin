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
Grid :: struct {
	cells:      [dynamic]Cell,
	rows, cols: int,
}

get_cell :: proc(grid: ^Grid, row: int, col: int) -> Cell {
	assert(0 <= row && row <= (grid.rows - 1))
	assert(0 <= col && col <= (grid.cols - 1))
	return grid.cells[grid.cols * row + col]
}
set_cell :: proc(grid: ^Grid, row: int, col: int, value: Cell) {
	assert(0 <= row && row <= (grid.rows - 1))
	assert(0 <= col && col <= (grid.cols - 1))
	grid.cells[grid.cols * row + col] = value
}


MIN_GRID_SIZE :: 20

new_grid :: proc(n_rows := MIN_GRID_SIZE, n_columns := MIN_GRID_SIZE) -> ^Grid {
	grid := new(Grid)
	n_cells := n_rows * n_columns
	grid.rows = n_rows
	grid.cols = n_columns
	grid.cells = make([dynamic]Cell, n_cells)
	for &cell in grid.cells {
		cell = CellEmpty{}
	}
	return grid
}

delete_grid :: proc(grid: ^Grid) {
	delete(grid.cells)
	free(grid)
}

// Inserts a new row at the specified position, optionally with provided cell values.
// All existing rows at and after `at_row` are shifted down by one position.
//
// @param grid: The grid to modify
// @param at_row: The row index where the new row should be inserted (0-based)
// @param row_cells: Optional slice of cells to insert. If nil, inserts empty cells.
//                   If provided, must have exactly `grid.cols` elements.
insert_row :: proc(grid: ^Grid, at_row: int, row_cells: []Cell = nil) {
	assert(0 <= at_row && at_row <= grid.rows)
	if row_cells != nil {
		assert(len(row_cells) == grid.cols)
	}

	new_rows := grid.rows + 1
	new_cells := make([dynamic]Cell, new_rows * grid.cols)

	// Initialize all cells as empty
	for i in 0 ..< len(new_cells) {
		new_cells[i] = CellEmpty{}
	}

	// Copy cells before the insertion point
	for row in 0 ..< at_row {
		for col in 0 ..< grid.cols {
			new_cells[grid.cols * row + col] = get_cell(grid, row, col)
		}
	}

	// Insert the new row
	if row_cells != nil {
		for col in 0 ..< grid.cols {
			new_cells[grid.cols * at_row + col] = row_cells[col]
		}
	}

	// Copy cells after the insertion point (shifted down by one row)
	for row in at_row ..< grid.rows {
		for col in 0 ..< grid.cols {
			new_cells[grid.cols * (row + 1) + col] = get_cell(grid, row, col)
		}
	}

	// Replace the old cells array
	delete(grid.cells)
	grid.cells = new_cells
	grid.rows = new_rows
}

// Inserts a new column at the specified position, optionally with provided cell values.
// All existing columns at and after `at_col` are shifted right by one position.
//
// @param grid: The grid to modify
// @param at_col: The column index where the new column should be inserted (0-based)
// @param col_cells: Optional slice of cells to insert. If nil, inserts empty cells.
//                   If provided, must have exactly `grid.rows` elements.
insert_column :: proc(grid: ^Grid, at_col: int, col_cells: []Cell = nil) {
	assert(0 <= at_col && at_col <= grid.cols)
	if col_cells != nil {
		assert(len(col_cells) == grid.rows)
	}

	new_cols := grid.cols + 1
	new_cells := make([dynamic]Cell, grid.rows * new_cols)

	// Initialize all cells as empty
	for i in 0 ..< len(new_cells) {
		new_cells[i] = CellEmpty{}
	}

	// Copy cells with column insertion
	for row in 0 ..< grid.rows {
		// Copy columns before the insertion point
		for col in 0 ..< at_col {
			new_cells[new_cols * row + col] = get_cell(grid, row, col)
		}

		// Insert the new column cell
		if col_cells != nil {
			new_cells[new_cols * row + at_col] = col_cells[row]
		}

		// Copy columns after the insertion point (shifted right by one column)
		for col in at_col ..< grid.cols {
			new_cells[new_cols * row + (col + 1)] = get_cell(grid, row, col)
		}
	}

	// Replace the old cells array
	delete(grid.cells)
	grid.cells = new_cells
	grid.cols = new_cols
}


render_state :: proc(state: State, grid: ^Grid) {
	buffer: strings.Builder
	strings.builder_init(&buffer)
	defer strings.builder_destroy(&buffer)

	// Clear screen and move cursor to home
	strings.write_string(&buffer, "\033[2J\033[H")

	grid := clone_grid(grid)
	defer {
		delete_grid(grid)
	}
	trim_grid(grid, MIN_GRID_SIZE)

	// Add header
	header := make([]Cell, grid.cols)
	defer delete(header)
	for _, i in header do header[i] = CellInt {
		value = i + 1,
	}
	insert_row(grid, 0, header)

	// Add left legend
	legend := make([]Cell, grid.rows)
	defer delete(legend)
	for _, i in legend do legend[i] = CellInt{i}
	insert_column(grid, 0, legend)

	fmt.printfln("row %d, col %d", grid.rows, grid.cols)

	// Find the max width of a cell in a column
	column_widths := max_column_widths(grid, state.cur_row, state.cur_col)
	defer delete(column_widths)

	// Write status line
	fmt.sbprintf(
		&buffer,
		"rows: %d | columns: %d | row: %d | col:%d | file: %s\n",
		grid.rows,
		grid.cols,
		state.cur_row + 1,
		state.cur_col + 1,
		state.file_path,
	)
	fmt.sbprintln(&buffer)

	strings.write_string(&buffer, "[Cell: ")
	curr_cell := get_cell(grid, state.cur_row + 1, state.cur_col + 1)
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

	for row in 0 ..< grid.rows {
		for column in 0 ..< grid.cols {
			strings.write_string(&buffer, column == 0 ? "║" : "│")
			cell := get_cell(grid, row, column)

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

clone_grid :: proc(original: ^Grid) -> ^Grid {
	new_grid := new_grid(original.rows, original.cols)

	for row_idx in 0 ..< original.rows {
		for col_idx in 0 ..< original.cols {
			value := get_cell(original, row_idx, col_idx)
			set_cell(new_grid, row_idx, col_idx, value)
		}
	}

	return new_grid
}

// Removes all the rows and columns that are all emtpy cells
//
// @param minimum the minimum number of rows and columns
trim_grid :: proc(grid: ^Grid, minimum := 0) {

	// Find the last row that has at least one value
	last_row, last_col: int
	for row_idx in 0 ..< grid.rows {
		for col_idx in 0 ..< grid.cols { 	// TODO: start from last_column
			cell := get_cell(grid, row_idx, col_idx)
			switch _ in cell {
			case CellInt:
				last_col = max(last_col, col_idx)
				last_row = max(last_row, row_idx)
			case CellFunc:
				last_col = max(last_col, col_idx)
				last_row = max(last_row, row_idx)
			case CellEmpty:
				continue
			}
		}
	}

	new_rows := max(last_row + 1, minimum)
	new_cols := max(last_col + 1, minimum)

	if new_rows < grid.rows || new_cols < grid.cols {
		// Create new cells array with trimmed size
		new_cells := make([dynamic]Cell, new_rows * new_cols)
		for i in 0 ..< len(new_cells) {
			new_cells[i] = CellEmpty{}
		}

		// Copy existing data to new layout
		for row_idx in 0 ..< new_rows {
			for col_idx in 0 ..< new_cols {
				if row_idx < grid.rows && col_idx < grid.cols {
					new_cells[new_cols * row_idx + col_idx] = get_cell(grid, row_idx, col_idx)
				}
			}
		}

		// Replace the old cells array
		delete(grid.cells)
		grid.cells = new_cells
		grid.rows = new_rows
		grid.cols = new_cols
	}
}

max_column_widths :: proc(grid: ^Grid, cur_row: int, cur_col: int) -> []int {
	column_widths := make([]int, grid.cols)
	for column in 0 ..< grid.cols {
		max_col_width: int = 1 // Min cell width
		for row in 0 ..< grid.rows {
			cell := get_cell(grid, row, column)
			is_cur_cell := column == cur_col + 1 && row == cur_row + 1
			switch _ in cell {
			case CellInt:
				as_str := fmt.tprintf("%d", cell.(CellInt).value)
				max_col_width = max(len(as_str), max_col_width)
			case CellFunc:
				length: int
				if is_cur_cell {
					length = len(cell.(CellFunc).formula)
				} else {
					as_str := fmt.tprintf("%d", cell.(CellFunc).value)
					length = len(as_str)
				}
				max_col_width = max(length, max_col_width)
			case CellEmpty:
				continue
			}
		}
		column_widths[column] = max_col_width
	}
	return column_widths
}


// compute_grid :: proc(grid: ^Grid) {
// 	n_rows, n_columns := len(grid), len(grid[0])
// 	for row in 0 ..< n_rows {
// 		for column in 0 ..< n_columns {
// 			cell := grid[row][column]
// 			switch _ in cell {
// 			case CellFunc:
// 				break
// 			case CellInt:
// 				continue
// 			case CellEmpty:
// 				continue
// 			}
//
// 		}
// 	}
// }

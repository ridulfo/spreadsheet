package main
import "core:encoding/csv"
import "core:fmt"
import "core:os"
import "core:strconv"

load_data := proc(file_path: string) -> ^Grid {
	handle, err := os.open(file_path)
	if err != nil {
		fmt.eprintfln("Cannot open %s", file_path)
		os.exit(1)
	}

	data, success := os.read_entire_file(file_path)
	defer delete(data)
	if !success {
		fmt.eprintfln("Cannot read %s", file_path)
		os.exit(1)
	}

	r: csv.Reader
	r.trim_leading_space = true
	r.reuse_record = true // Without this you have to delete(record)
	r.reuse_record_buffer = true // Without this you have to delete each of the fields within it
	defer csv.reader_destroy(&r)

	csv.reader_init_with_string(&r, string(data))
	values: [dynamic][dynamic]Cell
	defer {
		for row in values do delete(row)
		delete(values)
	}
	for record, row_idx, err in csv.iterator_next(&r) {
		row := make([dynamic]Cell)
		append(&values, row)
		if err != nil { /* Do something with error */}
		for value, column_idx in record {
			if value == "" do append(&values[row_idx], CellEmpty{})
			else do append(&values[row_idx], CellInt{strconv.atoi(value)})
		}
	}
	last_row := len(values) - 1
	last_col: int
	for row in 0 ..= last_row do last_col = max(last_col, len(values[row]))

	grid := new_grid(last_row + 1, last_col)

	for row_idx in 0 ..= last_row {
		for col_idx in 0 ..< len(values[row_idx]) {
			set_cell(grid, row_idx, col_idx, values[row_idx][col_idx])
		}
	}

	ensure_grid_size(grid, MIN_GRID_SIZE, MIN_GRID_SIZE)
	return grid
}

save_data := proc(grid: ^Grid, file_path: string) {
	handle, err := os.open(file_path, os.O_WRONLY | os.O_CREATE | os.O_TRUNC, 0o644)
	if err != nil {
		fmt.eprintfln("Cannot open %s - Error: %v", file_path, err)
		os.exit(1)
	}
	defer os.close(handle)

	w: csv.Writer
	csv.writer_init(&w, os.stream_from_handle(handle))

	grid_to_save := clone_grid(grid)
	defer delete_grid(grid_to_save)
	trim_empty_cells(grid_to_save, 0, 0)
	for row in 0 ..< grid.rows {
		record := make([]string, grid.cols)
		defer delete(record)

		for column in 0 ..< grid.cols {
			cell := get_cell(grid, row, column)
			switch _ in cell {
			case CellFunc:
				record[column] = cell.(CellFunc).formula
			case CellInt:
				record[column] = fmt.tprintf("%d", cell.(CellInt).value)
			case CellEmpty:
				record[column] = ""
			}
		}
		csv.write(&w, record)
	}
}

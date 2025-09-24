package main
import "core:encoding/csv"
import "core:fmt"
import "core:os"
import "core:strconv"

load_data := proc(file_path: string) -> Grid {
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
	grid: Grid
	for record, row_idx, err in csv.iterator_next(&r) {
		row := make([dynamic]Cell)
		append(&grid, row)
		if err != nil { /* Do something with error */}
		for value, column_idx in record {
			if value == "" do append(&grid[row_idx], CellEmpty{})
			else do append(&grid[row_idx], CellInt{strconv.atoi(value)})
		}
	}
	trim_grid(&grid, 10)
	return grid
}

save_data := proc(grid: Grid, file_path: string) {
	handle, err := os.open(file_path, os.O_WRONLY | os.O_CREATE | os.O_TRUNC, 0o644)
	if err != nil {
		fmt.eprintfln("Cannot open %s - Error: %v", file_path, err)
		os.exit(1)
	}
	defer os.close(handle)

	w: csv.Writer
	csv.writer_init(&w, os.stream_from_handle(handle))

	grid_to_save := clone_grid(grid)
	trim_grid(&grid_to_save)
	n_rows, n_columns := len(grid), len(grid[0])
	for row in 0 ..< n_rows {
		record := make([]string, n_columns)
		defer delete(record)

		for column in 0 ..< n_columns {
			cell := state.grid[row][column]
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

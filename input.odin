package main

import "core:c"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

foreign import libc "system:c"

@(default_calling_convention = "c")
foreign libc {
	system :: proc(command: cstring) -> c.int ---
	popen :: proc(command: cstring, mode: cstring) -> rawptr ---
	pclose :: proc(stream: rawptr) -> c.int ---
	fgets :: proc(str: [^]u8, size: c.int, stream: rawptr) -> [^]u8 ---
}

// Reads a line of text from stdin (exits raw mode temporarily)
enter_value :: proc() -> string {
	exit_raw_mode()
	defer enter_raw_mode()

	buf: [256]u8 = {}
	n, err := os.read(os.stdin, buf[:])
	if err != 0 || n == 0 {
		fmt.eprintfln("Error reading input or EOF")
		os.exit(1)
	}

	end := n > 0 && buf[n - 1] == '\n' ? n - 1 : n
	return strings.clone(string(buf[:end]))
}


// Handles navigation and selection while picking cells for formula references
//
// Uses select_* to track the selection range. `selecting` indicates
// whether we've started selecting. First Enter marks the start position,
// second Enter marks the end and inserts the cell reference (or range) into
// formula_field. Arrow keys navigate while showing the selection. ESC cancels
// and returns cursor to edit cell.
handle_cell_picking :: proc(state: ^State, c: u8) -> bool {
	cur_row, cur_col := state.cur_row, state.cur_col

	if c == 10 {
		// Enter in cell picking mode
		if !state.selected_first {
			// First Enter: mark start of selection
			state.select_row_start = cur_row
			state.select_col_start = cur_col
			state.selected_first = true
		} else {
			// Second Enter: mark end and insert reference
			state.select_row_end = cur_row
			state.select_col_end = cur_col

			// Insert cell reference or range
			start_col := column_to_column_label(state.select_col_start, context.temp_allocator)
			start_row := fmt.tprintf("%d", state.select_row_start + 1)

			if state.select_row_start == state.select_row_end &&
			   state.select_col_start == state.select_col_end {
				// Single cell
				strings.write_string(&state.formula_field, start_col)
				strings.write_string(&state.formula_field, start_row)
			} else {
				// Range
				end_col := column_to_column_label(state.select_col_end, context.temp_allocator)
				end_row := fmt.tprintf("%d", state.select_row_end + 1)
				strings.write_string(&state.formula_field, start_col)
				strings.write_string(&state.formula_field, start_row)
				strings.write_string(&state.formula_field, ":")
				strings.write_string(&state.formula_field, end_col)
				strings.write_string(&state.formula_field, end_row)
			}

			// Exit cell picking mode and restore cursor to editing cell
			state.selecting = false
			state.selected_first = false
			set_cur_cell(state, state.edit_row, state.edit_col)
		}
		return false
	}

	if c == 65 || c == 66 || c == 67 || c == 68 || c == 'h' || c == 'j' || c == 'k' || c == 'l' {
		// Arrow keys move cursor
		switch c {
		case 65, 'k':
			set_cur_cell(state, cur_row - 1, cur_col)
		case 66, 'j':
			if state.cur_row + 1 >= state.grid.rows {
				insert_row(state.grid, state.grid.rows)
			}
			set_cur_cell(state, cur_row + 1, cur_col)
		case 67, 'l':
			if state.cur_col + 1 >= state.grid.cols {
				insert_column(state.grid, state.grid.cols)
			}
			set_cur_cell(state, cur_row, cur_col + 1)
		case 68, 'h':
			set_cur_cell(state, cur_row, cur_col - 1)
		}
	} else if c == 27 {
		// ESC - exit cell picking mode
		state.selecting = false
		state.selected_first = false
		set_cur_cell(state, state.edit_row, state.edit_col)
	} else if c == 91 {
		// '[' character from escape sequences - ignore
	}

	return false
}

// Handles typing, editing, and committing cell values
//
// Delegates to handle_cell_picking when cell_picking is active. Otherwise
// handles text input into formula_field. Enter commits the value by parsing it
// as a formula (starts with =), int, or text, then writes to grid and returns
// to normal mode. Backspace deletes characters. ESC cancels without saving and
// clears formula_field.
handle_insert_mode :: proc(state: ^State, c: u8) -> bool {
	if c == 0 {
		// Control+Space toggles cell picking mode
		state.selecting = !state.selecting
		state.selected_first = false
		return false
	}

	if state.selecting {
		return handle_cell_picking(state, c)
	}

	if c == 10 {
		// Enter - commit the value and exit insert mode
		state.mode = Mode.normal
		set_cur_cell(state, state.edit_row, state.edit_col)
		value := strings.to_string(state.formula_field)

		// Free old cell data if it was a string type
		old_cell := get_cell(state.grid, state.edit_row, state.edit_col)
		switch c in old_cell {
		case CellFunc:
			delete(c.formula) // formula is heap-allocated via strings.clone()
		// Don't delete c.error - it's always a string literal
		case CellText:
			delete(c.value) // value is heap-allocated via strings.clone()
		case CellInt, CellEmpty:
		// No cleanup needed
		}

		if len(value) > 0 && value[0] == '=' {
			set_cell(
				state.grid,
				state.edit_row,
				state.edit_col,
				CellFunc{formula = strings.clone(value)},
			)
		} else {
			parsed_value, ok := strconv.parse_int(value)
			if ok {
				set_cell(state.grid, state.edit_row, state.edit_col, CellInt{value = parsed_value})
			} else {
				set_cell(
					state.grid,
					state.edit_row,
					state.edit_col,
					CellText{value = strings.clone(value)},
				)
			}
		}
		strings.builder_reset(&state.formula_field)
	} else if c == 127 || c == 8 {
		// Backspace - delete last character
		if strings.builder_len(state.formula_field) > 0 {
			strings.pop_rune(&state.formula_field)
		}
	} else if c == 27 {
		// ESC - exit insert mode without saving
		state.mode = Mode.normal
		strings.builder_reset(&state.formula_field)
		set_cur_cell(state, state.edit_row, state.edit_col)
	} else if c == 91 {
		// '[' character from escape sequences - ignore
	} else {
		// Store typed character in formula field
		strings.write_rune(&state.formula_field, rune(c))
	}

	return false
}

// Handles navigation and commands in normal mode
//
// Arrow keys move cursor and auto-expand grid at edges (or trim empty cells
// when moving left/up). Enter switches to insert mode, saves current position
// to edit_row/col, and prepopulates formula_field with the current cell's
// content. 's' opens save dialog, 'q' quits the app.
handle_normal_mode :: proc(state: ^State, c: u8) -> bool {
	cur_row, cur_col := state.cur_row, state.cur_col

	switch c {
	case 'q':
		return true
	case 10:
		// Enter - switch to insert mode
		state.mode = Mode.insert
		state.edit_row = cur_row
		state.edit_col = cur_col

		// Reset and pre-populate formula field with current cell value
		strings.builder_reset(&state.formula_field)
		cell := get_cell(state.grid, cur_row, cur_col)
		switch c in cell {
		case CellFunc:
			strings.write_string(&state.formula_field, c.formula)
		case CellInt:
			fmt.sbprintf(&state.formula_field, "%d", c.value)
		case CellText:
			strings.write_string(&state.formula_field, c.value)
		case CellEmpty:
		// Leave empty
		}
	case 'v':
		state.mode = Mode.visual
		state.selecting = true
		state.select_row_start = cur_row
		state.select_col_start = cur_col
		state.select_row_end = cur_row
		state.select_col_end = cur_col
	case 'p':
		// Paste from clipboard
		paste_from_clipboard(state)
	case 65, 'k':
		set_cur_cell(state, cur_row - 1, cur_col)
		trim_empty_cells(state.grid, state.cur_row, state.cur_col)
	case 66, 'j':
		if state.cur_row + 1 >= state.grid.rows {
			insert_row(state.grid, state.grid.rows)
		}
		set_cur_cell(state, cur_row + 1, cur_col)
	case 67, 'l':
		if state.cur_col + 1 >= state.grid.cols {
			insert_column(state.grid, state.grid.cols)
		}
		set_cur_cell(state, cur_row, cur_col + 1)
	case 68, 'h':
		set_cur_cell(state, cur_row, cur_col - 1)
		trim_empty_cells(state.grid, state.cur_row, state.cur_col)
	case 's':
		for {
			fmt.printfln(
				"Are you sure that you want to save the data to: %s? (Y/n/r=rename)",
				state.file_path,
			)
			c := get_press()
			if c == 'r' || c == 'R' {
				fmt.print("Enter file name: ")
				state.file_path = enter_value()
				continue
			} else if c != 'n' && c != 'N' {
				save_data(state.grid, state.file_path)
				fmt.println("Saved!")
				break
			} else do break
		}
	}

	return false
}

// Pastes from system clipboard (TSV format) starting at current cell
paste_from_clipboard :: proc(state: ^State) {
	// Execute wl-paste and capture output
	pipe := popen("wl-paste", "r")
	if pipe == nil {
		return
	}
	defer pclose(pipe)

	// Read all clipboard data
	clipboard_data: strings.Builder
	strings.builder_init(&clipboard_data)
	defer strings.builder_destroy(&clipboard_data)

	buf: [4096]u8
	for {
		result := fgets(raw_data(buf[:]), c.int(len(buf)), pipe)
		if result == nil {
			break
		}
		line := string(cstring(raw_data(buf[:])))
		strings.write_string(&clipboard_data, line)
	}

	data := strings.to_string(clipboard_data)
	if len(data) == 0 {
		return
	}

	// Parse TSV data and insert into grid
	rows := strings.split(data, "\n", context.temp_allocator)
	start_row := state.cur_row
	start_col := state.cur_col

	for row_data, row_offset in rows {
		if len(row_data) == 0 {
			continue
		}

		cols := strings.split(row_data, "\t", context.temp_allocator)
		target_row := start_row + row_offset

		// Expand grid if needed
		for target_row >= state.grid.rows {
			insert_row(state.grid, state.grid.rows)
		}

		for col_data, col_offset in cols {
			target_col := start_col + col_offset

			// Expand grid if needed
			for target_col >= state.grid.cols {
				insert_column(state.grid, state.grid.cols)
			}

			// Parse and insert cell value
			if len(col_data) > 0 {
				// Try to parse as integer
				if parsed_int, ok := strconv.parse_int(col_data); ok {
					set_cell(state.grid, target_row, target_col, CellInt{value = parsed_int})
				} else {
					// Store as text
					set_cell(state.grid, target_row, target_col, CellText{value = strings.clone(col_data)})
				}
			}
		}
	}
}

// Copies selected cells to system clipboard as TSV
yank_selection :: proc(state: ^State) {
	// Calculate selection bounds
	min_row := min(state.select_row_start, state.select_row_end)
	max_row := max(state.select_row_start, state.select_row_end)
	min_col := min(state.select_col_start, state.select_col_end)
	max_col := max(state.select_col_start, state.select_col_end)

	// Build TSV string
	builder: strings.Builder
	strings.builder_init(&builder)
	defer strings.builder_destroy(&builder)

	for row in min_row ..= max_row {
		for col in min_col ..= max_col {
			cell := get_cell(state.grid, row, col)

			// Convert cell to string value
			switch c in cell {
			case CellInt:
				fmt.sbprintf(&builder, "%d", c.value)
			case CellFunc:
				// For formulas, copy the evaluated value
				fmt.sbprintf(&builder, "%d", c.value)
			case CellText:
				strings.write_string(&builder, c.value)
			case CellEmpty:
				// Empty cell
			}

			// Add tab separator between columns (except last column)
			if col < max_col {
				strings.write_string(&builder, "\t")
			}
		}
		// Add newline between rows (except last row)
		if row < max_row {
			strings.write_string(&builder, "\n")
		}
	}

	// Pipe to wl-copy via shell
	data := strings.to_string(builder)
	cmd := fmt.tprintf("printf '%%s' '%s' | wl-copy", data)
	system(strings.clone_to_cstring(cmd, context.temp_allocator))
}

handle_visual_mode :: proc(state: ^State, c: u8) -> bool {
	cur_row, cur_col := state.cur_row, state.cur_col

	switch c {
	case 10:
		// Enter - exit visual mode, keeping selection
		state.mode = Mode.normal
		state.selecting = false
		state.select_row_end = cur_row
		state.select_col_end = cur_col
	case 'y':
		// Yank (copy) selection to clipboard
		state.select_row_end = cur_row
		state.select_col_end = cur_col
		yank_selection(state)
		state.mode = Mode.normal
		state.selecting = false
	case 'v', 'q':
		// 'v' or 'q' - exit visual mode
		state.mode = Mode.normal
		state.selecting = false
	case 65, 'k':
		// Move up
		set_cur_cell(state, cur_row - 1, cur_col)
		state.select_row_end = state.cur_row
		state.select_col_end = state.cur_col
	case 66, 'j':
		// Move down
		if state.cur_row + 1 >= state.grid.rows {
			insert_row(state.grid, state.grid.rows)
		}
		set_cur_cell(state, cur_row + 1, cur_col)
		state.select_row_end = state.cur_row
		state.select_col_end = state.cur_col
	case 67, 'l':
		// Move right
		if state.cur_col + 1 >= state.grid.cols {
			insert_column(state.grid, state.grid.cols)
		}
		set_cur_cell(state, cur_row, cur_col + 1)
		state.select_row_end = state.cur_row
		state.select_col_end = state.cur_col
	case 68, 'h':
		// Move left
		set_cur_cell(state, cur_row, cur_col - 1)
		state.select_row_end = state.cur_row
		state.select_col_end = state.cur_col
	case 27, 91:
		// ESC and '[' character from escape sequences - ignore
		// (these are part of arrow key sequences, not standalone commands)
	}

	return false
}

// Routes keypresses to the appropriate mode handler
//
// Checks current mode and delegates to the corresponding handler. Returns true
// if the app should quit (propagated from mode handlers).
handle_keypress :: proc(state: ^State, c: u8) -> bool {
	switch state.mode {
	case .normal:
		return handle_normal_mode(state, c)
	case .insert:
		return handle_insert_mode(state, c)
	case .visual:
		return handle_visual_mode(state, c)
	}
	return false
}

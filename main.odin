package main

import "core:bufio"
import "core:flags"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strconv"
import "core:strings"

Mode :: enum {
	normal, // Default navigation
	insert, // Writing value or formula
	visual, // For selecting
}

// The whole application's state
//
// Having all the state one place and rendering the whole state is that the
// code becomes much easier to reason about. Every action by the user just
// mutates the state.
State :: struct {
	// Current cell
	cur_row, cur_col:                 int,

	// Used when selecting a cell or a range
	select_row_start, select_row_end: int,
	select_col_start, select_col_end: int,
	selecting, selected_first:        bool,

	// Cell being edited (saved when entering insert mode)
	edit_row, edit_col:               int,

	// The data
	grid:                             ^Grid,

	// Path to the file currently being edited
	file_path:                        string,

	// Editing mode
	mode:                             Mode,

	// String to show in formula
	formula_field:                    strings.Builder,
}


state := State{}

// Helper function to set the current cell
set_cur_cell :: proc(state: ^State, row, col: int) {
	state.cur_row = min(max(row, 0), state.grid.rows - 1)
	state.cur_col = min(max(col, 0), state.grid.cols - 1)
	cell := get_cell(state.grid, state.cur_row, state.cur_col)
}


main :: proc() {
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	// https://github.com/odin-lang/Odin/blob/master/core/flags/example/example.odin
	Options :: struct {
		input_file: string `args:"pos=0" usage:"Input file."`,
	}
	opt: Options
	style: flags.Parsing_Style = .Odin
	flags.parse_or_exit(&opt, os.args, style)


	if opt.input_file != "" {
		state.grid = load_data(opt.input_file)
		state.file_path = opt.input_file
	} else {
		state.grid = new_grid()
		state.file_path = "untitled.csv"
	}

	defer {
		delete_grid(state.grid)
	}

	strings.builder_init(&state.formula_field)
	defer strings.builder_destroy(&state.formula_field)

	enter_raw_mode()
	defer exit_raw_mode()

	set_cur_cell(&state, 0, 0)
	evaluate_grid(state.grid)

	should_exit := false
	for {
		render_state(state, state.grid)
		c := get_press()
		should_exit = handle_keypress(&state, c)
		if should_exit do break
		evaluate_grid(state.grid)
	}
}

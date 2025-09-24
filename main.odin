package main

import "core:bufio"
import "core:flags"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:strconv"

None :: struct {}

State :: struct {
	cur_col, cur_row: int,
	grid:             ^Grid,
	file_path:        string,
}

state := State{}


enter_value := proc() -> string {
	exit_raw_mode()
	buf: [256]u8 = {}
	n, err := os.read(os.stdin, buf[:])
	if err != 0 || n == 0 {
		fmt.eprintfln("Error reading input or EOF")
		os.exit(1)
	}
	enter_raw_mode()

	end := n
	if n > 0 && buf[n - 1] == '\n' {
		end = n - 1
	}

	result := make([]u8, end)
	copy(result, buf[:end])
	return string(result)
}

handle_keypress := proc(c: u8) -> bool {
	switch c {
	case 'q':
		return true
	case 65:
		fallthrough
	case 'k':
		state.cur_row = min(max(state.cur_row - 1, 0), state.grid.rows - 1)
	case 66:
		fallthrough
	case 'j':
		state.cur_row = min(max(state.cur_row + 1, 0), state.grid.rows - 1)
	case 67:
		fallthrough
	case 'l':
		state.cur_col = min(max(state.cur_col + 1, 0), state.grid.cols - 1)
	case 68:
		fallthrough
	case 'h':
		state.cur_col = min(max(state.cur_col - 1, 0), state.grid.cols - 1)
	case 10:
		// Enter
		fmt.print("Enter value: ")
		value := enter_value()
		if len(value) > 0 && value[0] == '=' {
			set_cell(state.grid, state.cur_row, state.cur_col, CellFunc{formula = value})
		} else {
			set_cell(
				state.grid,
				state.cur_row,
				state.cur_col,
				CellInt{value = strconv.atoi(value)},
			)
		}
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
				continue // Go back to prompt
			} else if c != 'n' && c != 'N' {
				save_data(state.grid, state.file_path)
				fmt.println("Saved!")
				break
			} else do break
		}
	}
	return false
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

	enter_raw_mode()
	defer exit_raw_mode()
	should_exit := false
	for (!should_exit) {
		render_state(state, state.grid)
		c := get_press()
		should_exit = handle_keypress(c)
	}

}

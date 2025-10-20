package main

import "core:fmt"
import "core:strings"
import "core:testing"

// Helper to create a test state
make_test_state :: proc() -> State {
	state := State{}
	state.grid = new_grid()
	state.file_path = "test.csv"
	state.mode = .normal
	state.selecting = false
	state.selected_first = false
	strings.builder_init(&state.formula_field)
	return state
}

// Helper to cleanup test state
cleanup_test_state :: proc(state: ^State) {
	delete_grid(state.grid)
	strings.builder_destroy(&state.formula_field)
}

@(test)
test_enter_insert_mode :: proc(t: ^testing.T) {
	state := make_test_state()
	defer cleanup_test_state(&state)

	set_cur_cell(&state, 0, 0)
	testing.expect_value(t, state.mode, Mode.normal)

	// Press Enter to enter insert mode
	should_exit := handle_keypress(&state, 10)

	testing.expect_value(t, should_exit, false)
	testing.expect_value(t, state.mode, Mode.insert)
	testing.expect_value(t, state.edit_row, 0)
	testing.expect_value(t, state.edit_col, 0)
}

@(test)
test_insert_number :: proc(t: ^testing.T) {
	state := make_test_state()
	defer cleanup_test_state(&state)

	set_cur_cell(&state, 0, 0)

	// Enter insert mode
	handle_keypress(&state, 10) // Enter
	testing.expect_value(t, state.mode, Mode.insert)

	// Type "42"
	handle_keypress(&state, '4')
	handle_keypress(&state, '2')

	// Check formula field contains "42"
	field_content := strings.to_string(state.formula_field)
	testing.expect_value(t, field_content, "42")

	// Press Enter to commit
	handle_keypress(&state, 10)

	testing.expect_value(t, state.mode, Mode.normal)

	// Check the cell contains the integer 42
	cell := get_cell(state.grid, 0, 0)
	cell_f64, ok := cell.(CellNumeric)
	testing.expect(t, ok, "Cell should be CellInt")
	testing.expect_value(t, cell_f64.value, 42)
}

@(test)
test_insert_formula :: proc(t: ^testing.T) {
	state := make_test_state()
	defer cleanup_test_state(&state)

	set_cur_cell(&state, 0, 0)

	// Enter insert mode
	handle_keypress(&state, 10) // Enter

	// Type "=5+3"
	handle_keypress(&state, '=')
	handle_keypress(&state, '5')
	handle_keypress(&state, '+')
	handle_keypress(&state, '3')

	// Press Enter to commit
	handle_keypress(&state, 10)

	// Check the cell is a formula
	cell := get_cell(state.grid, 0, 0)
	cell_func, ok := cell.(CellFunc)
	testing.expect(t, ok, "Cell should be CellFunc")
	testing.expect_value(t, cell_func.formula, "=5+3")

	// Evaluate and check result
	evaluate_grid(state.grid)
	cell_after := get_cell(state.grid, 0, 0)
	cell_func_after := cell_after.(CellFunc)
	testing.expect_value(t, cell_func_after.value, 8)
}

@(test)
test_insert_text :: proc(t: ^testing.T) {
	state := make_test_state()
	defer cleanup_test_state(&state)

	set_cur_cell(&state, 0, 0)

	// Enter insert mode
	handle_keypress(&state, 10) // Enter

	// Type "hello"
	handle_keypress(&state, 'h')
	handle_keypress(&state, 'e')
	handle_keypress(&state, 'l')
	handle_keypress(&state, 'l')
	handle_keypress(&state, 'o')

	// Press Enter to commit
	handle_keypress(&state, 10)

	// Check the cell contains text
	cell := get_cell(state.grid, 0, 0)
	cell_text, ok := cell.(CellText)
	testing.expect(t, ok, "Cell should be CellText")
	testing.expect_value(t, cell_text.value, "hello")
}

@(test)
test_navigation :: proc(t: ^testing.T) {
	state := make_test_state()
	defer cleanup_test_state(&state)

	set_cur_cell(&state, 5, 5)
	testing.expect_value(t, state.cur_row, 5)
	testing.expect_value(t, state.cur_col, 5)

	// Move up (k or arrow up = 65)
	handle_keypress(&state, 'k')
	testing.expect_value(t, state.cur_row, 4)
	testing.expect_value(t, state.cur_col, 5)

	// Move down (j or arrow down = 66)
	handle_keypress(&state, 'j')
	testing.expect_value(t, state.cur_row, 5)
	testing.expect_value(t, state.cur_col, 5)

	// Move right (l or arrow right = 67)
	handle_keypress(&state, 'l')
	testing.expect_value(t, state.cur_row, 5)
	testing.expect_value(t, state.cur_col, 6)

	// Move left (h or arrow left = 68)
	handle_keypress(&state, 'h')
	testing.expect_value(t, state.cur_row, 5)
	testing.expect_value(t, state.cur_col, 5)
}

@(test)
test_escape_from_insert_mode :: proc(t: ^testing.T) {
	state := make_test_state()
	defer cleanup_test_state(&state)

	set_cur_cell(&state, 0, 0)

	// Enter insert mode
	handle_keypress(&state, 10)
	testing.expect_value(t, state.mode, Mode.insert)

	// Type something
	handle_keypress(&state, 'a')
	handle_keypress(&state, 'b')
	handle_keypress(&state, 'c')

	// Press ESC (27) to cancel
	handle_keypress(&state, 27)

	testing.expect_value(t, state.mode, Mode.normal)

	// Cell should still be empty
	cell := get_cell(state.grid, 0, 0)
	_, ok := cell.(CellEmpty)
	testing.expect(t, ok, "Cell should still be empty after ESC")
}

@(test)
test_backspace_in_insert_mode :: proc(t: ^testing.T) {
	state := make_test_state()
	defer cleanup_test_state(&state)

	set_cur_cell(&state, 0, 0)

	// Enter insert mode
	handle_keypress(&state, 10)

	// Type "abc"
	handle_keypress(&state, 'a')
	handle_keypress(&state, 'b')
	handle_keypress(&state, 'c')

	field := strings.to_string(state.formula_field)
	testing.expect_value(t, field, "abc")

	// Backspace (127)
	handle_keypress(&state, 127)

	field = strings.to_string(state.formula_field)
	testing.expect_value(t, field, "ab")

	// Backspace again
	handle_keypress(&state, 127)

	field = strings.to_string(state.formula_field)
	testing.expect_value(t, field, "a")
}

@(test)
test_edit_existing_cell :: proc(t: ^testing.T) {
	state := make_test_state()
	defer cleanup_test_state(&state)

	// Set up initial cell value
	set_cell(state.grid, 0, 0, CellNumeric{value = 100})
	set_cur_cell(&state, 0, 0)

	// Enter insert mode - should populate formula field with current value
	handle_keypress(&state, 10)

	field := strings.to_string(state.formula_field)
	testing.expect_value(t, field, "100")

	// Clear and type new value
	for i in 0 ..< 3 {
		handle_keypress(&state, 127) // Backspace 3 times
	}
	handle_keypress(&state, '2')
	handle_keypress(&state, '0')
	handle_keypress(&state, '0')

	// Commit
	handle_keypress(&state, 10)

	// Check updated value
	cell := get_cell(state.grid, 0, 0)
	cell_f64, ok := cell.(CellNumeric)
	testing.expect(t, ok, "Cell should be CellInt")
	testing.expect_value(t, cell_f64.value, 200)
}

@(test)
test_formula_evaluation_after_input :: proc(t: ^testing.T) {
	state := make_test_state()
	defer cleanup_test_state(&state)

	// Insert value in A1
	set_cur_cell(&state, 0, 0)
	handle_keypress(&state, 10) // Enter insert mode
	handle_keypress(&state, '1')
	handle_keypress(&state, '0')
	handle_keypress(&state, 10) // Commit

	// Move to B1 and insert formula =A1*2
	set_cur_cell(&state, 0, 1)
	handle_keypress(&state, 10) // Enter insert mode
	handle_keypress(&state, '=')
	handle_keypress(&state, 'A')
	handle_keypress(&state, '1')
	handle_keypress(&state, '*')
	handle_keypress(&state, '2')
	handle_keypress(&state, 10) // Commit

	// Evaluate grid
	evaluate_grid(state.grid)

	// Check A1
	cell_a1 := get_cell(state.grid, 0, 0)
	cell_a1_f64 := cell_a1.(CellNumeric)
	testing.expect_value(t, cell_a1_f64.value, 10)

	// Check B1 formula result
	cell_b1 := get_cell(state.grid, 0, 1)
	cell_b1_func := cell_b1.(CellFunc)
	testing.expect_value(t, cell_b1_func.formula, "=A1*2")
	testing.expect_value(t, cell_b1_func.value, 20)
}

@(test)
test_quit_command :: proc(t: ^testing.T) {
	state := make_test_state()
	defer cleanup_test_state(&state)

	set_cur_cell(&state, 0, 0)

	// Press 'q' in normal mode
	should_exit := handle_keypress(&state, 'q')

	testing.expect_value(t, should_exit, true)
}

@(test)
test_bounds_checking :: proc(t: ^testing.T) {
	state := make_test_state()
	defer cleanup_test_state(&state)

	// Try to go to negative position
	set_cur_cell(&state, -5, -5)

	// Should be clamped to 0, 0
	testing.expect_value(t, state.cur_row, 0)
	testing.expect_value(t, state.cur_col, 0)

	// Try to go beyond grid size
	set_cur_cell(&state, 1000, 1000)

	// Should be clamped to max valid position
	testing.expect_value(t, state.cur_row, state.grid.rows - 1)
	testing.expect_value(t, state.cur_col, state.grid.cols - 1)
}

@(test)
test_dependent_formulas_chain :: proc(t: ^testing.T) {
	state := make_test_state()
	defer cleanup_test_state(&state)

	// Create a chain of dependent formulas:
	// A1 = 10
	// A2 = A1 + 5      (should be 15)
	// A3 = A2 * 2      (should be 30)
	// A4 = A3 - A1     (should be 20)
	// A5 = A4 + A2     (should be 35)

	// Insert A1 = 10
	set_cur_cell(&state, 0, 0)
	handle_keypress(&state, 10) // Enter insert mode
	handle_keypress(&state, '1')
	handle_keypress(&state, '0')
	handle_keypress(&state, 10) // Commit

	// Move down and insert A2 = A1 + 5
	handle_keypress(&state, 'j')
	handle_keypress(&state, 10) // Enter insert mode
	handle_keypress(&state, '=')
	handle_keypress(&state, 'A')
	handle_keypress(&state, '1')
	handle_keypress(&state, '+')
	handle_keypress(&state, '5')
	handle_keypress(&state, 10) // Commit

	// Move down and insert A3 = A2 * 2
	handle_keypress(&state, 'j')
	handle_keypress(&state, 10) // Enter insert mode
	handle_keypress(&state, '=')
	handle_keypress(&state, 'A')
	handle_keypress(&state, '2')
	handle_keypress(&state, '*')
	handle_keypress(&state, '2')
	handle_keypress(&state, 10) // Commit

	// Move down and insert A4 = A3 - A1
	handle_keypress(&state, 'j')
	handle_keypress(&state, 10) // Enter insert mode
	handle_keypress(&state, '=')
	handle_keypress(&state, 'A')
	handle_keypress(&state, '3')
	handle_keypress(&state, '-')
	handle_keypress(&state, 'A')
	handle_keypress(&state, '1')
	handle_keypress(&state, 10) // Commit

	// Move down and insert A5 = A4 + A2
	handle_keypress(&state, 'j')
	handle_keypress(&state, 10) // Enter insert mode
	handle_keypress(&state, '=')
	handle_keypress(&state, 'A')
	handle_keypress(&state, '4')
	handle_keypress(&state, '+')
	handle_keypress(&state, 'A')
	handle_keypress(&state, '2')
	handle_keypress(&state, 10) // Commit

	// Evaluate the grid - tests topological sorting
	evaluate_grid(state.grid)

	// Verify A1 = 10
	cell_a1 := get_cell(state.grid, 0, 0)
	cell_a1_f64 := cell_a1.(CellNumeric)
	testing.expect_value(t, cell_a1_f64.value, 10)

	// Verify A2 = 15
	cell_a2 := get_cell(state.grid, 1, 0)
	cell_a2_func := cell_a2.(CellFunc)
	testing.expect_value(t, cell_a2_func.formula, "=A1+5")
	testing.expect_value(t, cell_a2_func.value, 15)

	// Verify A3 = 30
	cell_a3 := get_cell(state.grid, 2, 0)
	cell_a3_func := cell_a3.(CellFunc)
	testing.expect_value(t, cell_a3_func.formula, "=A2*2")
	testing.expect_value(t, cell_a3_func.value, 30)

	// Verify A4 = 20
	cell_a4 := get_cell(state.grid, 3, 0)
	cell_a4_func := cell_a4.(CellFunc)
	testing.expect_value(t, cell_a4_func.formula, "=A3-A1")
	testing.expect_value(t, cell_a4_func.value, 20)

	// Verify A5 = 35
	cell_a5 := get_cell(state.grid, 4, 0)
	cell_a5_func := cell_a5.(CellFunc)
	testing.expect_value(t, cell_a5_func.formula, "=A4+A2")
	testing.expect_value(t, cell_a5_func.value, 35)
}

@(test)
test_enter_visual_mode :: proc(t: ^testing.T) {
	state := make_test_state()
	defer cleanup_test_state(&state)

	set_cur_cell(&state, 2, 2)
	testing.expect_value(t, state.mode, Mode.normal)

	// Press 'v' to enter visual mode
	handle_keypress(&state, 'v')

	testing.expect_value(t, state.mode, Mode.visual)
	testing.expect_value(t, state.selecting, true)
	testing.expect_value(t, state.select_row_start, 2)
	testing.expect_value(t, state.select_col_start, 2)
	testing.expect_value(t, state.select_row_end, 2)
	testing.expect_value(t, state.select_col_end, 2)
}

@(test)
test_visual_mode_navigation :: proc(t: ^testing.T) {
	state := make_test_state()
	defer cleanup_test_state(&state)

	set_cur_cell(&state, 2, 2)

	// Enter visual mode
	handle_keypress(&state, 'v')
	testing.expect_value(t, state.mode, Mode.visual)

	// Move right
	handle_keypress(&state, 'l')
	testing.expect_value(t, state.cur_row, 2)
	testing.expect_value(t, state.cur_col, 3)
	testing.expect_value(t, state.select_row_end, 2)
	testing.expect_value(t, state.select_col_end, 3)

	// Move down
	handle_keypress(&state, 'j')
	testing.expect_value(t, state.cur_row, 3)
	testing.expect_value(t, state.cur_col, 3)
	testing.expect_value(t, state.select_row_end, 3)
	testing.expect_value(t, state.select_col_end, 3)

	// Selection start should remain unchanged
	testing.expect_value(t, state.select_row_start, 2)
	testing.expect_value(t, state.select_col_start, 2)
}

@(test)
test_visual_mode_exit_with_v :: proc(t: ^testing.T) {
	state := make_test_state()
	defer cleanup_test_state(&state)

	set_cur_cell(&state, 2, 2)

	// Enter visual mode
	handle_keypress(&state, 'v')
	testing.expect_value(t, state.mode, Mode.visual)

	// Exit visual mode with 'v'
	handle_keypress(&state, 'v')
	testing.expect_value(t, state.mode, Mode.normal)
	testing.expect_value(t, state.selecting, false)
}

@(test)
test_visual_mode_exit_with_enter :: proc(t: ^testing.T) {
	state := make_test_state()
	defer cleanup_test_state(&state)

	set_cur_cell(&state, 2, 2)

	// Enter visual mode
	handle_keypress(&state, 'v')
	testing.expect_value(t, state.mode, Mode.visual)

	// Move to create selection
	handle_keypress(&state, 'l')
	handle_keypress(&state, 'j')

	// Exit with Enter
	handle_keypress(&state, 10) // Enter
	testing.expect_value(t, state.mode, Mode.normal)
	testing.expect_value(t, state.selecting, false)
	// Selection bounds should be saved
	testing.expect_value(t, state.select_row_start, 2)
	testing.expect_value(t, state.select_col_start, 2)
	testing.expect_value(t, state.select_row_end, 3)
	testing.expect_value(t, state.select_col_end, 3)
}

@(test)
test_visual_mode_arrow_keys :: proc(t: ^testing.T) {
	state := make_test_state()
	defer cleanup_test_state(&state)

	set_cur_cell(&state, 5, 5)

	// Enter visual mode
	handle_keypress(&state, 'v')

	// Test arrow up (65)
	handle_keypress(&state, 27) // ESC
	handle_keypress(&state, 91) // [
	handle_keypress(&state, 65) // A (up arrow)
	testing.expect_value(t, state.cur_row, 4)

	// Test arrow down (66)
	handle_keypress(&state, 27) // ESC
	handle_keypress(&state, 91) // [
	handle_keypress(&state, 66) // B (down arrow)
	testing.expect_value(t, state.cur_row, 5)

	// Test arrow right (67)
	handle_keypress(&state, 27) // ESC
	handle_keypress(&state, 91) // [
	handle_keypress(&state, 67) // C (right arrow)
	testing.expect_value(t, state.cur_col, 6)

	// Test arrow left (68)
	handle_keypress(&state, 27) // ESC
	handle_keypress(&state, 91) // [
	handle_keypress(&state, 68) // D (left arrow)
	testing.expect_value(t, state.cur_col, 5)

	// Should still be in visual mode
	testing.expect_value(t, state.mode, Mode.visual)
}

@(test)
test_visual_mode_yank_exits :: proc(t: ^testing.T) {
	state := make_test_state()
	defer cleanup_test_state(&state)

	set_cur_cell(&state, 0, 0)

	// Enter visual mode
	handle_keypress(&state, 'v')
	testing.expect_value(t, state.mode, Mode.visual)

	// Press 'y' to yank (copy)
	handle_keypress(&state, 'y')

	// Should have exited visual mode
	testing.expect_value(t, state.mode, Mode.normal)
	testing.expect_value(t, state.selecting, false)
}

@(test)
test_cell_picking_initialization :: proc(t: ^testing.T) {
	state := make_test_state()
	defer cleanup_test_state(&state)

	// Navigate to cell 2,2
	set_cur_cell(&state, 2, 2)
	testing.expect_value(t, state.cur_row, 2)
	testing.expect_value(t, state.cur_col, 2)

	// Enter insert mode
	handle_keypress(&state, 10) // Enter
	testing.expect_value(t, state.mode, Mode.insert)
	testing.expect_value(t, state.edit_row, 2)
	testing.expect_value(t, state.edit_col, 2)

	// Current cursor should still be at 2,2
	testing.expect_value(t, state.cur_row, 2)
	testing.expect_value(t, state.cur_col, 2)

	// Press Control+Space to enter cell picking mode
	handle_keypress(&state, 0)
	testing.expect_value(t, state.selecting, true)
	testing.expect_value(t, state.selected_first, false)

	// Selection start should be initialized to current position (2,2)
	testing.expect_value(t, state.select_row_start, 2)
	testing.expect_value(t, state.select_col_start, 2)
}

@(test)
test_cell_picking_full_workflow :: proc(t: ^testing.T) {
	state := make_test_state()
	defer cleanup_test_state(&state)

	// Navigate to cell 2,2
	set_cur_cell(&state, 2, 2)

	// Enter insert mode
	handle_keypress(&state, 10) // Enter
	testing.expect_value(t, state.mode, Mode.insert)

	// Type "=" to start a formula
	handle_keypress(&state, '=')
	field := strings.to_string(state.formula_field)
	testing.expect_value(t, field, "=")

	// Press Control+Space to enter cell picking mode
	handle_keypress(&state, 0)
	testing.expect_value(t, state.selecting, true)

	// Selection start should be at current position (2,2)
	testing.expect_value(t, state.select_row_start, 2)
	testing.expect_value(t, state.select_col_start, 2)

	// Move up once (should be at 1,2)
	handle_keypress(&state, 'k')
	testing.expect_value(t, state.cur_row, 1)
	testing.expect_value(t, state.cur_col, 2)

	// Move left once (should be at 1,1)
	handle_keypress(&state, 'h')
	testing.expect_value(t, state.cur_row, 1)
	testing.expect_value(t, state.cur_col, 1)

	// Press Enter to mark the start of selection
	handle_keypress(&state, 10)
	testing.expect_value(t, state.selected_first, true)
	testing.expect_value(t, state.select_row_start, 1)
	testing.expect_value(t, state.select_col_start, 1)

	// Move right twice (should be at 1,3)
	handle_keypress(&state, 'l')
	handle_keypress(&state, 'l')
	testing.expect_value(t, state.cur_row, 1)
	testing.expect_value(t, state.cur_col, 3)

	// Move down once (should be at 2,3)
	handle_keypress(&state, 'j')
	testing.expect_value(t, state.cur_row, 2)
	testing.expect_value(t, state.cur_col, 3)

	// Press Enter to mark the end and insert the range
	handle_keypress(&state, 10)
	testing.expect_value(t, state.selecting, false)
	testing.expect_value(t, state.selected_first, false)

	// Should have returned to edit cell (2,2)
	testing.expect_value(t, state.cur_row, 2)
	testing.expect_value(t, state.cur_col, 2)

	// Formula field should now contain "=B2:D3"
	field = strings.to_string(state.formula_field)
	testing.expect_value(t, field, "=B2:D3")
}

@(test)
test_cell_picking_arrow_keys :: proc(t: ^testing.T) {
	state := make_test_state()
	defer cleanup_test_state(&state)

	set_cur_cell(&state, 5, 5)

	// Enter insert mode
	handle_keypress(&state, 10)
	testing.expect_value(t, state.mode, Mode.insert)

	// Press Control+Space to enter cell picking mode
	handle_keypress(&state, 0)
	testing.expect_value(t, state.selecting, true)

	// Simulate up arrow: ESC [ A
	handle_keypress(&state, 27) // ESC
	handle_keypress(&state, 91) // [
	handle_keypress(&state, 65) // A (up)

	// Should still be in cell picking mode and moved up
	testing.expect_value(t, state.selecting, true)
	testing.expect_value(t, state.cur_row, 4)
	testing.expect_value(t, state.cur_col, 5)

	// Simulate left arrow: ESC [ D
	handle_keypress(&state, 27) // ESC
	handle_keypress(&state, 91) // [
	handle_keypress(&state, 68) // D (left)

	// Should still be in cell picking mode and moved left
	testing.expect_value(t, state.selecting, true)
	testing.expect_value(t, state.cur_row, 4)
	testing.expect_value(t, state.cur_col, 4)
}

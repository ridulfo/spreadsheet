package main
import "core:strings"
import "core:testing"

// SUM function - sums all cells in a range
func_sum :: proc(grid: ^Grid, range_str: string) -> (result: f64, err: string) {
	// Parse range like "A1B5" (no colon)
	start, end, ok := parse_range(range_str, context.temp_allocator)
	if !ok {
		return 0, "Invalid range format"
	}

	start_row, start_col, ok1 := identifier_to_coordinates(start)
	end_row, end_col, ok2 := identifier_to_coordinates(end)

	if !ok1 || !ok2 {
		return 0, "Invalid range coordinates"
	}

	// Sum all values in the range
	sum := f64(0)
	for row in start_row ..= end_row {
		for col in start_col ..= end_col {
			if row < 0 || row >= grid.rows || col < 0 || col >= grid.cols {
				return 0, "Range out of bounds"
			}

			cell := get_cell(grid, row, col)
			switch c in cell {
			case CellNumeric:
				sum += c.value
			case CellFunc:
				sum += c.value
			case CellEmpty:
				// Empty cells contribute 0
			case CellText:
				return 0, "Cannot sum text cell"
			}
		}
	}
	return sum, ""
}

// PRODUCT function - multiplies all cells in a range
func_product :: proc(grid: ^Grid, range_str: string) -> (result: f64, err: string) {
	// Parse range like "A1B5" (no colon)
	start, end, ok := parse_range(range_str, context.temp_allocator)
	if !ok {
		return 0, "Invalid range format"
	}

	start_row, start_col, ok1 := identifier_to_coordinates(start)
	end_row, end_col, ok2 := identifier_to_coordinates(end)

	if !ok1 || !ok2 {
		return 0, "Invalid range coordinates"
	}

	// Multiply all values in the range
	product := f64(1)
	for row in start_row ..= end_row {
		for col in start_col ..= end_col {
			if row < 0 || row >= grid.rows || col < 0 || col >= grid.cols {
				return 0, "Range out of bounds"
			}

			cell := get_cell(grid, row, col)
			switch c in cell {
			case CellNumeric:
				product *= c.value
			case CellFunc:
				product *= c.value
			case CellEmpty:
				// Empty cells are treated as 1 (identity for multiplication)
			case CellText:
				return 0, "Cannot multiply text cell"
			}
		}
	}
	return product, ""
}

// COUNTIF function - counts cells in a range that meet a criteria
func_countif :: proc(grid: ^Grid, range_str: string, criteria: string) -> (result: f64, err: string) {
	// Parse range like "A1B5" (no colon)
	start, end, ok := parse_range(range_str, context.temp_allocator)
	if !ok {
		return 0, "Invalid range format"
	}

	start_row, start_col, ok1 := identifier_to_coordinates(start)
	end_row, end_col, ok2 := identifier_to_coordinates(end)

	if !ok1 || !ok2 {
		return 0, "Invalid range coordinates"
	}

	// Count cells matching the criteria
	count := f64(0)
	for row in start_row ..= end_row {
		for col in start_col ..= end_col {
			if row < 0 || row >= grid.rows || col < 0 || col >= grid.cols {
				return 0, "Range out of bounds"
			}

			cell := get_cell(grid, row, col)
			cell_val: f64
			switch c in cell {
			case CellNumeric:
				cell_val = c.value
			case CellFunc:
				cell_val = c.value
			case CellEmpty:
				cell_val = 0
			case CellText:
				continue // Skip text cells
			}

			// Test if cell matches criteria
			matches, crit_err := evaluate_criteria(cell_val, criteria)
			if crit_err != "" do return 0, crit_err
			if matches do count += 1
		}
	}
	return count, ""
}

// SUMIF function - sums cells in a range that meet a criteria
func_sumif :: proc(grid: ^Grid, range_str: string, criteria: string) -> (result: f64, err: string) {
	// Parse range like "A1B5" (no colon)
	start, end, ok := parse_range(range_str, context.temp_allocator)
	if !ok {
		return 0, "Invalid range format"
	}

	start_row, start_col, ok1 := identifier_to_coordinates(start)
	end_row, end_col, ok2 := identifier_to_coordinates(end)

	if !ok1 || !ok2 {
		return 0, "Invalid range coordinates"
	}

	// Sum cells matching the criteria
	sum := f64(0)
	for row in start_row ..= end_row {
		for col in start_col ..= end_col {
			if row < 0 || row >= grid.rows || col < 0 || col >= grid.cols {
				return 0, "Range out of bounds"
			}

			cell := get_cell(grid, row, col)
			cell_val: f64
			switch c in cell {
			case CellNumeric:
				cell_val = c.value
			case CellFunc:
				cell_val = c.value
			case CellEmpty:
				cell_val = 0
			case CellText:
				continue // Skip text cells
			}

			// Test if cell matches criteria
			matches, crit_err := evaluate_criteria(cell_val, criteria)
			if crit_err != "" do return 0, crit_err
			if matches do sum += cell_val
		}
	}
	return sum, ""
}

@(test)
test_sum_function :: proc(t: ^testing.T) {
	grid := new_grid()
	defer delete_grid(grid)

	// Set up a 2x2 grid with values:
	// A1=1, B1=2
	// A2=3, B2=4
	set_cell(grid, 0, 0, CellNumeric{value = 1})
	set_cell(grid, 0, 1, CellNumeric{value = 2})
	set_cell(grid, 1, 0, CellNumeric{value = 3})
	set_cell(grid, 1, 1, CellNumeric{value = 4})

	// Test SUM(A1:B2) = 1+2+3+4 = 10
	set_cell(grid, 2, 0, CellFunc{formula = "=SUM(A1:B2)"})
	val, err := evaluate_cell(grid, get_cell(grid, 2, 0).(CellFunc))
	testing.expect(t, val == 10, "SUM(A1:B2) should equal 10")
	testing.expect(t, err == "", "SUM should not produce error")

	// Test SUM with single row
	set_cell(grid, 2, 1, CellFunc{formula = "=SUM(A1:B1)"})
	val, err = evaluate_cell(grid, get_cell(grid, 2, 1).(CellFunc))
	testing.expect(t, val == 3, "SUM(A1:B1) should equal 3")
	testing.expect(t, err == "")

	// Test SUM with single column
	set_cell(grid, 2, 2, CellFunc{formula = "=SUM(A1:A2)"})
	val, err = evaluate_cell(grid, get_cell(grid, 2, 2).(CellFunc))
	testing.expect(t, val == 4, "SUM(A1:A2) should equal 4")
	testing.expect(t, err == "")

	// Test SUM with empty cells
	set_cell(grid, 3, 0, CellFunc{formula = "=SUM(C1:C2)"})
	val, err = evaluate_cell(grid, get_cell(grid, 3, 0).(CellFunc))
	testing.expect(t, val == 0, "SUM of empty cells should be 0")
	testing.expect(t, err == "")
}

@(test)
test_product_function :: proc(t: ^testing.T) {
	grid := new_grid()
	defer delete_grid(grid)

	// Set up a 2x2 grid with values:
	// A1=2, B1=3
	// A2=4, B2=5
	set_cell(grid, 0, 0, CellNumeric{value = 2})
	set_cell(grid, 0, 1, CellNumeric{value = 3})
	set_cell(grid, 1, 0, CellNumeric{value = 4})
	set_cell(grid, 1, 1, CellNumeric{value = 5})

	// Test PRODUCT(A1:B2) = 2*3*4*5 = 120
	set_cell(grid, 2, 0, CellFunc{formula = "=PRODUCT(A1:B2)"})
	val, err := evaluate_cell(grid, get_cell(grid, 2, 0).(CellFunc))
	testing.expect(t, val == 120, "PRODUCT(A1:B2) should equal 120")
	testing.expect(t, err == "", "PRODUCT should not produce error")

	// Test PRODUCT with single row
	set_cell(grid, 2, 1, CellFunc{formula = "=PRODUCT(A1:B1)"})
	val, err = evaluate_cell(grid, get_cell(grid, 2, 1).(CellFunc))
	testing.expect(t, val == 6, "PRODUCT(A1:B1) should equal 6")
	testing.expect(t, err == "")

	// Test PRODUCT with single column
	set_cell(grid, 2, 2, CellFunc{formula = "=PRODUCT(A1:A2)"})
	val, err = evaluate_cell(grid, get_cell(grid, 2, 2).(CellFunc))
	testing.expect(t, val == 8, "PRODUCT(A1:A2) should equal 8")
	testing.expect(t, err == "")

	// Test PRODUCT with empty cells
	set_cell(grid, 3, 0, CellFunc{formula = "=PRODUCT(C1:C2)"})
	val, err = evaluate_cell(grid, get_cell(grid, 3, 0).(CellFunc))
	testing.expect(t, val == 1, "PRODUCT of empty cells should be 1")
	testing.expect(t, err == "")
}

@(test)
test_countif_function :: proc(t: ^testing.T) {
	grid := new_grid()
	defer delete_grid(grid)

	// Set up a grid with values:
	// A1=5, B1=10
	// A2=15, B2=20
	set_cell(grid, 0, 0, CellNumeric{value = 5})
	set_cell(grid, 0, 1, CellNumeric{value = 10})
	set_cell(grid, 1, 0, CellNumeric{value = 15})
	set_cell(grid, 1, 1, CellNumeric{value = 20})

	// Test COUNTIF(A1:B2, ">10") should count 2 cells (15, 20)
	set_cell(grid, 2, 0, CellFunc{formula = `=COUNTIF(A1:B2, ">10")`})
	val, err := evaluate_cell(grid, get_cell(grid, 2, 0).(CellFunc))
	testing.expect(t, val == 2, "COUNTIF(A1:B2, \">10\") should equal 2")
	testing.expect(t, err == "", "COUNTIF should not produce error")

	// Test COUNTIF(A1:B2, ">=10") should count 3 cells (10, 15, 20)
	set_cell(grid, 2, 1, CellFunc{formula = `=COUNTIF(A1:B2, ">=10")`})
	val, err = evaluate_cell(grid, get_cell(grid, 2, 1).(CellFunc))
	testing.expect(t, val == 3, "COUNTIF(A1:B2, \">=10\") should equal 3")
	testing.expect(t, err == "")

	// Test COUNTIF(A1:B2, "<10") should count 1 cell (5)
	set_cell(grid, 2, 2, CellFunc{formula = `=COUNTIF(A1:B2, "<10")`})
	val, err = evaluate_cell(grid, get_cell(grid, 2, 2).(CellFunc))
	testing.expect(t, val == 1, "COUNTIF(A1:B2, \"<10\") should equal 1")
	testing.expect(t, err == "")

	// Test COUNTIF(A1:B2, "==15") should count 1 cell (15)
	set_cell(grid, 2, 3, CellFunc{formula = `=COUNTIF(A1:B2, "==15")`})
	val, err = evaluate_cell(grid, get_cell(grid, 2, 3).(CellFunc))
	testing.expect(t, val == 1, "COUNTIF(A1:B2, \"==15\") should equal 1")
	testing.expect(t, err == "")
}

@(test)
test_sumif_function :: proc(t: ^testing.T) {
	grid := new_grid()
	defer delete_grid(grid)

	// Set up a grid with values:
	// A1=5, B1=10
	// A2=15, B2=20
	set_cell(grid, 0, 0, CellNumeric{value = 5})
	set_cell(grid, 0, 1, CellNumeric{value = 10})
	set_cell(grid, 1, 0, CellNumeric{value = 15})
	set_cell(grid, 1, 1, CellNumeric{value = 20})

	// Test SUMIF(A1:B2, ">10") should sum 2 cells (15+20=35)
	set_cell(grid, 2, 0, CellFunc{formula = `=SUMIF(A1:B2, ">10")`})
	val, err := evaluate_cell(grid, get_cell(grid, 2, 0).(CellFunc))
	testing.expect(t, val == 35, "SUMIF(A1:B2, \">10\") should equal 35")
	testing.expect(t, err == "", "SUMIF should not produce error")

	// Test SUMIF(A1:B2, ">=10") should sum 3 cells (10+15+20=45)
	set_cell(grid, 2, 1, CellFunc{formula = `=SUMIF(A1:B2, ">=10")`})
	val, err = evaluate_cell(grid, get_cell(grid, 2, 1).(CellFunc))
	testing.expect(t, val == 45, "SUMIF(A1:B2, \">=10\") should equal 45")
	testing.expect(t, err == "")

	// Test SUMIF(A1:B2, "<10") should sum 1 cell (5)
	set_cell(grid, 2, 2, CellFunc{formula = `=SUMIF(A1:B2, "<10")`})
	val, err = evaluate_cell(grid, get_cell(grid, 2, 2).(CellFunc))
	testing.expect(t, val == 5, "SUMIF(A1:B2, \"<10\") should equal 5")
	testing.expect(t, err == "")

	// Test SUMIF(A1:B2, "<=15") should sum 3 cells (5+10+15=30)
	set_cell(grid, 2, 3, CellFunc{formula = `=SUMIF(A1:B2, "<=15")`})
	val, err = evaluate_cell(grid, get_cell(grid, 2, 3).(CellFunc))
	testing.expect(t, val == 30, "SUMIF(A1:B2, \"<=15\") should equal 30")
	testing.expect(t, err == "")
}

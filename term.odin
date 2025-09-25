package main
import "core:fmt"
import "core:os"
import "core:sys/posix"

oldt, newt: posix.termios;
enter_raw_mode :: proc(){

	// Get current terminal attributes
	if posix.tcgetattr(posix.FD(os.stdin), &oldt) != .OK {
		fmt.println("Error getting terminal attributes")
		return
	}

	newt = oldt
	// Disable canonical mode and echo
	newt.c_lflag -= {posix.CLocal_Flag_Bits.ICANON, posix.CLocal_Flag_Bits.ECHO}

	// Set new terminal attributes immediately
	if posix.tcsetattr(posix.FD(os.stdin), .TCSANOW, &newt) != .OK {
		fmt.println("Error setting terminal attributes")
		return
	}
	
	// Hide cursor
	fmt.print("\033[?25l")
}

exit_raw_mode :: proc() {
	// Show cursor
	fmt.print("\033[?25h")
	// Restore old terminal settings before exit
	posix.tcsetattr(posix.FD(os.stdin), .TCSANOW, &oldt)
}

get_press :: proc() -> u8{
	buf: [1]u8
	n, err := os.read(os.stdin, buf[:])
	if err != 0 || n == 0 {
		
		fmt.eprintfln("Error reading input or EOF")
		os.exit(1)
	}
	return buf[0]
}

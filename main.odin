package main

import "core:flags"
import "core:fmt"
import "core:os"
// import "core:net"


main :: proc() {

	Options :: struct {
		u: string `usage:"makes an HTTP request to the specified URL and print the response"`,
		s: string `usage:"makes an HTTP request to search the term using your favorite search engine and print top 10 results"`,
		// INFO: already implemented by deffault
		// h: bool `usage:"shows this help"`,
		// help: bool `usage:"shows this help"`,
	}

	opt: Options
	style := flags.Parsing_Style.Odin

	flags.parse_or_exit(&opt, os.args, style)

	fmt.printfln("%#v", opt)

}

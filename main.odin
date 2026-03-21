package main

import "core:flags"
import "core:fmt"
import "core:net"
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

	if opt.u != "" {
		http_get(opt.u, "")
	}


}

buff: [1024 * 1024]u8

//@tcp
http_get :: proc(hostname: string, endpoint: string) {
	host: net.Host = {
		hostname = hostname,
		port     = 80,
	}
	fmt.println("Dialing tcp")
	socket, dial_err := net.dial_tcp_from_host(host)
	if dial_err != nil {fmt.panicf("dial error: %v", dial_err)}

	request: []u8 = transmute([]u8)fmt.aprintf(
		"GET /%v HTTP/1.1\r\nHost: %s\r\n" + "User-Agent: Mozilla/5.0\r\n" + "\r\n",
		endpoint,
		host.hostname,
	)

	fmt.printfln("Sending tcp request: %s", request)
	_, send_err := net.send_tcp(socket, request)
	if send_err != nil {fmt.panicf("send error: %v", send_err)}

	fmt.println("Recieving tcp response")
	n, recv_err := net.recv_tcp(socket, buff[:])
	if recv_err != nil {fmt.panicf("recv error: %v", recv_err)}
	if n <= 0 {panic("got nothing from request")}

	fmt.printfln("%s", buff[:n])
}

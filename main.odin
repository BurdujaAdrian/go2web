package main

import "core:c"
import "core:flags"
import "core:fmt"
import "core:net"
import "core:os"
import "core:strings"
import html "odin-html"
import ossl "odin-http/openssl"


main :: proc() {

	Options :: struct {
		u: string `args:"pos=0" usage:"makes an HTTP request to the specified URL and print the response"`,
		s: string ` usage:"makes an HTTP request to search the term using your favorite search engine and print top 10 results"`,
		// INFO: already implemented by deffault
		// h: bool `usage:"shows this help"`,
		// help: bool `usage:"shows this help"`,
	}

	opt: Options
	style := flags.Parsing_Style.Odin

	flags.parse_or_exit(&opt, os.args, style)

	fmt.printfln("%#v", opt)

	https :: "https://"
	http :: "http://"
	is_https := true


	if opt.u != "" {
		url := opt.u
		hostname: string

		if url[:len(https)] == https {
			is_https = true
			hostname = url[len(https):]
		} else if url[:len(http)] == http {
			is_https = false
			hostname = url[len(http):]
		} else {
			// default to https
			hostname = url
		}

		endpoint_n := strings.index(url, "/")
		endpoint: string
		if endpoint_n == -1 {
			endpoint = ""
		} else {
			endpoint = url[endpoint_n + 1:]
			hostname = url[:endpoint_n]
		}
		fmt.println(hostname)
		fmt.println(endpoint)

		response: string = https_get(hostname, endpoint)
		doc := html.parse(response)
		fmt.println(response)

		// TODO: iterate the doc elements

	} else if opt.s != "" {
		// html based search engine api
		hostname := "html.duckduckgo.com"
		endpoint := fmt.aprintf("html/?q=%s", opt.s)

		response: string = https_get(hostname, endpoint)
		fmt.println(response)

		doc := html.parse(response)
		fmt.println(response)
	}


}

buff: [1024 * 1024]u8

https_get :: proc(hostname, endpoint: string) -> (response: string) {

	host: net.Host = {
		hostname = hostname,
		port     = 443,
	}

	fmt.println("Dialing tcp")
	socket, dial_err := net.dial_tcp_from_host(host)
	if dial_err != nil {fmt.panicf("dial error: %v", dial_err)}

	request := transmute([]u8)fmt.aprintf(
		"GET /%v HTTP/1.1\r\n" + "Host: %s\r\n" + "User-Agent: Mozilla/5.0\r\n" + "\r\n",
		endpoint,
		host.hostname,
	)

	fmt.println("Setting up tls connection")
	method := ossl.TLS_client_method()
	ctx := ossl.SSL_CTX_new(method)
	ssl := ossl.SSL_new(ctx)
	ossl.SSL_set_fd(ssl, c.int(socket))
	chostname := strings.clone_to_cstring(hostname)
	ossl.SSL_set_tlsext_host_name(ssl, chostname)

	switch ossl.SSL_connect(ssl) {
	case 2:
		fmt.panicf("ssl error: Controlled shutdown")
	case 1:
	case:
		fmt.panicf("ssl error: Fatal shutdown")
	}

	to_write := len(request)
	for to_write > 0 {
		ret := ossl.SSL_write(ssl, raw_data(request), c.int(to_write))
		if ret <= 0 {fmt.panicf("ssl error: write failed")}

		to_write -= int(ret)
	}

	response_size := ossl.SSL_read(ssl, raw_data(response[:]), len(buff))

	return transmute(string)buff[:response_size]
}

http_get :: proc(hostname: string, endpoint: string) -> string {

	host: net.Host = {
		hostname = hostname,
		port     = 80,
	}

	fmt.println("Dialing tcp")
	socket, dial_err := net.dial_tcp_from_host(host)
	if dial_err != nil {fmt.panicf("dial error: %v", dial_err)}

	request := transmute([]u8)fmt.aprintf(
		"GET /%v HTTP/1.1\r\nHost: %s\r\n" + "User-Agent: Mozilla/5.0\r\n" + "\r\n",
		endpoint,
		host.hostname,
	)

	fmt.printfln("Sending tcp request:\n%s", request)
	_, send_err := net.send_tcp(socket, request)
	if send_err != nil {fmt.panicf("send error: %v", send_err)}

	fmt.println("Recieving tcp response")
	n, recv_err := net.recv_tcp(socket, buff[:])
	if recv_err != nil {fmt.panicf("recv error: %v", recv_err)}
	if n <= 0 {panic("got nothing from request")}

	return transmute(string)buff[:n]
}

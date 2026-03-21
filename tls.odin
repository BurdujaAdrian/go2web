package main

import "core:c"
import "core:fmt"
import "core:net"
import "core:strings"
import ossl "openssl"

test_ssl :: proc() {
	hostname := "html.duckduckgo.com"
	host: net.Host = {
		hostname = hostname,
		port     = 443,
	}
	fmt.println("Dialing tcp")
	socket, dial_err := net.dial_tcp_from_host(host)
	if dial_err != nil {fmt.panicf("dial error: %v", dial_err)}

	request: []u8 = transmute([]u8)fmt.aprintf(
		"GET /html/?q=%v HTTP/1.1\r\n" + "Host: %s\r\n" + "User-Agent: Mozilla/5.0\r\n" + "\r\n",
		"nothing",
		host.hostname,
	)
	method := ossl.TLS_client_method()
	fmt.println("Making a ssl context")
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
		if ret <= 0 {
			fmt.panicf("ssl error: write failed")
		}

		to_write -= int(ret)
	}
	@(static) response: [1024 * 1024]u8

	ossl.SSL_read(ssl, raw_data(response[:]), len(response))

	fmt.printfln("%s", response[:])
}

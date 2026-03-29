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


	https :: "https://"
	http :: "http://"


	response: string

	if opt.u != "" {
		//#url based request

		url := opt.u
		hostname: string
		is_https := true

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

		endpoint_n := strings.index(hostname, "/")
		endpoint: string
		if endpoint_n == -1 {
			endpoint = ""
		} else {
			endpoint = hostname[endpoint_n + 1:]
			hostname = hostname[:endpoint_n]
		}
		// fmt.println(hostname)
		// fmt.println(endpoint)

		if is_https {
			fmt.println("Sending https")
			response = https_get(hostname, endpoint)
		} else {
			fmt.println("Sending http")
			response = http_get(hostname, endpoint)
		}

		fmt.println("\"", response, "\"")

		body := strings.split(response, "\r\n\r\n")[1]
		response_parse(body)

	} else if opt.s != "" {
		//#search on duckduckgo

		hostname := "html.duckduckgo.com"
		endpoint := fmt.aprintf("html/?q=%s", opt.s)

		response = https_get(hostname, endpoint)

		// html based search engine api
		search_result_parse(response)
	}

}

search_result_parse :: proc(body: string) {

	doc := html.parse(body)

	// fmt.println("node iterator from doc")
	doc_iter := html.node_iterator_from_document(doc)
	for node in html.node_iterator_depth_first(&doc_iter) {
		switch item in node {
		case html.Node_Tag:
			if item.name != "a" {continue}

			found_result := false
			found_result_url := false
			pending_href: string
			for attr in item.attributes {
				if attr.name == "class" {
					if attr.value == "\"result__a\"" {found_result = true}

					if attr.value == "\"result__url\"" {found_result_url = true}
				}
			}

			if found_result {
				fmt.print("(")
				for subitem in item.children {
					if text, ok := subitem.(html.Node_Text); ok {
						fmt.print(text.text)
					}
					if link, ok := subitem.(html.Node_Tag); ok {
						fmt.println("\nSubtag:", link)
					}
				}
				fmt.print(")")
				continue
			}

			if found_result_url {
				for subitem in item.children {
					if text, ok := subitem.(html.Node_Text); ok {
						fmt.print("[https://", strings.trim_space(text.text), "]", sep = "")
					}
					if link, ok := subitem.(html.Node_Tag); ok {
						fmt.println("\nSubtag:", link)
					}
				}
				fmt.println()
				fmt.println()
				continue
			}

		case html.Node_Text:
		}
	}
}


display_inner_text_nodes :: proc(
	doc_iter: ^html.Node_Iterator,
	parent: html.Node_Tag,
	nested := false, // if this function is called on a node who's children were not yet added to the stack
) {

	for item in parent.children {
		if !nested {
			pop_safe(&doc_iter.stack)
		}

		switch v in item {
		case html.Node_Text:
			text := strings.trim_space(v.text)
			if text != "" do fmt.print(text)
		case html.Node_Tag:
			switch v.name {
			// text nodes
			case "b", "i":
				fmt.print(" ")
				display_inner_text_nodes(doc_iter, v, true)
				fmt.print(" ")
			// link
			case "a":
				display_link_node(doc_iter, v, true)

			case "br":
				fmt.println("")
			case:
				fmt.panicf(
					"Unhandled child tag in inner_text_node: %v \n parrent tag: %v\n parrent children:%v",
					v.name,
					parent.name,
					parent.children,
				)
			}
		}
	}
}

display_link_node :: proc(
	doc_iter: ^html.Node_Iterator,
	v: html.Node_Tag,
	nested := false, // if this function is called on a node who's children were not yet added to the stack
) {
	fmt.print("(")
	display_inner_text_nodes(doc_iter, v, nested)
	fmt.print(")")
	for attr in v.attributes {
		// TODO: handle relative links and nofallow as well
		if attr.name == "href" {fmt.print("[", attr.value, "]", sep = "")}
	}
}

response_parse :: proc(body: string) {
	doc := html.parse(body)

	doc_iter := html.node_iterator_from_document(doc)

	for node in html.node_iterator_depth_first(&doc_iter) {
		switch v in node {
		case html.Node_Tag:
			switch v.name {
			case "title":
				fmt.print("Title: ")
				display_inner_text_nodes(&doc_iter, v)

				fmt.println()
			case "h":
				/*"h1", "h2", "h3", "h4", "h5" are all parsed as h*/
				fmt.print("\n\n# ")
				display_inner_text_nodes(&doc_iter, v)
			case "p":
				fmt.println()
				display_inner_text_nodes(&doc_iter, v)
			case "a":
				display_link_node(&doc_iter, v)
			case "b":
				display_inner_text_nodes(&doc_iter, v)

			case "img":
				for attr in v.attributes {
					if attr.name == "name" {
						fmt.print("img:", attr.value)
					}
				}
			case "ul":
				fmt.println("TABLE:")
				// fmt.printfln("%#v", v.children)
				for child in v.children {
					switch child_v in child {
					case html.Node_Tag:
						if child_v.name == "li" {
							fmt.print("- ")
							display_inner_text_nodes(&doc_iter, child_v)
							fmt.println()
							continue
						}
						fmt.panicf(
							"Didn't expect tags besides <li> within a <ul>, got %v instead",
							child_v.name,
						)

					case html.Node_Text:
						// remove the redundant text node
						pop_safe(&doc_iter.stack)
					}

				}
			case "ol":
				fmt.println("List:")
				// fmt.printfln("%#v", v.children)
				for child, i in v.children {
					switch child_v in child {
					case html.Node_Tag:
						if child_v.name == "li" {
							fmt.print(i + 1)
							display_inner_text_nodes(&doc_iter, child_v)
							fmt.println()
							continue
						}
						fmt.panicf(
							"Didn't expect tags besides <li> within a <ul>, got %v instead",
							child_v.name,
						)

					case html.Node_Text:
						// remove the redundant text node
						pop_safe(&doc_iter.stack)
					}

				}

			// tags to remove inner children from
			case "script", "style", "noscript":
				for _ in v.children {pop_safe(&doc_iter.stack)}
			case "div":
				fmt.print(" ")
			case:
			// ignore
			// fmt.println("ignored tag:", v.name)
			}

		case html.Node_Text:
			text := strings.trim_space(v.text)
			if text != "" do fmt.print(text)
		}

	}

}

buff: [1024 * 1024]u8

https_get :: proc(hostname, endpoint: string) -> (response: string) {

	host: net.Host = {
		hostname = hostname,
		port     = 443,
	}

	// fmt.println("Dialing tcp at ", host)
	socket, dial_err := net.dial_tcp_from_host(host)
	if dial_err != nil {fmt.panicf("dial error: %v", dial_err)}
	
	// odinfmt: disable
	request := transmute([]u8)fmt.aprintf(
		"GET /%v HTTP/1.1\r\n"+
		"Host: %s\r\n"+ 
		"User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/144.0.0.0 Safari/537.36 OPR/128.0.0.0\r\n" + 
		"Connection: close\r\n"+
		"\r\n",
		endpoint,
		host.hostname,
	)
	// odinfmt: enable


	// fmt.println("Setting up tls connection")
	method := ossl.TLS_client_method()
	ctx := ossl.SSL_CTX_new(method)
	ssl := ossl.SSL_new(ctx)
	ossl.SSL_set_fd(ssl, c.int(socket))
	chostname := strings.clone_to_cstring(hostname)
	ossl.SSL_set_tlsext_host_name(ssl, chostname)

	// fmt.println("Connecting to ssl")
	switch ossl.SSL_connect(ssl) {
	case 2:
		fmt.panicf("ssl error: Controlled shutdown")
	case 1:
	case:
		fmt.panicf("ssl error: Fatal shutdown")
	}

	to_write := len(request)
	for to_write > 0 {
		// fmt.println("writing to ssl")
		ret := ossl.SSL_write(ssl, raw_data(request), c.int(to_write))
		if ret <= 0 {fmt.panicf("ssl error: write failed")}

		to_write -= int(ret)
	}

	response_builder: strings.Builder
	bytes_read: i32
	for {
		bytes_read = ossl.SSL_read(ssl, raw_data(buff[:]), len(buff))
		if bytes_read <= 0 do break
		strings.write_bytes(&response_builder, buff[:bytes_read])
		fmt.println(strings.to_string(response_builder))
	}
	return strings.to_string(response_builder)
}

http_get :: proc(hostname: string, endpoint: string) -> string {

	host: net.Host = {
		hostname = hostname,
		port     = 80,
	}

	// fmt.println("Dialing tcp at ", host)
	socket, dial_err := net.dial_tcp_from_host(host)
	if dial_err != nil {fmt.panicf("dial error: %v", dial_err)}

	request := transmute([]u8)fmt.aprintf(
		"GET /%v HTTP/1.1\r\nHost: %s\r\n" +
		"User-Agent: Mozilla/5.0\r\n" +
		"Connection: close\r\n" +
		"\r\n",
		endpoint,
		host.hostname,
	)

	// fmt.printfln("Sending tcp request:\n%s", request)
	_, send_err := net.send_tcp(socket, request)
	if send_err != nil {fmt.panicf("send error: %v", send_err)}

	// fmt.println("Recieving tcp response")
	n, recv_err := net.recv_tcp(socket, buff[:])
	if recv_err != nil {fmt.panicf("recv error: %v", recv_err)}
	if n <= 0 {panic("got nothing from request")}

	return transmute(string)buff[:n]
}

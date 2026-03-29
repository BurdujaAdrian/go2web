package main

import "core:bytes"
import "core:c"
import "core:compress/gzip"
import "core:flags"
import "core:fmt"
import "core:net"
import "core:os"
import "core:strconv"
import "core:strings"
import html "odin-html"
import ossl "odin-http/openssl"

when ODIN_DEBUG {
	printf :: fmt.printfln
	print :: fmt.println
} else {
	nop :: proc(args: ..any) {}
	printf :: nop
	print :: nop
}


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

	checker :: proc(model: rawptr, name: string, value: any, args_tag: string) -> string {
		opts := cast(^Options)model
		if opts.u != "" && opts.s != "" {
			return "Flags -s and -u are mutually exclusive"
		}
		return ""
	}

	flags.register_flag_checker(checker)
	flags.parse_or_exit(&opt, os.args, style)


	https :: "https://"
	http :: "http://"


	response: string

	if opt.u != "" {
		//#url based request

		url := opt.u
		hostname: string
		is_https := true
		header: string
		body: string

		outer: for {
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
			print(hostname)
			print(endpoint)

			if is_https {
				print("Sending https")
				response = https_get(hostname, endpoint)
			} else {
				print("Sending http")
				response = http_get(hostname, endpoint)
			}

			parts := strings.split(response, "\r\n\r\n")
			header = parts[0]
			body = parts[1]

			inner: for line in strings.split_lines_iterator(&header) {
				http_tag :: "HTTP/1.1 "
				if len(line) >= len(http_tag) do if line[:len(http_tag)] == http_tag {
					printf("Found http tag:%v \n|%v|%v|", line, line[:len(http_tag)], line[len(http_tag):])

					if line[len(http_tag):][:1] != "3" && line[len(http_tag):][:3] != "300" {
						print("Not a redirect")
						break outer
					} else {
						print("Definetly a redirect")
					}
				}


				location_tag :: "Location: "
				if len(line) >= len(location_tag) do if line[:len(location_tag)] == location_tag {
					printf("Found location tag:%v \n|%v|%v|", line, line[:len(location_tag)], line[len(location_tag):])
					url = strings.trim_space(line[len(location_tag):])
					break inner
				}
			}

			fmt.println("Reddirecting to [", url, "] ...")
		}

		print("Decoding...", header)
		body = content_decoding(header, body)
		response_parse(body)

	} else if opt.s != "" {
		//#search on duckduckgo

		hostname := "html.duckduckgo.com"
		endpoint := fmt.aprintf("html/?q=%s", opt.s)

		response = https_get(hostname, endpoint)

		// html based search engine api
		parts := strings.split(response, "\r\n\r\n")
		header := parts[0]
		body := parts[1]

		print("Decoding...", header)
		body = content_decoding(header, body)
		search_result_parse(body)
	}

}

content_decoding :: proc(header, body: string) -> string {
	header := header
	body := body
	encoding_list: [dynamic]string
	is_chunked: bool = false

	gzip_tag :: "gzip"

	encoding_field :: "Content-Encoding: "
	encoding_flen :: len(encoding_field)

	chuncked_tag :: "chunked"
	chuncked_flen :: len(chuncked_tag)

	transfer_field :: "Transfer-Encoding: "
	transfer_flen :: len(transfer_field)

	for line in strings.split_lines_iterator(&header) {
		if len(line) >= encoding_flen do if line[:encoding_flen] == encoding_field {
			encodings := strings.split(line[encoding_flen:], ",")
			for encoding in encodings {
				encoding := strings.trim_space(encoding)
				append(&encoding_list, encoding)
			}
		}

		if len(line) >= transfer_flen do if line[:transfer_flen] == transfer_field {
			if line[transfer_flen:][:chuncked_flen] == chuncked_tag {
				is_chunked = true
			}
		}
	}


	if is_chunked {
		print("Decoding chunks")
		chunks_buffer: bytes.Buffer
		rest := transmute([]u8)body
		for {
			idx := bytes.index(rest, []byte{'\r', '\n'})
			if idx == -1 {
				// no more clrf's
				break
			}

			chunck_size, ok := strconv.parse_uint(transmute(string)rest[:idx], 16)
			if !ok do fmt.panicf("Can't parse int in chuncks, idx:%v; chunck:%s", idx, rest[:idx - 2])

			// last chunk
			if chunck_size == 0 do break

			rest = rest[idx + 2:] //skip clrf

			n, _ := bytes.buffer_write(&chunks_buffer, rest[:chunck_size])
			if n != cast(int)chunck_size do panic("Couldn't write the whole chunk")

			rest = rest[chunck_size + 2:]
		}

		body = bytes.buffer_to_string(&chunks_buffer)
	}

	if len(encoding_list) > 0 {
		for enc in encoding_list {
			switch enc {
			case gzip_tag:
				print("Attempting to unzip using gzip")
				bytes_buffer: bytes.Buffer
				if err := gzip.load_from_bytes(transmute([]byte)body, &bytes_buffer); err != nil {
					fmt.panicf("%v", err)
				}

				body = bytes.buffer_to_string(&bytes_buffer)
			case:
				return fmt.aprintfln("Encoding %s not supported", enc)

			}

		}
	}

	return body
}

search_result_parse :: proc(body: string) {

	doc := html.parse(body)

	print("node iterator from doc")
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
				print("ignored tag:", v.name)
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

	print("Dialing tcp at ", host)
	socket, dial_err := net.dial_tcp_from_host(host)
	if dial_err != nil {fmt.panicf("dial error: %v", dial_err)}

	request := format_request(endpoint, hostname)

	print("Setting up tls connection")
	method := ossl.TLS_client_method()
	ctx := ossl.SSL_CTX_new(method)
	ssl := ossl.SSL_new(ctx)
	ossl.SSL_set_fd(ssl, c.int(socket))
	chostname := strings.clone_to_cstring(hostname)
	ossl.SSL_set_tlsext_host_name(ssl, chostname)

	print("Connecting to ssl")
	switch ossl.SSL_connect(ssl) {
	case 2:
		fmt.panicf("ssl error: Controlled shutdown")
	case 1:
	case:
		fmt.panicf("ssl error: Fatal shutdown")
	}

	to_write := len(request)
	for to_write > 0 {
		print("writing to ssl")
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
	}
	return strings.to_string(response_builder)
}

http_get :: proc(hostname: string, endpoint: string) -> string {

	host: net.Host = {
		hostname = hostname,
		port     = 80,
	}

	print("Dialing tcp at ", host)
	socket, dial_err := net.dial_tcp_from_host(host)
	if dial_err != nil {fmt.panicf("dial error: %v", dial_err)}

	request := format_request(endpoint, hostname)

	printf("Sending tcp request:\n%s", request)
	_, send_err := net.send_tcp(socket, request)
	if send_err != nil {fmt.panicf("send error: %v", send_err)}

	print("Recieving tcp response")
	n, recv_err := net.recv_tcp(socket, buff[:])
	if recv_err != nil {fmt.panicf("recv error: %v", recv_err)}
	if n <= 0 {panic("got nothing from request")}

	return transmute(string)buff[:n]
}

format_request :: proc(endpoint, hostname: string) -> []u8 {
	
	// odinfmt: disable
	request := transmute([]u8)fmt.aprintf(
		"GET /%v HTTP/1.1\r\n"+
		"Host: %s\r\n"+ 
		"User-Agent: PostmanRuntime/7.52.0\r\n" + 
		"Accept-Encoding: gzip\r\n"+
		"Accept: */*\r\n"+
		"Connection: close\r\n"+
		"\r\n",
		endpoint,
		hostname,
	)
	// odinfmt: enable

	return request
}

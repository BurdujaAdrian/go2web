# Odin HTTP CLI

A simple command-line tool written in [Odin](https://odin-lang.org/) that fetches web pages or searches the web via DuckDuckGo’s HTML interface, then formats the response as readable plain text.

### Usage example: web searching
```bash
>go2web.exe -s:"Apples"
(Apple - Wikipedia)[https://en.wikipedia.org/wiki/Apple]

(25 Types of Apples - Jessica Gavin)[https://www.jessicagavin.com/types-of-apples/]

(Apples 101: Nutrition Facts and Health Benefits)[https://www.healthline.com/nutrition/foods/apples]

(Apple)[https://www.apple.com]

(6 Healthiest Types of Apples for Digestion, Blood Sugar, and Gut Health)[https://www.verywellhealth.com/healthiest-types-of-apples-11905297]

(All the types of apples (almost) and what to use them for in one place)[https://www.usatoday.com/story/graphics/2024/10/24/apple-types-varieties-guide/75721107007/]

(Apple | Fruit, Types, Nutrition, Cultivation, &amp; Facts | Britannica)[https://www.britannica.com/plant/apple-fruit-and-tree]

(iSpace - oficial Apple Premium Partner in Moldova)[https://ispace.md]

(The 10 Best Apples to Eat Fresh, According to a Fruit Expert)[https://www.marthastewart.com/best-apples-to-eat-fresh-11832852]

(Apples: Nutrition and Health Benefits - WebMD)[https://www.webmd.com/food-recipes/benefits-apples]


```

### Usage example: web browsing
```bash
go2web.exe -u:"https://example.com"
()["https://iana.org/domains/example"]Title: Example Domain


# Example Domain
This domain is for use in documentation examples without needing permission. Avoid use in operations.
Learn more
```

## Features

- Make `GET` requests to HTTP and HTTPS URLs with automatic redirect handling (up to 10 redirects).
- Decode `gzip` and `chunked` transfer encoding.
- Parse HTML and extract text, links, headings, lists, and images as plain text.
- Search DuckDuckGo using the `-s` flag and display the top results in a clean format.
- Local response caching (10‑second TTL) to avoid repeated network requests.

## Dependencies

- **Odin compiler** – [Installation guide](https://odin-lang.org/docs/install/)
- **OpenSSL** development libraries (e.g. `libssl-dev` on Debian/Ubuntu, `openssl` on macOS via Homebrew)
- Two custom Odin packages are vendored as **git submodules**:
  - `odin-html` – HTML parser
  - `odin-http` – Library for HTTP/S

  These are automatically checked out when cloning with:
  ```bash
  git clone --recurse-submodules <repo-url>
  ```
  If you have already cloned the repository without submodules, run:
  ```bash
  git submodule update --init
  ```
  The submodules live at the paths expected by the import statements (`odin-html` and `odin-http`).

## Build

```bash
odin build .
```

The `-file` flag treats the file as a standalone script. If you structure the project with packages, adjust accordingly.

## Usage

```bash
# Fetch a URL and display its content
./httpcli -u "https://example.com"

# Search for a term using DuckDuckGo
./httpcli -s "odin programming language"
```

Flags `-u` and `-s` are mutually exclusive. If both are provided, an error is shown.

### Caching

Responses are cached in the `cache/u/` (for URLs) and `cache/s/` (for searches) directories. A cache entry is valid for **10 seconds**; after that, a fresh request is made.

## How it works

- HTTPS is handled via OpenSSL using the `odin-http/openssl` package.
- HTTP requests use Odin’s built‑in `net` package.
- HTML parsing is done with `odin-html`.
- Gzip decompression uses Odin’s `core:compress/gzip`.
- Output is printed to stdout after basic formatting.

## Notes

- This tool was tested with simple websites and DuckDuckGo’s `html.duckduckgo.com` endpoint. Complex JavaScript‑driven sites will not render correctly.
- The search functionality relies on DuckDuckGo’s HTML version and may break if the site’s structure changes.

## License

No license specified – use at your own discretion.

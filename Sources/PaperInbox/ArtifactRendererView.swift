import SwiftUI
import WebKit

struct ArtifactRendererView: NSViewRepresentable {
    let markdown: String

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.allowsMagnification = true
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(ArtifactHTMLRenderer(markdown: markdown).htmlDocument(), baseURL: nil)
    }
}

private struct ArtifactHTMLRenderer {
    let markdown: String

    func htmlDocument() -> String {
        """
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <script>
          window.MathJax = {
            tex: {
              inlineMath: [['\\\\(', '\\\\)'], ['$', '$']],
              displayMath: [['\\\\[', '\\\\]'], ['$$', '$$']],
              processEscapes: true
            },
            svg: { fontCache: 'global' }
          };
          </script>
          <script async src="https://cdn.jsdelivr.net/npm/mathjax@3/es5/tex-svg.js"></script>
          <style>
          :root {
            color-scheme: light dark;
            font: -apple-system-body;
          }
          body {
            margin: 0;
            padding: 0;
            background: transparent;
            color: CanvasText;
            font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
            font-size: 14px;
            line-height: 1.55;
          }
          .artifact {
            box-sizing: border-box;
            padding: 2px 2px 18px;
            max-width: 100%;
          }
          h1, h2, h3 {
            line-height: 1.25;
            margin: 1.1em 0 0.45em;
            font-weight: 650;
          }
          h1 { font-size: 1.28rem; }
          h2 { font-size: 1.14rem; }
          h3 { font-size: 1.02rem; }
          p { margin: 0.6em 0; }
          ul, ol { margin: 0.45em 0 0.85em 1.35em; padding: 0; }
          li { margin: 0.28em 0; }
          code {
            font-family: "SF Mono", Menlo, monospace;
            font-size: 0.92em;
            background: color-mix(in srgb, CanvasText 8%, transparent);
            padding: 0.08em 0.28em;
            border-radius: 4px;
          }
          pre {
            overflow-x: auto;
            padding: 10px 12px;
            border-radius: 6px;
            background: color-mix(in srgb, CanvasText 8%, transparent);
          }
          pre code { background: transparent; padding: 0; }
          blockquote {
            margin: 0.8em 0;
            padding-left: 1em;
            border-left: 3px solid color-mix(in srgb, CanvasText 22%, transparent);
            color: color-mix(in srgb, CanvasText 72%, transparent);
          }
          .math-block {
            overflow-x: auto;
            margin: 0.65em 0;
            padding: 0.2em 0;
          }
          mjx-container[jax="SVG"] {
            overflow-x: auto;
            overflow-y: hidden;
            max-width: 100%;
          }
          </style>
        </head>
        <body>
          <main class="artifact">
            \(bodyHTML())
          </main>
        </body>
        </html>
        """
    }

    private func bodyHTML() -> String {
        renderBlocks(from: normalizeMath(in: clean(markdown)))
    }

    private func clean(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{fffc}", with: "")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizeMath(in text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var output: [String] = []
        var mathBuffer: [String] = []
        var insideDelimitedMath = false
        var insideFence = false

        func flushMathBuffer() {
            guard !mathBuffer.isEmpty else { return }
            output.append("\\[")
            output.append(contentsOf: mathBuffer)
            output.append("\\]")
            mathBuffer.removeAll()
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flushMathBuffer()
                insideFence.toggle()
                output.append(line)
                continue
            }

            if insideFence {
                output.append(line)
                continue
            }

            if trimmed.contains("\\[") || trimmed.contains("$$") {
                flushMathBuffer()
                insideDelimitedMath = true
                output.append(line)
                if trimmed.contains("\\]") || (trimmed.filter { $0 == "$" }.count >= 4) {
                    insideDelimitedMath = false
                }
                continue
            }

            if insideDelimitedMath {
                output.append(line)
                if trimmed.contains("\\]") || trimmed.contains("$$") {
                    insideDelimitedMath = false
                }
                continue
            }

            if trimmed.isEmpty {
                flushMathBuffer()
                output.append(line)
            } else if isStandaloneMathLine(trimmed) {
                mathBuffer.append(trimmed)
            } else {
                flushMathBuffer()
                output.append(line)
            }
        }

        flushMathBuffer()
        return output.joined(separator: "\n")
    }

    private func isStandaloneMathLine(_ line: String) -> Bool {
        guard !line.hasPrefix("#"),
              !line.hasPrefix("- "),
              !line.hasPrefix("* "),
              !line.hasPrefix(">"),
              line.range(of: #"^\d+\.\s+"#, options: .regularExpression) == nil else {
            return false
        }

        if isClearlyProseWithInlineMath(line) {
            return false
        }

        let latexCommands = [
            "\\alpha", "\\beta", "\\gamma", "\\delta", "\\epsilon", "\\theta", "\\lambda",
            "\\mu", "\\sigma", "\\phi", "\\psi", "\\omega", "\\mathcal", "\\mathbb",
            "\\mathrm", "\\mathbf", "\\mathsf", "\\text", "\\operatorname",
            "\\frac", "\\sum", "\\prod", "\\int", "\\nabla", "\\partial", "\\sqrt",
            "\\exp", "\\log", "\\Pr", "\\arg", "\\min", "\\max", "\\sim", "\\in",
            "\\le", "\\ge", "\\neq", "\\approx", "\\propto", "\\cdot", "\\times",
            "\\top", "\\dot", "\\hat", "\\bar", "\\tilde", "\\vec", "\\overline",
            "\\widehat", "\\star", "\\varepsilon", "\\ell", "\\qquad", "\\quad",
            "\\left", "\\right", "\\xrightarrow", "\\leftrightarrow", "\\rightarrow",
            "\\Leftarrow", "\\Rightarrow", "\\Leftrightarrow", "\\Longrightarrow",
            "\\Longleftarrow", "\\Longleftrightarrow", "\\implies", "\\iff", "\\mapsto",
            "\\to"
        ]
        let hasLatexCommand = latexCommands.contains { line.contains($0) }
        let hasEquationRelation = line.contains("=")
            || line.contains("=>")
            || line.contains("->")
            || line.contains("\\to")
            || line.contains("\\rightarrow")
            || line.contains("\\leftrightarrow")
            || line.contains("\\Rightarrow")
            || line.contains("\\Leftarrow")
            || line.contains("\\Leftrightarrow")
            || line.contains("\\Longrightarrow")
            || line.contains("\\Longleftarrow")
            || line.contains("\\Longleftrightarrow")
            || line.contains("\\implies")
            || line.contains("\\iff")
            || line.contains("\\mapsto")
        let hasMathSyntax = line.contains("_") || line.contains("^") || line.contains("\\")
        let isShortMathToken = line.range(
            of: #"^[A-Za-z](?:_[A-Za-z0-9{}\\]+)?(?:\^\{?[^,\s]+\}?)?[,.]?$"#,
            options: .regularExpression
        ) != nil

        return isShortMathToken || hasLatexCommand || (hasEquationRelation && hasMathSyntax)
    }

    private func isClearlyProseWithInlineMath(_ line: String) -> Bool {
        if line.hasPrefix("\\text{") && line.range(of: #"^\\text\{[^}]+\}[,.;:]?$"#, options: .regularExpression) != nil {
            return false
        }

        let stripped = line
            .replacingOccurrences(of: #"\\text\{[^}]*\}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\\[A-Za-z]+(?:\{[^}]*\})?"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[A-Za-z]_[A-Za-z0-9{}\\^()]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"[=+\-*/^_(),.;:\[\]{}]"#, with: " ", options: .regularExpression)

        let proseWords = stripped
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { word in
                word.count > 2 && word.rangeOfCharacter(from: .decimalDigits) == nil
            }

        guard proseWords.count >= 4 else {
            return false
        }

        if proseWords.count >= 6 {
            return true
        }

        let proseMarkers: Set<String> = [
            "and", "with", "from", "into", "where", "usually", "such", "layer",
            "aligns", "target", "features", "frozen", "visual", "encoder",
            "method", "paper", "intermediate", "chooses", "coefficient", "controls",
            "training", "inference", "time", "steps", "involving", "disappear",
            "sampling", "uses", "ordinary", "exactly", "usual", "clean", "noisy",
            "representation", "regularizer", "velocity", "objective"
        ]
        let lowercasedWords = proseWords.map { $0.lowercased() }
        return lowercasedWords.contains { proseMarkers.contains($0) }
    }

    private func renderBlocks(from text: String) -> String {
        let lines = text.components(separatedBy: "\n")
        var html: [String] = []
        var paragraph: [String] = []
        var listKind: String?
        var inCode = false
        var codeLines: [String] = []
        var inMath = false
        var mathLines: [String] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            html.append("<p>\(renderInline(paragraph.joined(separator: " ")))</p>")
            paragraph.removeAll()
        }

        func closeList() {
            if let currentListKind = listKind {
                html.append("</\(currentListKind)>")
                listKind = nil
            }
        }

        func appendListItem(kind: String, content: String) {
            flushParagraph()
            if listKind != kind {
                closeList()
                listKind = kind
                html.append("<\(kind)>")
            }
            html.append("<li>\(renderInline(content))</li>")
        }

        func flushCode() {
            guard !codeLines.isEmpty else { return }
            html.append("<pre><code>\(escapeHTML(codeLines.joined(separator: "\n")))</code></pre>")
            codeLines.removeAll()
        }

        func flushMath() {
            guard !mathLines.isEmpty else { return }
            html.append("<div class=\"math-block\">\\[\(escapeHTML(mathLines.joined(separator: "\n")))\\]</div>")
            mathLines.removeAll()
        }

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                if inCode {
                    inCode = false
                    flushCode()
                } else {
                    flushParagraph()
                    closeList()
                    inCode = true
                }
                continue
            }

            if inCode {
                codeLines.append(rawLine)
                continue
            }

            if line == "\\[" || line == "$$" {
                flushParagraph()
                closeList()
                inMath = true
                mathLines.removeAll()
                continue
            }

            if line == "\\]" || line == "$$" {
                inMath = false
                flushMath()
                continue
            }

            if inMath {
                mathLines.append(rawLine)
                continue
            }

            if line.isEmpty {
                flushParagraph()
                closeList()
                continue
            }

            if let heading = headingMatch(line) {
                flushParagraph()
                closeList()
                html.append("<h\(heading.level)>\(renderInline(heading.text))</h\(heading.level)>")
            } else if let heading = numberedSectionHeading(line) {
                flushParagraph()
                closeList()
                html.append("<h3>\(renderInline(heading))</h3>")
            } else if let item = unorderedListItem(line) {
                appendListItem(kind: "ul", content: item)
            } else if let item = orderedListItem(line) {
                appendListItem(kind: "ol", content: item)
            } else if line.hasPrefix(">") {
                flushParagraph()
                closeList()
                html.append("<blockquote>\(renderInline(String(line.dropFirst()).trimmingCharacters(in: .whitespaces)))</blockquote>")
            } else {
                closeList()
                paragraph.append(line)
            }
        }

        flushParagraph()
        closeList()
        flushCode()
        flushMath()
        return html.joined(separator: "\n")
    }

    private func headingMatch(_ line: String) -> (level: Int, text: String)? {
        guard let range = line.range(of: #"^#{1,3}\s+"#, options: .regularExpression) else {
            return nil
        }
        let level = line[line.startIndex..<range.upperBound].filter { $0 == "#" }.count
        return (level, String(line[range.upperBound...]))
    }

    private func unorderedListItem(_ line: String) -> String? {
        guard let range = line.range(of: #"^[-*]\s+"#, options: .regularExpression) else {
            return nil
        }
        return String(line[range.upperBound...])
    }

    private func numberedSectionHeading(_ line: String) -> String? {
        guard let range = line.range(of: #"^\d+\.\s+"#, options: .regularExpression) else {
            return nil
        }

        let content = String(line[range.upperBound...])
        let wordCount = content
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .count

        guard wordCount <= 9,
              !content.contains(":"),
              !content.contains(","),
              !content.contains(";"),
              !content.hasSuffix("."),
              !content.contains("  ") else {
            return nil
        }

        return content
    }

    private func orderedListItem(_ line: String) -> String? {
        guard let range = line.range(of: #"^\d+\.\s+"#, options: .regularExpression) else {
            return nil
        }
        return String(line[range.upperBound...])
    }

    private func renderInline(_ text: String) -> String {
        var value = escapeHTML(text)

        value = value.replacingOccurrences(
            of: #"`([^`]+)`"#,
            with: #"<code>$1</code>"#,
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"\*\*([^*]+)\*\*"#,
            with: #"<strong>$1</strong>"#,
            options: .regularExpression
        )
        value = value.replacingOccurrences(
            of: #"(?<!\*)\*([^*]+)\*(?!\*)"#,
            with: #"<em>$1</em>"#,
            options: .regularExpression
        )
        value = protectExistingMath(in: value) { unprotected in
            var rendered = normalizeInlineArrows(in: unprotected)
            rendered = wrapParenthesizedMath(in: rendered)
            rendered = wrapInlineMath(in: rendered)
            return rendered
        }
        return value
    }

    private func wrapParenthesizedMath(in text: String) -> String {
        let patterns = [
            #"\((\\[A-Za-z]+(?:_[A-Za-z0-9{}\\]+)?(?:\^\{?[^)\s]+\}?)?)\)"#,
            #"\(([A-Za-z](?:_[A-Za-z0-9{}\\]+)(?:\^\{?[^)\s]+\}?)?)\)"#
        ]

        var value = text
        for pattern in patterns {
            value = value.replacingOccurrences(
                of: pattern,
                with: #"\($1\)"#,
                options: .regularExpression
            )
        }
        return value
    }

    private func wrapInlineMath(in text: String) -> String {
        var value = text
        let patterns = [
            #"(?<![\\\w])([A-Za-z](?:_[A-Za-z0-9{}\\]+)(?:\^\{?[^,\s.;:]+\}?)?(?:\([^)]*\))?(?:\s*=\s*[A-Za-z0-9_\\{}^()]+)?)"#,
            #"(?<![\\\w])(\\[A-Za-z]+(?:\{[^}]+\})?(?:_[A-Za-z0-9{}\\]+)?(?:\^\{?[^,\s.;:]+\}?)?)"#,
            #"(?<![\\\w])([A-Za-z]+_[A-Za-z0-9]+(?:\^\([^)]+\))?)"#
        ]

        for pattern in patterns {
            value = value.replacingOccurrences(
                of: pattern,
                with: #"\($1\)"#,
                options: .regularExpression
            )
        }
        return value
    }

    private func normalizeInlineArrows(in text: String) -> String {
        text
            .replacingOccurrences(of: "=>", with: "⇒")
            .replacingOccurrences(of: "->", with: "→")
    }

    private func protectExistingMath(in text: String, transform: (String) -> String) -> String {
        let patterns = [
            #"\\\(.+?\\\)"#,
            #"\\\[.+?\\\]"#,
            #"\$\$.+?\$\$"#
        ]

        var protected = text
        var replacements: [(String, String)] = []

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
                continue
            }
            let matches = regex.matches(
                in: protected,
                range: NSRange(protected.startIndex..<protected.endIndex, in: protected)
            )
            for match in matches.reversed() {
                guard let range = Range(match.range, in: protected) else { continue }
                let token = "PINMATHTOKEN\(replacements.count)X"
                replacements.append((token, String(protected[range])))
                protected.replaceSubrange(range, with: token)
            }
        }

        var transformed = transform(protected)
        for (token, original) in replacements.reversed() {
            transformed = transformed.replacingOccurrences(of: token, with: original)
        }
        return transformed
    }

    private func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

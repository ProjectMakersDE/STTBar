import SwiftUI

/// License acknowledgements for the bundled open-source components. Required
/// because WhisperKit and the Whisper models ship with / are loaded by the app.
struct AcknowledgementsView: View {
    var body: some View {
        ScrollView {
            Text(Self.text)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(8)
        }
    }

    static let text = """
    STTBar enthält / verwendet Open-Source-Software unter der MIT-Lizenz:

    • WhisperKit — © Argmax, Inc. — https://github.com/argmaxinc/WhisperKit
    • OpenAI Whisper (Modelle) — © OpenAI — https://github.com/openai/whisper
    • whisper.cpp — © Georgi Gerganov — https://github.com/ggerganov/whisper.cpp

    MIT License

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
    """
}

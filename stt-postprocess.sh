#!/usr/bin/env bash
# stt-postprocess.sh — Optional STT text cleanup via local LLM
# Usage: printf '%s' "$text" | stt-postprocess.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
[[ -f "$SCRIPT_DIR/.env" ]] && source "$SCRIPT_DIR/.env"

input="$(cat)"
replacements_enabled="${STT_REPLACEMENTS_ENABLED:-1}"
replacements_file="${STT_REPLACEMENTS_FILE:-$SCRIPT_DIR/stt-replacements.tsv}"

apply_replacements() {
    local text="$1"

    case "$replacements_enabled" in
        1|true|TRUE|yes|YES|on|ON) ;;
        *) printf '%s' "$text"; return 0 ;;
    esac

    if [[ ! -f "$replacements_file" ]]; then
        printf '%s' "$text"
        return 0
    fi

    printf '%s' "$text" | perl -CSDA -Mutf8 -e '
use strict;
use warnings;
use utf8;

my $file = shift @ARGV;
my $text = do { local $/; <STDIN> };

open my $fh, q(<:encoding(UTF-8)), $file or do {
    print $text;
    exit 0;
};

while (my $line = <$fh>) {
    chomp $line;
    next if $line =~ /^\s*(?:#|$)/;

    my ($from, $to) = split /\t/, $line, 2;
    next unless defined $from && defined $to;
    next if $from eq q();

    my $quoted = quotemeta($from);
    my $left = $from =~ /^\w/ ? q((?<![\p{L}\p{N}_])) : q();
    my $right = $from =~ /\w$/ ? q((?![\p{L}\p{N}_])) : q();
    $text =~ s/${left}${quoted}${right}/$to/giu;
}

print $text;
' "$replacements_file"
}

fallback() {
    apply_replacements "$input"
}

if [[ -z "$input" ]]; then
    exit 0
fi

case "${STT_POSTPROCESS_ENABLED:-0}" in
    1|true|TRUE|yes|YES|on|ON) ;;
    *) fallback; exit 0 ;;
esac

provider="${STT_POSTPROCESS_PROVIDER:-lmstudio}"
url="${STT_POSTPROCESS_URL:-http://localhost:1234/api/v1/chat}"
model="${STT_POSTPROCESS_MODEL:-qwen/qwen3.5-9b}"
timeout="${STT_POSTPROCESS_TIMEOUT:-5}"
temperature="${STT_POSTPROCESS_TEMPERATURE:-0}"
reasoning="${STT_POSTPROCESS_REASONING:-off}"

default_prompt='Du bist ein Post-Processor für Speech-to-Text-Rohtexte.
Nicht übersetzen. Erhalte Sprache, Bedeutung, Reihenfolge und Fachbegriffe.
Korrigiere Grammatik, Zeichensetzung und Groß-/Kleinschreibung.
Mache den Text lesbar und natürlich, aber erfinde keine neuen Inhalte.
Wandle gesprochene technische Schreibweisen um:
- HTTP doppelpunkt slash slash -> http://
- HTTPS doppelpunkt slash slash -> https://
- punkt in Domains -> .
- slash oder schrägstrich in URLs -> /
- at in E-Mail-Adressen -> @
Gib ausschließlich den finalen korrigierten Text zurück, keine Erklärung.'

input="$(apply_replacements "$input")"
prompt="${STT_POSTPROCESS_PROMPT:-$default_prompt}"
prompt_input="${prompt}

Text: ${input}"

case "$provider" in
    lmstudio)
        if ! payload="$(jq -n \
            --arg model "$model" \
            --arg input "$prompt_input" \
            --arg reasoning "$reasoning" \
            --arg temperature "$temperature" \
            '{
                model: $model,
                input: $input,
                store: false,
                stream: false,
                reasoning: $reasoning,
                temperature: ($temperature | tonumber)
            }' 2>/dev/null)"; then
            fallback
            exit 0
        fi

        if ! response="$(curl -sS --max-time "$timeout" \
            -H 'Content-Type: application/json' \
            -d "$payload" \
            "$url" 2>/dev/null)"; then
            fallback
            exit 0
        fi

        text="$(printf '%s' "$response" | jq -r '[.output[]? | select(.type == "message") | .content] | join("")' 2>/dev/null || true)"
        ;;

    openai)
        if ! payload="$(jq -n \
            --arg model "$model" \
            --arg prompt "$prompt" \
            --arg text "$input" \
            --arg temperature "$temperature" \
            '{
                model: $model,
                messages: [
                    {role: "system", content: $prompt},
                    {role: "user", content: $text}
                ],
                stream: false,
                temperature: ($temperature | tonumber)
            }' 2>/dev/null)"; then
            fallback
            exit 0
        fi

        if ! response="$(curl -sS --max-time "$timeout" \
            -H 'Content-Type: application/json' \
            -d "$payload" \
            "$url" 2>/dev/null)"; then
            fallback
            exit 0
        fi

        text="$(printf '%s' "$response" | jq -r '.choices[0].message.content // empty' 2>/dev/null || true)"
        ;;

    *)
        fallback
        exit 0
        ;;
esac

if [[ -z "$text" ]]; then
    fallback
    exit 0
fi

apply_replacements "$text"

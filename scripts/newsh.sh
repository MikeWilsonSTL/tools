#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2025 Mike Wilson
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Usage: newsh [options] [filename]
# Author: Mike Wilson <mike@mikewilsonstl.com>
# Created: 2025-12-14T17:06:00+00:00
# Description: A tool to streamline bash script creation. Creates a named script from a template and opens a text editor.
#              NOTE: This one is my personal modification with author and license fields hard coded.

set -euo pipefail
shopt -s extglob

# defaults
FILENAME=""
TIMESTAMP=true
YEAR=""
TEMPLATE_FILE=""
SHELL="bash"
NO_EDIT=false
FORCE=false

# templates
template_bash() {
cat <<'EOF'
#!/usr/bin/env bash
# SPDX-FileCopyrightText: {{YEAR}} Mike Wilson
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Usage: [how to run the script, e.g., ./script_name.sh <arguments>]
# Author: Mike Wilson <mike@mikewilsonstl.com>
# Created: {{TIMESTAMP}}
# Description: [brief purpose of the script]

set -euo pipefail
shopt -s extglob

main() {
    echo "script started"
    # add commands here
    echo "script finished successfully"
}

main "$@"
EOF
}

usage() {
    cat <<EOF
Usage: newsh [options] [filename]

NOTE: This is a personal modification with metadata
      flags removed. These the values hard-coded.

Options:
  -n, --no-edit         Do not open editor
  -T, --template [FILE] Use custom template file
  -F, --force           Overwrite existing file
  -h, --help            Show this help
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -T|--template)
                if [[ ${2:-} && ! $2 =~ ^- ]]; then
                    TEMPLATE_FILE="$2"
                    shift 2
                else
                    echo "Error: --template requires a file path" >&2
                    return 1
                fi
                ;;
            -n|--no-edit)
                NO_EDIT=true
                shift
                ;;
            -F|--force)
                FORCE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            --)
                shift
                break
                ;;
            -*)
                echo "Unknown option: $1" >&2
                return 1
                ;;
            *)
                FILENAME="$1"
                shift
                ;;
        esac
    done
}


collect_metadata() {
    $YEAR && YEAR="$(date +%Y)" || YEAR=""
    $TIMESTAMP && TIMESTAMP="$(date -Is)" || TIMESTAMP=""
}

render_template() {
    local content

    if [[ -n "$TEMPLATE_FILE" ]]; then
        content="$(<"$TEMPLATE_FILE")"
    else
        case "$SHELL" in
            bash) content="$(template_bash)" ;;
            *) echo "Unsupported shell: $SHELL" >&2; return 1 ;;
        esac
    fi

    content="${content//\{\{TIMESTAMP\}\}/$TIMESTAMP}"
    content="${content//\{\{YEAR\}\}/$YEAR}"

    printf '%s\n' "$content"
}

main() {
    parse_args "$@"

    [[ -z "${FILENAME:-}" ]] && read -rp "New script name: " FILENAME

    if [[ -e "$FILENAME" && $FORCE == false ]]; then
        echo "File exists. Use --force to overwrite." >&2
        return 1
    fi

    collect_metadata
    render_template > "$FILENAME"
    chmod +x "$FILENAME"

    $NO_EDIT || ${EDITOR:-vim} "$FILENAME"
}

main "$@" || exit $?

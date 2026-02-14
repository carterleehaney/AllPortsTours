#!/bin/bash

set -e

TEAM=""
COPY_START=""
COPY_END=""
DATE=""
TEMPLATE_FILE="Inject-Template.odt"

while [[ $# -gt 0 ]]; do
    case $1 in
        --team)
            TEAM="$2"
            shift 2
            ;;
        --copy-start)
            COPY_START="$2"
            shift 2
            ;;
        --copy-end)
            COPY_END="$2"
            shift 2
            ;;
        --date)
            DATE="$2"
            shift 2
            ;;
        *)
            exit 1
            ;;
    esac
done

if [[ -z "$TEAM" ]]; then
    exit 1
fi

if [[ -z "$COPY_START" ]]; then
    exit 1
fi

if [[ -z "$COPY_END" ]]; then
    exit 1
fi

if ! [[ "$COPY_START" =~ ^[0-9]+$ ]] || [[ "$COPY_START" -lt 1 ]]; then
    exit 1
fi

if ! [[ "$COPY_END" =~ ^[0-9]+$ ]] || [[ "$COPY_END" -lt 1 ]]; then
    exit 1
fi

if [[ "$COPY_END" -lt "$COPY_START" ]]; then
    exit 1
fi

if [[ ! -f "$TEMPLATE_FILE" ]]; then
    exit 1
fi

NUM_FILES=$((COPY_END - COPY_START + 1))

process_file() {
    local inject_num=$1
    local output_file="team${TEAM}-inject${inject_num}.odt"
    local temp_dir="temp_odt_${inject_num}_$$"
    
    
    mkdir -p "$temp_dir"
    unzip -q "$TEMPLATE_FILE" -d "$temp_dir"
    sed -i "s/Team #/Team $TEAM/g" "$temp_dir/content.xml"
    sed -i "s/Inject #/Inject $inject_num/g" "$temp_dir/content.xml"
    sed -i "s/Team #/Team $TEAM/g" "$temp_dir/styles.xml"
    sed -i "s/Inject #/Inject $inject_num/g" "$temp_dir/styles.xml"

    if [[ -n "$DATE" ]]; then
        sed -i "s/03-21-2026/$DATE/g" "$temp_dir/content.xml"
        sed -i "s/03-21-2026/$DATE/g" "$temp_dir/styles.xml"
    fi
    
    cd "$temp_dir"
    zip -q -0 -X "../$output_file" mimetype
    zip -q -r "../$output_file" . -x mimetype
    cd ..
    rm -rf "$temp_dir"
}

for ((i=COPY_START; i<=COPY_END; i++)); do
    process_file "$i"
done

echo "Successfully created $NUM_FILES files:"
for ((i=COPY_START; i<=COPY_END; i++)); do
    echo "  - team${TEAM}-inject${i}.odt"
done

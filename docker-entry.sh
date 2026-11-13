#!/bin/bash

set -e

# Use login shell environment variables
source /etc/profile.d/cli.sh

# Usage instructions
usage () {
    echo "Usage: $0 OPTION..."
    echo "--branch            BRANCH          branch to clone"
    echo "--callback-url      URL             callback URL"
    echo "--commit            SHA             commit to check out"
    echo "--job-id            ID              job id"
    echo "--org               ORGANIZATION    organization name"
    echo "--pushed-at         DATETIME        date and time of push"
    echo "--repo              REPOSITORY      repository name"
    echo "--slug              SLUG            check50 slug"
    echo "--style50                           whether to use style50"
    echo "--token             TOKEN           GitHub access token used for cloning and pushing"
    echo "--help                              display help message"
    exit 1
}


# Get command-line args
while [ $# -gt 0 ]; do
    case $1 in
        --branch)
            shift
            BRANCH="$1"
            ;;

        --callback-url)
            shift
            CALLBACK_URL="$1"
            ;;

        --commit)
            shift
            COMMIT="$1"
            ;;

        --job-id)
            shift
            JOB_ID="$1"
            ;;

        --org)
            shift
            ORG="$1"
            ;;

        --pushed-at)
            shift
            PUSHED_AT="$1"
            ;;

        --repo)
            shift
            REPO="$1"
            ;;

        --slug)
            shift
            SLUG="$1"
            ;;

        --style50)
            STYLE=1
            ;;

        --token)
            shift
            TOKEN="$1"
            ;;

        *)
            usage
            ;;
    esac

    shift
done

# Clone repo
echo "Cloning $ORG/$REPO@$BRANCH..."
git clone --branch "$BRANCH" --single-branch "https://$TOKEN:x-oauth-basic@github.com/$ORG/$REPO.git"

# Checkout commit to be tested
echo "Changing directory to $REPO..."
cd $REPO

echo "Checking out $COMMIT..."
git checkout "$COMMIT"

# Construct tag name (note assumes system timezone is utc)
echo "Constructing tag name..."
TAG_NAME="$REPO-$BRANCH@$(date '+%Y%m%dT%H%M%S.%NZ')"
echo "Tag name is $TAG_NAME..."

# Squash commit
echo "Squashing commit..."
TAG_HASH="$(git commit-tree HEAD^{tree} -m "$TAG_NAME")"
echo "Tag hash is $TAG_HASH"

# Push tag
echo "Pushing tag $TAG_NAME ($TAG_HASH)..."
git push origin "$TAG_HASH:refs/tags/$TAG_NAME"

# Remove remote origin
echo "Removing remote origin..."
git remote remove origin

function sandbox() {
    eval "CHECK50_PRIVATE_KEY= TOKEN= PYTHON_COLORS=0 $@"
}

# Get style50 result
#
# style50 must never cost a submission its check50 results. This Job has a 2 minute
# deadline and the callback only accepts a modestly sized payload, yet a single
# vendored asset such as a 230 KB bootstrap.min.css makes style50 spend the better
# part of a minute on a character-level diff and emit a payload of several hundred KB,
# after which no results are recorded at all. So: skip minified assets, bound the run
# time, keep the payload small, and fall back to null on any failure instead of
# exiting (set -e).
STYLE50_RESULT_DEFAULT="null"
STYLE50_RESULT="$STYLE50_RESULT_DEFAULT"
STYLE50_TIMEOUT="${STYLE50_TIMEOUT:-60}"
# Compact size after which diffs are dropped so the payload stays within what the
# callback accepts, with headroom for it being re-serialized less compactly.
STYLE50_MAX_BYTES="${STYLE50_MAX_BYTES:-49152}"
STYLE50_OMITTED_DIFF="(diff omitted: result too large to store)"

if [ "$STYLE" == "1" ]; then
    echo "Running style50 (timeout ${STYLE50_TIMEOUT}s)..."
    STYLE50_OUT="$(mktemp)"

    # --ignore patterns are fnmatch'ed against the full path, so a leading * also spans directories
    if sandbox "timeout $STYLE50_TIMEOUT style50 --verbose --ignore \*/.\* --ignore \*.min.css --ignore \*.min.js --output=json \$PWD" > "$STYLE50_OUT" \
        && STYLE50_RESULT="$(jq -c . "$STYLE50_OUT")" \
        && [ -n "$STYLE50_RESULT" ]; then

        # Files that already look good have their diff hidden by the renderer, so drop those first
        if [ "$(printf %s "$STYLE50_RESULT" | wc -c)" -gt "$STYLE50_MAX_BYTES" ]; then
            echo "style50 result exceeds $STYLE50_MAX_BYTES bytes, dropping diffs of files that look good..."
            STYLE50_RESULT="$(jq -c '.files |= map(if .score == 1 then del(.diff) else . end)' <<<"$STYLE50_RESULT")"
        fi

        # Still too large: keep every file's score but replace the diffs with a note
        if [ "$(printf %s "$STYLE50_RESULT" | wc -c)" -gt "$STYLE50_MAX_BYTES" ]; then
            echo "style50 result still exceeds $STYLE50_MAX_BYTES bytes, dropping all diffs..."
            STYLE50_RESULT="$(jq -c --arg note "$STYLE50_OMITTED_DIFF" '.files |= map(if has("diff") then .diff = $note else . end)' <<<"$STYLE50_RESULT")"
        fi
    else
        echo "style50 failed or timed out, recording null..."
        STYLE50_RESULT="$STYLE50_RESULT_DEFAULT"
    fi

    echo "style50 result is $STYLE50_RESULT"
else
    echo "STYLE is $STYLE. Skipping style50..."
fi

# Get check50 result
CHECK50_OUT="$(mktemp)"
echo -n "null" > "$CHECK50_OUT"

if [ -n "$SLUG" ]; then
    echo "Cloning checks at $SLUG..."
    cd ..
    python3 -c "import lib50, os, sys; lib50.set_local_path(os.getenv('CHECK50_PATH')); lib50.local(sys.argv[1], github_token=sys.argv[2], remove_origin=True)" "$SLUG" "$TOKEN"
    cd $REPO

    echo "Running check50..."
    sandbox "check50 --local --no-download-checks --log-level=debug --output=json --output-file='$CHECK50_OUT' '$SLUG'" || true
else
    echo "slug is empty, skipping check50..."
fi

CHECK50_RESULT=$(cat $CHECK50_OUT)
echo "check50 result is $CHECK50_RESULT"

# Construct payload
PAYLOAD="{ \
    \"id\": \"$JOB_ID\", \
    \"org\": \"$ORG\", \
    \"repo\": \"$REPO\", \
    \"slug\": \"$BRANCH\", \
    \"commit_hash\": \"$COMMIT\", \
    \"style50\": $STYLE50_RESULT, \
    \"check50\": $CHECK50_RESULT, \
    \"tag_hash\": \"$TAG_HASH\", \
    \"pushed_at\": \"$PUSHED_AT\"
}"

echo "Payload is $PAYLOAD"
echo "Compacting payload..."
PAYLOAD="$(jq -c . <<<"$PAYLOAD")"
echo "Compact payload is $PAYLOAD"

echo "Signing payload..."
SIGNATURE="$(openssl dgst -sha512 -sigopt rsa_padding_mode:pss -sigopt rsa_pss_saltlen:-2 -sign <(echo -e "$CHECK50_PRIVATE_KEY") <(echo -n "$PAYLOAD") | openssl base64 -A)"

# Send payload to callback URL
echo "Sending payload to $CALLBACK_URL..."
echo -n "$PAYLOAD" | curl --header "Content-Type: application/json" --header "X-Payload-Signature: $SIGNATURE" --data @- "$CALLBACK_URL"

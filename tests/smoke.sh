#!/bin/bash
# Smoke-tests a built cs50/check image before it is pushed. Usage: tests/smoke.sh [IMAGE]
# Run from the repository root (it mounts dependencies/python/requirements.txt).
#
# The Dockerfile only proves that apt-get and pip3 exited 0. Everything a check50 job
# needs at runtime is exercised here, so that a rebuild whose only change is upstream
# (cs50/cli:latest, a nightly wheel) cannot publish a broken grader image with a green
# Actions run. Each check has a timeout so that a regression that hangs fails loudly.

set -o errexit -o nounset -o pipefail

IMAGE="${1:-cs50/check}"
run() { timeout 300 docker run --rm --entrypoint "" "$@"; }

echo "Checking $IMAGE"

echo "- base image is Ubuntu 26.04, the runtime is Python 3.14, and jobs run as ubuntu"
run "$IMAGE" bash -c '
    . /etc/os-release && test "$VERSION_ID" = 26.04 || { echo "unexpected Ubuntu $VERSION_ID" >&2; exit 1; }
    python3 --version | grep -q "^Python 3\.14\." || { echo "unexpected $(python3 --version)" >&2; exit 1; }
    test "$(id -un)" = ubuntu || { echo "expected to run as ubuntu, got $(id -un)" >&2; exit 1; }
'

echo "- every pinned requirement is installed at its pinned version"
run --volume "$PWD/dependencies/python/requirements.txt:/tmp/requirements.txt:ro" "$IMAGE" bash -c '
    grep -v "^git+" /tmp/requirements.txt > /tmp/pins.txt
    pip3 install --quiet --no-index --dry-run --requirement /tmp/pins.txt
' || { echo "installed packages do not satisfy requirements.txt" >&2; exit 1; }

echo "- the Python stack imports, tf.keras is Keras 3 in a job that imports tensorflow, and models train"
run --interactive "$IMAGE" python3 - <<'EOF'
import importlib

for name in ["numpy", "pandas", "sklearn", "cv2", "nltk", "cffi", "PIL", "plotly", "flask", "check50", "lib50"]:
    importlib.import_module(name)

import numpy as np
import tensorflow as tf
import tf_keras
import keras

print("tensorflow", tf.__version__)
tf_keras_version = getattr(tf.keras, "__version__", None)  # tf_keras's tf.keras has no __version__
print("tf.keras", tf_keras_version, "| keras", keras.__version__, "| tf_keras", tf_keras.__version__)
print("cv2", __import__("cv2").__version__, "| numpy", np.__version__)

# tf.keras must be Keras 3: this image has shipped Keras 3 to graders since tf-nightly
# replaced stable tensorflow, and TF_USE_LEGACY_KERAS is deliberately not set.
assert tf_keras_version and tf_keras_version.startswith("3."), \
    f"tf.keras resolved to {tf.keras.Sequential.__module__} ({tf_keras_version}); expected Keras 3"
assert tf_keras.__version__.startswith("2."), f"tf_keras is {tf_keras.__version__}, expected Keras 2"

# tf.keras trains and evaluates a model end to end (the path a CS50 AI check exercises)
x = np.random.rand(64, 4).astype("float32")
y = (x.sum(axis=1) > 2).astype("int32")
model = tf.keras.Sequential([
    tf.keras.layers.Input(shape=(4,)),
    tf.keras.layers.Dense(8, activation="relu"),
    tf.keras.layers.Dense(1, activation="sigmoid"),
])
model.compile(optimizer="adam", loss="binary_crossentropy", metrics=["accuracy"])
model.fit(x, y, epochs=1, verbose=0)
model.evaluate(x, y, verbose=0)

# nltk data baked into the image is found without a download
import nltk
assert nltk.sent_tokenize("Hello there. General Kenobi.") == ["Hello there.", "General Kenobi."]

# cv2 and sklearn do real work against the pinned numpy
import cv2
assert cv2.resize(np.zeros((8, 8, 3), dtype="uint8"), (4, 4)).shape == (4, 4, 3)
from sklearn.neighbors import KNeighborsClassifier
assert KNeighborsClassifier(n_neighbors=1).fit(x, y).predict(x[:1]).shape == (1,)
print("OK")
EOF

echo "- transformers' TF model classes load (they run on tf_keras / Keras 2 in their own process)"
run --interactive "$IMAGE" python3 - <<'EOF'
import numpy as np
import transformers
from transformers import BertConfig, TFBertForMaskedLM  # TFBert*: the TF classes 4.x keeps and 5.x drops
import tf_keras

print("transformers", transformers.__version__)
# Build a tiny TF BERT from config (no download) and run a forward pass
model = TFBertForMaskedLM(BertConfig(vocab_size=100, hidden_size=16, num_hidden_layers=1, num_attention_heads=2, intermediate_size=32))
out = model(np.array([[1, 2, 3, 4]], dtype="int32"))
assert out.logits.shape == (1, 4, 100), out.logits.shape
assert isinstance(model, tf_keras.Model), type(model).__mro__
print("OK")
EOF

echo "- check50 and style50 entry points import and parse their arguments"
run "$IMAGE" bash -c 'check50 --help > /dev/null && style50 --help > /dev/null'

echo "- style50 skips minified assets, bounds its runtime, and keeps its payload small"
# Regression test for submissions that vendor e.g. bootstrap.min.css: style50 used to spend
# the Job's whole deadline on a character diff of it and emit a payload too big to record,
# so no results were ever recorded. Runs the style50 block of docker-entry.sh as the Job does.
run --volume "$PWD/docker-entry.sh:/docker-entry.sh:ro" "$IMAGE" bash -c '
    set -o errexit
    mkdir -p /tmp/sub/static && cd /tmp/sub
    printf "import sys\n\n\ndef main():\n    print(\"hi\")\n\n\nmain()\n" > app.py
    python3 -c "print(\"\".join(f\".c{i}{{color:red;margin:{i}px}}\" for i in range(20000)))" > static/bootstrap.min.css
    cp static/bootstrap.min.css static/vendored.css
    STYLE=1
    function sandbox() { eval "CHECK50_PRIVATE_KEY= TOKEN= PYTHON_COLORS=0 $@"; }
    eval "$(sed -n "/^# Get style50 result/,/^# Get check50 result/p" /docker-entry.sh | sed "\$d")"
    jq -e "
        (.files | map(.name) | any(endswith(\"bootstrap.min.css\")) | not)
        and (.files | map(select(.name | endswith(\"vendored.css\")) | .diff) == [\"(diff omitted: result too large to store)\"])
        and (.files | map(select(.name | endswith(\"app.py\")) | .score) == [1])
    " <<<"$STYLE50_RESULT" > /dev/null
    test "$(printf %s "$STYLE50_RESULT" | wc -c)" -le 49152
' || { echo "docker-entry.sh style50 block did not handle a large minified asset" >&2; exit 1; }

echo "- R loads tidyverse and the pinned testthat"
run "$IMAGE" Rscript -e '
    suppressPackageStartupMessages({ library(tidyverse); library(testthat) })
    stopifnot(packageVersion("testthat") == "3.3.2")
    expect_equal(nrow(filter(tibble(x = 1:3), x > 1)), 2L)
'

echo "- docker-entry.sh is the entrypoint and prints usage"
docker inspect --format '{{json .Config.Entrypoint}}' "$IMAGE" | grep -q '"/docker-entry.sh"'
out=$(timeout 60 docker run --rm "$IMAGE" --help 2>&1 || true)
grep -q '^Usage:' <<< "$out" || { printf "docker-entry.sh --help did not print usage:\n%s\n" "$out" >&2; exit 1; }

echo "OK"

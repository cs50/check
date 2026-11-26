#!/bin/bash
# Smoke-tests a built cs50/check image before it is pushed. Usage: tests/smoke.sh [IMAGE]
# Run from the repository root (it mounts dependencies/python/).
#
# The Dockerfile only proves that apt-get and pip3 exited 0. Everything a check50 job
# needs at runtime is exercised here, so that a rebuild whose only change is upstream
# (cs50/cli:latest, a nightly wheel) cannot publish a broken grader image with a green
# Actions run. Each check has a timeout so that a regression that hangs fails loudly.

set -o errexit -o nounset -o pipefail

IMAGE="${1:-cs50/check}"
TF_PREFIX="/opt/tensorflow"
TF="$TF_PREFIX/bin"
run() { timeout 300 docker run --rm --entrypoint "" --env TF_PREFIX="$TF_PREFIX" --env TF="$TF" "$@"; }

# Assertions shared by both runtimes: the non-TensorFlow stack imports and does real work
STACK_CHECK=$(cat <<'EOF'
import importlib

for name in ["numpy", "pandas", "sklearn", "cv2", "nltk", "cffi", "PIL", "plotly", "flask", "check50", "lib50"]:
    importlib.import_module(name)

import numpy as np
import nltk
import cv2
from sklearn.neighbors import KNeighborsClassifier

print("cv2", cv2.__version__, "| numpy", np.__version__)
assert nltk.sent_tokenize("Hello there. General Kenobi.") == ["Hello there.", "General Kenobi."]
assert cv2.resize(np.zeros((8, 8, 3), dtype="uint8"), (4, 4)).shape == (4, 4, 3)
x = np.random.rand(64, 4).astype("float32")
y = (x.sum(axis=1) > 2).astype("int32")
assert KNeighborsClassifier(n_neighbors=1).fit(x, y).predict(x[:1]).shape == (1,)
EOF
)

echo "Checking $IMAGE"

echo "- base image is Ubuntu 26.04, the TensorFlow runtime is our Python 3.14 build, and jobs run as ubuntu"
run "$IMAGE" bash -c '
    . /etc/os-release && test "$VERSION_ID" = 26.04 || { echo "unexpected Ubuntu $VERSION_ID" >&2; exit 1; }
    echo "  default runtime: $(command -v python3) is $(python3 --version)"
    python3 -c "import sys; assert sys.version_info >= (3, 14), sys.version" || exit 1
    echo "  TensorFlow runtime: $TF/python3 is $($TF/python3 --version)"
    $TF/python3 --version | grep -q "^Python 3\.14\." || { echo "unexpected $($TF/python3 --version)" >&2; exit 1; }
    $TF/python3 -c "import sys, sysconfig; assert sys.prefix == \"$TF_PREFIX\", sys.prefix; a = sysconfig.get_config_var(\"CONFIG_ARGS\"); missing = [f for f in (\"--enable-optimizations\", \"--enable-shared\", \"--with-lto\") if f not in a]; sys.exit(f\"CONFIG_ARGS lacks {missing}: {a}\" if missing else 0)" || exit 1
    ldd $TF/python3 | grep -q "libpython3.14.so.1.0 => $TF_PREFIX/lib/" || { echo "TensorFlow runtime does not resolve libpython from its prefix:"; ldd $TF/python3; exit 1; } >&2
    $TF/python3 -c "import bz2, ctypes, curses, decimal, lzma, readline, sqlite3, ssl, zlib" || exit 1
    test "$(id -un)" = ubuntu || { echo "expected to run as ubuntu, got $(id -un)" >&2; exit 1; }
'

echo "- every pinned requirement is installed at its pinned version, in each runtime"
run --volume "$PWD/dependencies/python:/tmp/deps:ro" "$IMAGE" bash -c '
    grep -v "^git+" /tmp/deps/requirements.txt > /tmp/pins.txt
    grep -v "^git+" /tmp/deps/requirements-tensorflow.txt > /tmp/pins-tensorflow.txt
    pip3 install --quiet --no-index --dry-run --requirement /tmp/pins.txt || { echo "default runtime does not satisfy requirements.txt" >&2; exit 1; }
    $TF/pip install --quiet --no-index --dry-run --requirement /tmp/pins.txt --requirement /tmp/pins-tensorflow.txt || { echo "TensorFlow runtime does not satisfy requirements.txt + requirements-tensorflow.txt" >&2; exit 1; }
'

echo "- the default runtime imports the Python stack and does real work, and has no TensorFlow (so cs50/cli need not wait for it)"
run --interactive "$IMAGE" python3 - <<EOF
$STACK_CHECK

for name in ["tensorflow", "tf_keras", "keras", "transformers"]:
    try:
        importlib.import_module(name)
    except ImportError:
        pass
    else:
        raise SystemExit(f"{name} is importable on the default runtime; it belongs only to the TensorFlow runtime")
print("OK")
EOF

echo "- the TensorFlow runtime imports the same stack plus TensorFlow, tf.keras is Keras 3 in a job that imports tensorflow, and models train"
run --interactive "$IMAGE" "$TF/python3" - <<EOF
$STACK_CHECK

import tensorflow as tf
import tf_keras
import keras

print("tensorflow", tf.__version__)
tf_keras_version = getattr(tf.keras, "__version__", None)  # tf_keras's tf.keras has no __version__
print("tf.keras", tf_keras_version, "| keras", keras.__version__, "| tf_keras", tf_keras.__version__)

# tf.keras must be Keras 3: this image has shipped Keras 3 to graders since tf-nightly
# replaced stable tensorflow, and TF_USE_LEGACY_KERAS is deliberately not set.
assert tf_keras_version and tf_keras_version.startswith("3."), \\
    f"tf.keras resolved to {tf.keras.Sequential.__module__} ({tf_keras_version}); expected Keras 3"
assert tf_keras.__version__.startswith("2."), f"tf_keras is {tf_keras.__version__}, expected Keras 2"

# tf.keras trains and evaluates a model end to end (the path a CS50 AI check exercises)
model = tf.keras.Sequential([
    tf.keras.layers.Input(shape=(4,)),
    tf.keras.layers.Dense(8, activation="relu"),
    tf.keras.layers.Dense(1, activation="sigmoid"),
])
model.compile(optimizer="adam", loss="binary_crossentropy", metrics=["accuracy"])
model.fit(x, y, epochs=1, verbose=0)
model.evaluate(x, y, verbose=0)
print("OK")
EOF

echo "- transformers' TF model classes load (they run on tf_keras / Keras 2 in their own process)"
run --interactive "$IMAGE" "$TF/python3" - <<'EOF'
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

echo "- check50-runtime routes checks that import TensorFlow to the TensorFlow runtime, and nothing else"
run "$IMAGE" bash -c '
    set -o errexit
    mkdir -p /tmp/checks/{traffic,attention,multi,shopping,comment,broken}
    printf "import numpy as np\nimport tensorflow as tf\nimport check50\n" > /tmp/checks/traffic/__init__.py
    printf "from transformers.tokenization_utils_base import BatchEncoding\n" > /tmp/checks/attention/__init__.py
    printf "import check50\ndef f():\n    import numpy, tensorflow as tf\n" > /tmp/checks/multi/__init__.py
    printf "import numpy, pandas\nimport check50\n" > /tmp/checks/shopping/__init__.py
    printf "# tensorflow is not used here\nx = \"import tensorflow\"\nimport check50\n" > /tmp/checks/comment/__init__.py
    printf "def (\n" > /tmp/checks/broken/__init__.py
    for d in traffic attention multi; do
        test "$(check50-runtime /tmp/checks/$d)" = "$TF" || { echo "$d should run on the TensorFlow runtime" >&2; exit 1; }
    done
    for d in shopping comment; do
        test -z "$(check50-runtime /tmp/checks/$d)" || { echo "$d should run on the default runtime" >&2; exit 1; }
    done
    # A check that cannot be parsed is left to check50 to report, so the job still runs
    out="$(check50-runtime /tmp/checks/broken)" || { echo "check50-runtime failed on an unparsable check (exit $?)" >&2; exit 1; }
    test -z "$out" || { echo "broken should run on the default runtime" >&2; exit 1; }
'

echo "- check50 on the TensorFlow runtime grades a submission whose checks import tensorflow and load student code in-process, within a job's 1 GiB and 1.2 CPUs"
# The cluster runs each job with these limits (submit.cs50.io's Job spec). check50 starts a worker per CPU the
# node reports, and each worker imports TensorFlow, so without docker-entry.sh's CHECK50_WORKERS=1 the pod is
# OOM-killed and the student never gets a result. Run under the same limits so that regressing it fails here.
run --interactive --memory 1g --memory-swap 1g --cpus 1.2 "$IMAGE" bash -c '
    set -o errexit
    mkdir -p /tmp/checks/traffic /tmp/submission
    cat > /tmp/checks/traffic/.cs50.yml <<YML
check50:
  files:
    - !require traffic.py
YML
    cat > /tmp/checks/traffic/__init__.py <<PY
import sys
import tensorflow as tf
import check50
import check50.py

@check50.check()
def exists():
    """traffic.py exists"""
    check50.exists("traffic.py")

@check50.check(exists)
def get_model_is_model():
    """get_model returns a Keras model"""
    sys.path = [""] + sys.path
    traffic = check50.py.import_("traffic.py")
    if not isinstance(traffic.get_model(), tf.keras.Model):
        raise check50.Failure("expected a model")

@check50.check(exists)
def python3_is_tensorflow_runtime():
    """python3 spawned by a check is the TensorFlow runtime"""
    # Prove the interpreter (prefix + version) without importing TensorFlow a second time: the parent
    # and the worker already hold it, and a third copy would not fit the 1 GiB a job gets. Real checks
    # do not spawn TensorFlow subprocesses either; they load student code in-process.
    check50.run("python3 -c \"import sys, importlib.util; print(sys.prefix, sys.version_info[:2], importlib.util.find_spec(str(sys.argv[1])) is not None)\" tensorflow").stdout("/opt/tensorflow (3, 14) True\n", regex=False).exit(0)
PY
    cat > /tmp/submission/traffic.py <<PY
import cv2
import numpy as np
import tensorflow as tf
from sklearn.model_selection import train_test_split

def get_model():
    model = tf.keras.Sequential([tf.keras.layers.Input(shape=(30, 30, 3)), tf.keras.layers.Flatten(), tf.keras.layers.Dense(43, activation="softmax")])
    model.compile(optimizer="adam", loss="categorical_crossentropy", metrics=["accuracy"])
    return model
PY
    # The same PATH switch and worker count docker-entry.sh sets for a job check50-runtime routes here
    export PATH="$(check50-runtime /tmp/checks/traffic):$PATH"
    export CHECK50_WORKERS=1
    test "$(command -v check50)" = "$TF/check50" || { echo "check50 did not resolve to the TensorFlow runtime: $(command -v check50)" >&2; exit 1; }
    cd /tmp/submission
    PYTHON_COLORS=0 check50 --dev --output=json --output-file=/tmp/result.json /tmp/checks/traffic || true
    jq -e "(.results | length) == 3 and all(.results[]; .passed == true)" /tmp/result.json > /dev/null \
        || { echo "check50 on the TensorFlow runtime did not pass every check:" >&2; jq . /tmp/result.json >&2; exit 1; }
    jq -r ".results[] | \"    \\(.passed) \\(.description)\"" /tmp/result.json
'

echo "- check50 and style50 entry points import and parse their arguments"
run "$IMAGE" bash -c 'check50 --help > /dev/null && style50 --help > /dev/null'

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

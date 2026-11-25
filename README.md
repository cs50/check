# cs50/check

https://cs50.readthedocs.io/cs50/check/

## Python runtimes

The image has two Python runtimes, and `docker-entry.sh` picks one per job:

- **cs50/cli's `python3`** (`/usr/local/bin/python3`) is the default. It gets
  `dependencies/python/requirements.txt`.
- **`/opt/tensorflow`** is a venv on Ubuntu 26.04's `python3.14` that gets the same
  `requirements.txt` plus `dependencies/python/requirements-tensorflow.txt`. A job
  runs on it when `check50-runtime` finds that its checks import `tensorflow`,
  `tf_keras`, `keras`, or `transformers` (e.g. `ai50/projects/traffic` and `attention`,
  which import TensorFlow in the check module and load student code in-process).

This keeps TensorFlow, which trails new Python releases by about a year, from
holding back the Python version in `cs50/cli` ([cs50/cli#254](https://github.com/cs50/cli/issues/254)).
Once the TensorFlow stack has wheels for cs50/cli's Python, fold
`requirements-tensorflow.txt` back into `requirements.txt` and drop the second runtime.

`make build` then `make test` (or `bash tests/smoke.sh IMAGE`) exercises both runtimes
the way CI does before pushing.

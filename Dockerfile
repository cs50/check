# Base image tag (e.g., ubuntu-26.04 to build on a specific release of cs50/cli)
ARG TAG=latest
FROM cs50/cli:${TAG}

USER root

ARG DEBIANFRONTEND=noninteractive

# Remove customized R from cs50/cli
RUN rm -rf /opt/cs50/bin/R

# Install additional Ubuntu packages
RUN apt-get update -qq && apt-get install -y \
    cmake \
    g++ \
    jq \
    pkg-config

# Dependencies for OpenCV
RUN apt-get install -y libgl1

# Install Python packages from requirements file
COPY dependencies/python/requirements.txt /tmp/requirements.txt
RUN pip3 install --no-cache-dir -r /tmp/requirements.txt

# Install nltk data
RUN python3 -c "import nltk; nltk.download('punkt_tab', download_dir='/usr/share/nltk_data/')"

# Python 3.14 runtime for checks that import TensorFlow
#
# The TensorFlow stack lags new Python releases by about a year (cp314 wheels arrived
# eleven months after 3.14.0), and cs50/cli's python3 should not have to wait for it
# (cs50/cli#254). So TensorFlow is installed into its own CPython 3.14 at /opt/tensorflow,
# and check50-runtime routes a job onto it when its checks import the stack. Each runtime
# gets the same requirements.txt, so a check behaves the same on either; only the
# TensorFlow packages differ. Replace this runtime with cs50/cli's python3 once the stack
# supports it.
#
# Built from source with cs50/cli's configure flags, so these checks grade on the same
# interpreter students had on 3.14. (Ubuntu 26.04's python3.14 package stays at 3.14.4
# for the life of the release, with security fixes only.) The rpath keeps libpython
# resolving from the prefix without an ld.so.conf entry.
ENV TENSORFLOW_RUNTIME=/opt/tensorflow
RUN apt-get update -qq && apt-get install -y \
    libbz2-dev \
    libffi-dev \
    liblzma-dev \
    libncursesw5-dev \
    libreadline-dev \
    libsqlite3-dev \
    libssl-dev \
    zlib1g-dev
COPY dependencies/python/requirements-tensorflow.txt /tmp/requirements-tensorflow.txt
RUN cd /tmp && \
    curl --remote-name https://www.python.org/ftp/python/3.14.10/Python-3.14.10.tgz && \
    tar xzf Python-3.14.10.tgz && \
    rm --force Python-3.14.10.tgz && \
    cd Python-3.14.10 && \
    CFLAGS="-Os" LDFLAGS="-Wl,-rpath,${TENSORFLOW_RUNTIME}/lib" ./configure --prefix="$TENSORFLOW_RUNTIME" --disable-static --enable-optimizations --enable-shared --with-lto --without-tests && \
    make -j "$(nproc)" && \
    make install && \
    cd .. && \
    rm --force --recursive Python-3.14.10 && \
    ln --relative --symbolic "$TENSORFLOW_RUNTIME/bin/pip3" "$TENSORFLOW_RUNTIME/bin/pip" && \
    ln --relative --symbolic "$TENSORFLOW_RUNTIME/bin/python3" "$TENSORFLOW_RUNTIME/bin/python" && \
    "$TENSORFLOW_RUNTIME/bin/pip" install --no-cache-dir --upgrade "pip>=26.2.2" `# GHSA-6q48-6c7w-9gw2` && \
    "$TENSORFLOW_RUNTIME/bin/pip" install --no-cache-dir -r /tmp/requirements.txt -r /tmp/requirements-tensorflow.txt && \
    rm /tmp/requirements.txt /tmp/requirements-tensorflow.txt

COPY ./check50-runtime /usr/local/bin/check50-runtime
RUN chmod 755 /usr/local/bin/check50-runtime

# Fail the build, not a check50 job, if the TF stack does not import together.
# Order matters: `tf.keras` is resolved on first use, and loading transformers' TF
# model classes sets TF_USE_LEGACY_KERAS=1 in that process, so tf.keras is checked
# first, as a check50 job that imports tensorflow alone would see it (Keras 3).
RUN "$TENSORFLOW_RUNTIME/bin/python3" -c "\
import sys; assert sys.version_info[:2] == (3, 14), sys.version; \
import tensorflow as tf, tf_keras; \
v = getattr(tf.keras, '__version__', None); \
assert v and v.startswith('3.'), f'tf.keras resolved to {tf.keras.Sequential.__module__} ({v}); expected Keras 3'; \
assert tf_keras.__version__.startswith('2.'), tf_keras.__version__; \
from transformers import TFBertForMaskedLM"

# Install R and dependencies for tidyverse library
RUN apt-get update -qq && apt-get install -y \
    automake \
    build-essential \
    libhdf5-dev `# For R` \
    liblapack3 `# For R` \
    libpangocairo-1.0-0 `# For R` \
    libtiff6 `# For R` \
    libxt6 `# For R` \
    libssl-dev \
    libxml2-dev \
    libfontconfig1-dev \
    libfreetype6-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libtool \
    libpng-dev \
    libjpeg-dev \
    libcairo2-dev \
    libtiff-dev \
    libpcre2-dev \
    libcurl4-gnutls-dev \
    libuv1-dev `# For R 'fs' (transitive dep of pkgload, tidyverse, etc.)` \
    r-base

# Install R libraries
RUN R -e "install.packages(c(\
    'desc', \
    'pkgbuild', \
    'pkgload', \
    'praise', \
    'rprojroot', \
    'tidyverse', \
    'waldo'), repos='https://cloud.r-project.org')"

# Pinned R packages required by testthat. Try Archive/ first (stable URL for
# any past version), fall back to src/contrib/ while a pin is the current release.
RUN set -e; cd /tmp; for pkg in \
        brio:1.1.5 \
        diffobj:0.3.6 \
        testthat:3.3.2; do \
      name="${pkg%:*}"; tarball="${name}_${pkg#*:}.tar.gz"; \
      wget -q "https://cloud.r-project.org/src/contrib/Archive/${name}/${tarball}" \
        || wget -q "https://cloud.r-project.org/src/contrib/${tarball}"; \
      tar -xzf "${tarball}"; \
      R CMD INSTALL -l /usr/local/lib/R/site-library "${name}" --no-test-load --no-clean-on-error; \
      rm -rf "${name}" "${tarball}"; \
    done

COPY ./docker-entry.sh /
# Explicit mode: COPY keeps the build host's file mode, and the ubuntu user must be
# able to read the script, not just execute it, for bash to run it
RUN chmod 755 /docker-entry.sh

RUN sed -i '/^ubuntu ALL=(ALL) NOPASSWD:ALL$/d' /etc/sudoers

USER ubuntu
ENV PATH="/opt/cs50/bin:/opt/bin:${PATH}"

# Clone checks
ENV CHECK50_PATH="~/.local/share/check50"

# Configure git
RUN git config --global user.name bot50 && \
    git config --global user.email bot@cs50.harvard.edu

ENTRYPOINT [ "/docker-entry.sh" ]

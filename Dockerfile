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
RUN pip3 install --no-cache-dir -r /tmp/requirements.txt && \
    rm /tmp/requirements.txt

# Fail the build, not a check50 job, if the TF stack does not import together.
# Order matters: `tf.keras` is resolved on first use, and loading transformers' TF
# model classes sets TF_USE_LEGACY_KERAS=1 in that process, so tf.keras is checked
# first, as a check50 job that imports tensorflow alone would see it (Keras 3).
RUN python3 -c "\
import tensorflow as tf, tf_keras; \
v = getattr(tf.keras, '__version__', None); \
assert v and v.startswith('3.'), f'tf.keras resolved to {tf.keras.Sequential.__module__} ({v}); expected Keras 3'; \
assert tf_keras.__version__.startswith('2.'), tf_keras.__version__; \
from transformers import TFBertForMaskedLM"

# Install nltk data
RUN python3 -c "import nltk; nltk.download('punkt_tab', download_dir='/usr/share/nltk_data/')"

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

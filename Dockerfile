FROM cs50/cli:amd64

USER root

ARG DEBIANFRONTEND=noninteractive


RUN apt-get update -qq && apt-get install -y jq cmake


# Suggested build environment for Python, per pyenv, even though we're building ourselves
# https://github.com/pyenv/pyenv/wiki#suggested-build-environment
RUN apt update && \
    apt install --no-install-recommends --yes \
        make build-essential libssl-dev zlib1g-dev \
        libbz2-dev libreadline-dev libsqlite3-dev llvm wget unzip \
        libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev && \
        apt clean && \
        rm -rf /var/lib/apt/lists/*


# Install Python 3.12.x
# https://www.python.org/downloads/
RUN cd /tmp && \
    curl https://www.python.org/ftp/python/3.12.0/Python-3.12.0.tgz --output Python-3.12.0.tgz && \
    tar xzf Python-3.12.0.tgz && \
    rm --force Python-3.12.0.tgz && \
    cd Python-3.12.0 && \
    ./configure && \
    make && \
    make install && \
    cd .. && \
    rm --force --recursive Python-3.12.0 && \
    ln -f --relative --symbolic /usr/local/bin/pip3 /usr/local/bin/pip && \
    ln -f --relative --symbolic /usr/local/bin/python3 /usr/local/bin/python && \
    pip3 install --no-cache-dir --upgrade pip


# Install Python packages for Python 3.12.x
RUN apt update && \
    apt install --no-install-recommends --upgrade --yes libmagic-dev `# For style50` && \
    pip3 install --no-cache-dir \
        awscli \
        "check50<4" \
        compare50 \
        cs50 \
        Flask \
        Flask-Session \
        help50 \
        pytest \
        "pydantic<2" \
        render50 \
        s3cmd \
        setuptools \
        style50 \
        "submit50<4"


# Install additional Python packages
# TODO remove werkzeug after https://github.com/fengsp/flask-session/issues/99 is fixed
RUN pip3 install --no-cache-dir \
        flask_sqlalchemy \
        numpy \
        pandas \
        passlib \
        plotly \
        pytz \
        cffi \
        inflect \
        emoji \
        pyfiglet \
        multipledispatch \
        Pillow \
        tabulate \
        validators \
        validator-collection \
        fpdf2==2.7.6


# Install ML packages for CS50 AI
RUN pip3 install --no-cache-dir \
    nltk \
    opencv-python \
    scikit-learn \
    tf-nightly \
    transformers && \
    python3 -m nltk.downloader -d /usr/share/nltk_data/ punkt


# Install CS50 Python packages
RUN pip3 install cs50 --upgrade --no-cache-dir


# Install nltk data
RUN python3 -m nltk.downloader -d /usr/share/nltk_data/ punkt


COPY ./docker-entry.sh /
RUN chmod a+x /docker-entry.sh


RUN sed -i '/^ubuntu ALL=(ALL) NOPASSWD:ALL$/d' /etc/sudoers


USER ubuntu
ENV PATH="/opt/cs50/bin:/opt/bin:${PATH}"


# Clone checks
ENV CHECK50_PATH  "~/.local/share/check50"


# Configure git
RUN git config --global user.name bot50 && \
    git config --global user.email bot@cs50.harvard.edu


ENTRYPOINT [ "/docker-entry.sh" ]

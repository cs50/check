FROM cs50/cli:bionic

echo "root:thisis" | chpasswd
USER root


ARG DEBIANFRONTEND=noninteractive

RUN apt-get update -qq && apt-get install -y jq

# Install Python packages
# TODO remove werkzeug after https://github.com/fengsp/flask-session/issues/99 is fixed
RUN pip3 install \
        flask_sqlalchemy \
        nltk \
        numpy \
        pandas \
        passlib \
        plotly \
        pytz \
        cffi \
        'werkzeug<1.0.0' \
        'scikit-learn==0.22.1' \
        'tensorflow==2.3.1' \
        opencv-python && \
    python3 -m nltk.downloader -d /usr/share/nltk_data/ punkt

COPY ./docker-entry.sh /
RUN chmod a+x /docker-entry.sh

RUN sed -i '/^ubuntu ALL=(ALL) NOPASSWD:ALL$/d' /etc/sudoers

USER ubuntu

# Clone checks
ENV CHECK50_PATH  "~/.local/share/check50"

# Configure git
RUN git config --global user.name bot50 && \
    git config --global user.email bot@cs50.harvard.edu

ENTRYPOINT [ "/docker-entry.sh" ]

FROM cs50/baseimage

USER root

ARG DEBIANFRONTEND=noninteractive

# Install apt packages
RUN apt-get install --allow-downgrades -y openjdk-11-jdk-headless libcs50=8.1.2

# TODO remove after fixing check50 issue
RUN pip3 install pip==9

# Install Python packages
RUN pip3 install \
        flask_sqlalchemy \
        nltk \
        passlib \
        pytz && \
    python3 -m nltk.downloader -d /usr/share/nltk_data/ punkt

# check50 wrapper
COPY ./check50-wrapper /usr/local/bin/
RUN chmod a+x /usr/local/bin/check50-wrapper

USER ubuntu

# Clone checks
RUN git clone -b master https://github.com/cs50/checks.git ~/.local/share/check50/cs50/checks/

# Configure git
RUN git config --global user.name bot50 && \
    git config --global user.email bot@cs50.harvard.edu

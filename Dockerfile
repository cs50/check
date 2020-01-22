FROM cs50/cli

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
        werkzeug && \
    python3 -m nltk.downloader -d /usr/share/nltk_data/ punkt

COPY ./docker-entry /usr/local/bin/
RUN chmod a+x /usr/local/bin/docker-entry

RUN sed -i '/^ubuntu ALL=(ALL) NOPASSWD:ALL$/d' /etc/sudoers

USER ubuntu

# Clone checks
RUN git clone -b 2020/x https://github.com/cs50/problems.git ~/.local/share/check50/cs50/problems/

# Configure git
RUN git config --global user.name bot50 && \
    git config --global user.email bot@cs50.harvard.edu

ENV CHECK50_WORKERS "4"

CMD [ "/usr/local/bin/docker-entry" ]

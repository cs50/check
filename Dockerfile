FROM cs50/baseimage

USER root

ARG DEBIANFRONTEND=noninteractive

RUN apt-get update -qq && apt-get install -y jq

# Install Python packages
# TODO remove werkzeug after https://github.com/fengsp/flask-session/issues/99 is fixed
RUN pip3 install \
        flask_sqlalchemy \
        nltk \
        passlib \
        plotly \
        pytz \
        'werkzeug<0.15' && \
    python3 -m nltk.downloader -d /usr/share/nltk_data/ punkt

RUN pip3 install --upgrade git+git://github.com/cs50/check50@develop git+git://github.com/cs50/style50@develop

# check50 wrapper
COPY ./docker-entry /usr/local/bin/
RUN chmod a+x /usr/local/bin/docker-entry

USER ubuntu

# Clone checks
RUN git clone -b 2019/x https://github.com/cs50/problems.git ~/.local/share/check50/cs50/problems/

# Configure git
RUN git config --global user.name bot50 && \
    git config --global user.email bot@cs50.harvard.edu

CMD [ "/usr/local/bin/docker-entry" ]

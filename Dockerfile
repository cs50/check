FROM cs50/cli:amd64

USER root

ARG DEBIANFRONTEND=noninteractive

RUN apt-get update -qq && apt-get install -y jq

# Install Python packages
# TODO remove werkzeug after https://github.com/fengsp/flask-session/issues/99 is fixed
RUN pip3 install --no-cache-dir \
        flask_sqlalchemy \
        nltk \
        numpy \
        pandas \
        passlib \
        plotly \
        pytz \
        cffi \
        opencv-python \
        inflect \
        emoji \
        pyfiglet \
        multipledispatch \
        Pillow \
        tabulate \
        validators \
        validator-collection \
        fpdf2==2.7.6 \
        SQLAlchemy==1.4.49

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

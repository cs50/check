FROM cs50/cli:amd64

USER root

ARG DEBIANFRONTEND=noninteractive


RUN apt-get update -qq && apt-get install -y jq cmake


# Install additional Python packages
# TODO remove werkzeug after https://github.com/fengsp/flask-session/issues/99 is fixed
RUN pip3 install --no-cache-dir \
        flask_sqlalchemy \
        numpy \
        pandas \
        passlib \
        plotly \
        pytz \
        cachelib \
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
    transformers==4.35.0


# Install nltk data
RUN python3 -m nltk.downloader -d /usr/share/nltk_data/ punkt


# Dependencies for OpenCV
RUN apt-get install -y libgl1


# Install CS50 Python packages
RUN pip3 install cs50 --upgrade --no-cache-dir


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

FROM cs50/common

# nltk and punkt data
RUN nltk && python -m nltk.downloader -d /usr/share/nltk_data/ punkt

# clone checks
RUN git clone -b master https://github.com/cs50/checks.git /home/ubuntu/.local/share/check50/cs50/checks

# check50 wrapper
COPY ./check50-wrapper /usr/local/bin/
RUN chmod a+x /usr/local/bin/check50-wrapper

# configure git
RUN git config --global user.name bot50 && \
    git config --global user.email bot@cs50.harvard.edu

# run shell in /root
RUN useradd --create-home --user-group ubuntu
WORKDIR /home/ubuntu/check/
RUN chown -R ubuntu:ubuntu /home/ubuntu/ && chmod -R 755 /home/ubuntu/
USER ubuntu

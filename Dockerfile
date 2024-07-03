FROM cs50/cli

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
    libpcre3-dev \
    libcurl4-gnutls-dev \
    r-base

# Install R libraries
RUN R -e "install.packages(c(\
    'desc', \
    'pkgbuild', \
    'pkgload', \
    'praise', \
    'rprojroot', \
    'tidyverse'), repos='http://cran.rstudio.com/')"

# brio (required by testthat)
RUN wget https://cloud.r-project.org/src/contrib/brio_1.1.5.tar.gz && \
    tar -xzf brio_1.1.5.tar.gz && \
    cd brio && \
    R CMD INSTALL -l /usr/local/lib/R/site-library . --no-test-load --no-clean-on-error --verbose && \
    cd src && \
    R CMD SHLIB brio.c && \
    mv brio.so /usr/local/lib/R/site-library/brio/libs/brio.so && \
    cd /home/ubuntu && \
    rm -rf brio brio_1.1.5.tar.gz

# diffobj (required by testthat and waldo)
RUN wget https://cloud.r-project.org/src/contrib/diffobj_0.3.5.tar.gz && \
    tar -xzf diffobj_0.3.5.tar.gz && \
    cd diffobj && \
    R CMD INSTALL -l /usr/local/lib/R/site-library . --no-test-load --no-clean-on-error --verbose && \
    cd src && \
    gcc -I/usr/share/R/include -DNDEBUG -fpic -O2 -c diff.c -o diff.o && \
    gcc -I/usr/share/R/include -DNDEBUG -fpic -O2 -c init.c -o init.o && \
    gcc -I/usr/share/R/include -DNDEBUG -fpic -O2 -c diffobj.c -o diffobj.o && \
    gcc -shared -o diffobj.so diff.o init.o diffobj.o -L/usr/lib/R/lib -lR && \
    mv diffobj.so /usr/local/lib/R/site-library/diffobj/libs/ && \
    cd /home/ubuntu && \
    rm -rf diffobj diffobj_0.3.5.tar.gz

# waldo (required by testthat)
RUN R -e "install.packages(c('waldo'), repos='http://cran.rstudio.com/')"

# testthat
RUN wget https://cran.r-project.org/src/contrib/testthat_3.2.1.1.tar.gz && \
    tar -xzf testthat_3.2.1.1.tar.gz && \
    cd testthat && \
    R CMD INSTALL -l /usr/local/lib/R/site-library . --no-test-load --no-clean-on-error --verbose && \
    cd src && \
    gcc -I/usr/share/R/include -DNDEBUG -fpic -O2 -c init.c -o init.o && \
    gcc -I/usr/share/R/include -DNDEBUG -fpic -O2 -c reassign.c -o reassign.o && \
    g++ -I/usr/share/R/include -I../inst/include -DNDEBUG -fpic -O2 -c test-catch.cpp -o test-catch.o && \
    g++ -I/usr/share/R/include -I../inst/include -DNDEBUG -fpic -O2 -c test-example.cpp -o test-example.o && \
    g++ -I/usr/share/R/include -I../inst/include -DNDEBUG -fpic -O2 -c test-runner.cpp -o test-runner.o && \
    g++ -shared -o testthat.so init.o reassign.o test-catch.o test-example.o test-runner.o -L/usr/lib/R/lib -lR && \
    mv testthat.so /usr/local/lib/R/site-library/testthat/libs/ && \
    cd /home/ubuntu && \
    rm -rf testthat testthat_3.2.1.1.tar.gz

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

# Pin inflect to 7.0.0
RUN pip3 install inflect==7.0.0 --no-cache-dir

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

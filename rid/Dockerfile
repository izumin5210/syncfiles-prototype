FROM node:10.15.0-stretch-slim as node
FROM ruby:2.5.3-slim-stretch


#  Timezone
#-----------------------------------------------
ENV TZ Asia/Tokyo


#  Locale
#-----------------------------------------------
RUN echo "ja_JP.UTF-8 UTF-8" > /etc/locale.gen \
  && apt-get update && apt-get install -y locales \
  && locale-gen ja_JP.UTF-8 \
  && update-locale LANG=ja_JP.UTF-8 \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*
ENV LC_CTYPE=ja_JP.UTF-8


#  Library
#-----------------------------------------------
RUN apt-get update && apt-get install -y \
    cmake \
    g++ \
    git \
    make \
    nodejs \
    # for installing private gem via ssh
    openssh-client \
    libpq-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*


#  Node.js
#-----------------------------------------------
COPY --from=node /opt/ /opt
COPY --from=node /usr/local/lib/ /usr/local/lib
COPY --from=node /usr/local/bin/ /usr/local/bin

#  App
#-----------------------------------------------
WORKDIR /app

RUN npm install --global smee-client

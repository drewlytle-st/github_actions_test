FROM amd64/ubuntu:latest
LABEL maintainer="devops@simplethread.com"

ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=America/New_York

RUN apt-get clean && \
  apt-get update -qq && \
  apt-get install -y \
  software-properties-common \
  build-essential \
  postgresql-client \
  libpq-dev \
  vim \
  openssh-server \
  iputils-ping \
  libxml2-dev \
  libxmlsec1-dev \
  libxmlsec1-openssl \
  pkg-config \
  bzip2 \
  ca-certificates \
  libffi-dev \
  libgmp-dev \
  libssl-dev \
  libyaml-dev \
  procps \
  shared-mime-info \
  zlib1g-dev \
  git 

# install ruby 2.7 from https://github.com/docker-library/ruby/blob/301b52c1bb0f109e8bdbb7b6178a022030ec37ee/2.7/slim-buster/Dockerfile
# skip installing gem documentation

RUN set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends \
  bzip2 \
  ca-certificates \
  libffi-dev \
  libgmp-dev \
  libssl-dev \
  libyaml-dev \
  procps \
  zlib1g-dev \
  ; \
  rm -rf /var/lib/apt/lists/*

# skip installing gem documentation
RUN set -eux; \
  mkdir -p /usr/local/etc; \
  { \
  echo 'install: --no-document'; \
  echo 'update: --no-document'; \
  } >> /usr/local/etc/gemrc

ENV LANG C.UTF-8
ENV RUBY_MAJOR 2.7
ENV RUBY_VERSION 2.7.4
ENV RUBY_DOWNLOAD_SHA256 2a80824e0ad6100826b69b9890bf55cfc4cf2b61a1e1330fccbcb30c46cef8d7

# some of ruby's build scripts are written in ruby
#   we purge system ruby later to make sure our final image uses what we just built
RUN set -eux; \
  \
  savedAptMark="$(apt-mark showmanual)"; \
  apt-get update; \
  apt-get install -y --no-install-recommends \
  bison \
  dpkg-dev \
  libgdbm-dev \
  ruby \
  autoconf \
  g++ \
  gcc \
  libbz2-dev \
  libgdbm-compat-dev \
  libglib2.0-dev \
  libncurses-dev \
  libreadline-dev \
  libxml2-dev \
  libxslt-dev \
  make \
  wget \
  xz-utils \
  ; \
  rm -rf /var/lib/apt/lists/*; \
  \
  wget -O ruby.tar.xz "https://cache.ruby-lang.org/pub/ruby/${RUBY_MAJOR%-rc}/ruby-$RUBY_VERSION.tar.xz"; \
  echo "$RUBY_DOWNLOAD_SHA256 *ruby.tar.xz" | sha256sum --check --strict; \
  \
  mkdir -p /usr/src/ruby; \
  tar -xJf ruby.tar.xz -C /usr/src/ruby --strip-components=1; \
  rm ruby.tar.xz; \
  \
  cd /usr/src/ruby; \
  \
  # hack in "ENABLE_PATH_CHECK" disabling to suppress:
  #   warning: Insecure world writable dir
  { \
  echo '#define ENABLE_PATH_CHECK 0'; \
  echo; \
  cat file.c; \
  } > file.c.new; \
  mv file.c.new file.c; \
  \
  autoconf; \
  gnuArch="$(dpkg-architecture --query DEB_BUILD_GNU_TYPE)"; \
  ./configure \
  --build="$gnuArch" \
  --disable-install-doc \
  --enable-shared \
  ; \
  make -j "$(nproc)"; \
  make install; \
  \
  apt-mark auto '.*' > /dev/null; \
  apt-mark manual $savedAptMark > /dev/null; \
  find /usr/local -type f -executable -not \( -name '*tkinter*' \) -exec ldd '{}' ';' \
  | awk '/=>/ { print $(NF-1) }' \
  | sort -u \
  | grep -vE '^/usr/local/lib/' \
  | xargs -r dpkg-query --search \
  | cut -d: -f1 \
  | sort -u \
  | xargs -r apt-mark manual \
  ; \
  apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
  \
  cd /; \
  rm -r /usr/src/ruby; \
  # verify we have no "ruby" packages installed
  if dpkg -l | grep -i ruby; then exit 1; fi; \
  [ "$(command -v ruby)" = '/usr/local/bin/ruby' ]; \
  # rough smoke test
  ruby --version; \
  gem --version; \
  bundle --version

# Install NodeJS
# RUN apt-get update \
#   && apt-get install -y curl \
#   && apt-get -y autoclean
# ENV NVM_DIR /usr/local/nvm
# ENV NODE_VERSION 14.17.3
# RUN curl --silent -o- https://raw.githubusercontent.com/creationix/nvm/v0.31.2/install.sh | bash
# RUN . $NVM_DIR/nvm.sh \
#   && nvm install $NODE_VERSION \
#   && nvm alias default $NODE_VERSION \
#   && nvm use default
# ENV NODE_PATH $NVM_DIR/v$NODE_VERSION/lib/node_modules
# ENV PATH $NVM_DIR/versions/node/v$NODE_VERSION/bin:$PATH
# RUN node -v
# RUN npm -v

# Install Yarn for webpacker
# RUN npm install -g yarn

# don't create ".bundle" in all our apps
ENV GEM_HOME /usr/local/bundle
ENV BUNDLE_SILENCE_ROOT_WARNING=1 \
  BUNDLE_APP_CONFIG="$GEM_HOME"
ENV PATH $GEM_HOME/bin:$PATH
# adjust permissions of a few directories for running "gem install" as an arbitrary user
RUN mkdir -p "$GEM_HOME" && chmod 777 "$GEM_HOME"

# Set work directory
WORKDIR /app

# Install ruby dependencies
COPY Gemfile Gemfile.lock /app/
COPY vendor/ /app/vendor/
RUN gem install bundler
RUN bundle config set --local without development:test
RUN bundle install
# copy app
COPY . /app/
# Install npm dependencies
# RUN npm install


# create folder for puma pid file
RUN mkdir -p /app/tmp/pids

# setup SSH
RUN mkdir /var/run/sshd
RUN mkdir -p /root/.ssh
RUN touch /root/.ssh/environment
RUN chmod 0600 /root/.ssh/environment
RUN sed -ie 's/#PermitUserEnvironment no/PermitUserEnvironment yes/g' /etc/ssh/sshd_config

# setup SSH keys
COPY ./docker/authorized_keys /root/.ssh/authorized_keys
RUN chmod 0600 /root/.ssh/authorized_keys

# copy ssh entrypoint and custom work scripts
COPY ./docker/ssh_entrypoint.sh /usr/local/bin
COPY ./docker/start_server.sh /usr/local/bin
COPY ./docker/work /usr/local/bin
RUN sed -i '/disable ghostscript format types/,+6d' /etc/ImageMagick-6/policy.xml
RUN chmod +x /usr/local/bin/ssh_entrypoint.sh
RUN chmod +x /usr/local/bin/start_server.sh
RUN chmod +x /usr/local/bin/work
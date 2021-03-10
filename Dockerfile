FROM php:7.3-apache

ARG ESPO_VERSION=6.1.4
ARG PROJECT_PATH=/usr/src/espocrm


# Install php libs
RUN set -ex; \
    \
    aptMarkList="$(apt-mark showmanual)"; \
    \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        libjpeg-dev \
        libpng-dev \
        libzip-dev \
        libxml2-dev \
        libc-client-dev \
        libkrb5-dev \
        libldap2-dev \
        libzmq3-dev \
        zlib1g-dev \
    ; \
    \
# Install php-zmq
    cd /usr; \
    curl -fSL https://github.com/zeromq/php-zmq/archive/e0db82c3286da81fa8945894dd10125a528299e4.tar.gz -o php-zmq.tar.gz; \
    tar -zxf php-zmq.tar.gz; \
    cd php-zmq*; \
    phpize && ./configure; \
    make; \
    make install; \
    cd .. && rm -rf php-zmq*; \
# END: Install php-zmq
    \
    debMultiarch="$(dpkg-architecture --query DEB_BUILD_MULTIARCH)"; \
    docker-php-ext-install pdo_mysql; \
    docker-php-ext-install zip; \
    docker-php-ext-configure gd --with-png-dir=/usr --with-jpeg-dir=/usr; \
    docker-php-ext-install gd; \
    docker-php-ext-configure imap --with-kerberos --with-imap-ssl; \
    docker-php-ext-install imap; \
    docker-php-ext-configure ldap --with-libdir="lib/$debMultiarch"; \
    docker-php-ext-install ldap; \
    docker-php-ext-install exif; \
    docker-php-ext-enable zmq; \
    \
# reset a list of apt-mark
    apt-mark auto '.*' > /dev/null; \
    apt-mark manual $aptMarkList; \
    ldd "$(php -r 'echo ini_get("extension_dir");')"/*.so \
        | awk '/=>/ { print $3 }' \
        | sort -u \
        | xargs -r dpkg-query -S \
        | cut -d: -f1 \
        | sort -u \
        | xargs -rt apt-mark manual; \
    \
    apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false

# Install required libs
RUN set -ex; \
    apt-get install -y --no-install-recommends \
        unzip \
        busybox-static \
    ; \
    rm -rf /var/lib/apt/lists/*; \
    \
    mkdir -p /var/spool/cron/crontabs; \
    echo '* * * * * cd /var/www/html; /usr/local/bin/php -f cron.php > /dev/null 2>&1' > /var/spool/cron/crontabs/www-data

# php.ini
RUN { \
	echo 'expose_php = Off'; \
	echo 'display_errors = Off'; \
	echo 'display_startup_errors = Off'; \
	echo 'log_errors = On'; \
	echo 'memory_limit=256M'; \
	echo 'max_execution_time=180'; \
	echo 'max_input_time=180'; \
	echo 'post_max_size=30M'; \
	echo 'upload_max_filesize=30M'; \
	echo 'date.timezone=UTC'; \
} > ${PHP_INI_DIR}/conf.d/espocrm.ini

RUN a2enmod rewrite;

ENV ESPOCRM_VERSION 6.1.4
ENV ESPOCRM_SHA256 d05741edbb12b31e5d93a8863f471da6241ea824b92be67c29e5ab333ef61add

WORKDIR $PROJECT_PATH

# Apache2 conf
RUN echo "ServerName localhost" | tee /etc/apache2/conf-available/fqdn.conf && \
    a2enconf fqdn

# Set the timezone.
RUN echo $TIMEZONE > /etc/timezone && \
    dpkg-reconfigure -f noninteractive tzdata

#TODO SHA256 and WORKDIR
#Download ESPOCRM
WORKDIR /tmp
RUN set -ex; \
    curl -fSL "https://www.espocrm.com/downloads/EspoCRM-$ESPO_VERSION.zip" -o EspoCRM.zip;  \
    unzip -q /tmp/EspoCRM.zip -d /tmp

RUN cp -a /tmp/EspoCRM-6.1.4/.  $PROJECT_PATH/; \
#Add permissions 
    chown -R www-data:www-data $PROJECT_PATH/*

WORKDIR $PROJECT_PATH

RUN find . -type d -exec chmod 755 {} + && find . -type f -exec chmod 644 {} +;
RUN find data custom -type d -exec chmod 775 {} + && find data custom -type f -exec chmod 664 {} +;
RUN chmod 777 cron.php

COPY ./docker-entrypoint.sh /usr/local/bin/
COPY ./docker-cron.sh /usr/local/bin/
ENTRYPOINT [ "docker-entrypoint.sh" ]

CMD ["apache2-foreground"]

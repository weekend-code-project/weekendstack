FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies including SVN
RUN apt-get update && apt-get install -y \
    apache2 \
    php8.1 \
    php8.1-cli \
    php8.1-mysql \
    php8.1-gd \
    php8.1-curl \
    php8.1-mbstring \
    php8.1-xml \
    php8.1-zip \
    libapache2-mod-php8.1 \
    imagemagick \
    ghostscript \
    antiword \
    xpdf \
    ffmpeg \
    exiftool \
    subversion \
    mariadb-client \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Download ResourceSpace from SVN repository  
WORKDIR /tmp
RUN svn export https://svn.resourcespace.com/svn/rs/releases/10.3 /tmp/resourcespace \
    && mv /tmp/resourcespace/* /var/www/html/ \
    && rm -rf /tmp/resourcespace \
    && rm -f /var/www/html/index.html \
    && chown -R www-data:www-data /var/www/html \
    && chmod -R 755 /var/www/html

# Configure Apache
RUN a2enmod rewrite \
    && a2enmod headers \
    && sed -i 's/AllowOverride None/AllowOverride All/g' /etc/apache2/apache2.conf

# Configure Apache to trust X-Forwarded-Proto from Traefik
RUN echo "SetEnvIf X-Forwarded-Proto https HTTPS=on" >> /etc/apache2/apache2.conf

# Configure PHP settings for ResourceSpace
RUN sed -i 's/memory_limit = 128M/memory_limit = 512M/g' /etc/php/8.1/apache2/php.ini \
    && sed -i 's/post_max_size = 8M/post_max_size = 200M/g' /etc/php/8.1/apache2/php.ini \
    && sed -i 's/upload_max_filesize = 2M/upload_max_filesize = 200M/g' /etc/php/8.1/apache2/php.ini \
    && sed -i 's/max_execution_time = 30/max_execution_time = 300/g' /etc/php/8.1/apache2/php.ini

# Set permissions
RUN chown -R www-data:www-data /var/www/html \
    && chmod -R 755 /var/www/html

# Create filestore directory
RUN mkdir -p /var/www/html/filestore \
    && chown -R www-data:www-data /var/www/html/filestore

# Copy entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /var/www/html

EXPOSE 80

ENTRYPOINT ["/entrypoint.sh"]

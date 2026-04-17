FROM nginx:1.28-alpine

ARG REQUESTS_CA_BUNDLE_ARG=/etc/ssl/certs/ca-certificates.crt
ARG CURL_CA_BUNDLE_ARG=/etc/ssl/certs/ca-certificates.crt
ARG SSL_CERT_FILE_ARG=/etc/ssl/certs/ca-certificates.crt
ARG PIP_FILE_ARG=/etc/ssl/certs/ca-certificates.crt
ARG PYTHONHTTPSVERIFY_ARG=1
ARG FORCE_TLS12_ARG=1

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    REQUESTS_CA_BUNDLE=${REQUESTS_CA_BUNDLE_ARG} \
    CURL_CA_BUNDLE=${CURL_CA_BUNDLE_ARG} \
    SSL_CERT_FILE=${SSL_CERT_FILE_ARG} \
    PIP_CERT=${PIP_FILE_ARG} \
    PYTHONHTTPSVERIFY=${PYTHONHTTPSVERIFY_ARG}


# COPY ./ca-certificates.crt /usr/local/share/ca-certificates/firewall-ca.crt
# RUN update-ca-certificates    
# RUN apk add --no-cache curl gettext-runtime

# COPY ./ca-certificates.crt /usr/local/share/ca-certificates/firewall-ca.crt
# RUN [ ! -f /usr/local/share/ca-certificates/firewall-ca.crt ] || update-ca-certificates


# Le glob [t] rend la copie optionnelle : pas d'erreur si le fichier est absent
COPY ./ca-certificates.cr[t] /usr/local/share/ca-certificates/
RUN [ ! -f /usr/local/share/ca-certificates/ca-certificates.crt ] || \
    mv /usr/local/share/ca-certificates/ca-certificates.crt /usr/local/share/ca-certificates/firewall-ca.crt && \
    update-ca-certificates

RUN set -eux; \
    if [ "${FORCE_TLS12_ARG}" = "1" ]; then \
      printf '%s\n' \
        'openssl_conf = default_conf' \
        '[default_conf]' \
        'ssl_conf = ssl_sect' \
        '[ssl_sect]' \
        'system_default = system_default_sect' \
        '[system_default_sect]' \
        'MinProtocol = TLSv1.2' \
        'MaxProtocol = TLSv1.2' \
        > /tmp/openssl-tls12.cnf; \
      OPENSSL_CONF=/tmp/openssl-tls12.cnf apk add --no-cache curl gettext; \
    else \
      apk add --no-cache curl gettext; \
    fi 


RUN apk add --no-cache curl gettext
RUN mkdir -p /etc/nginx/certs /etc/nginx/templates /var/log/nginx \
 && ln -sf /dev/stdout /var/log/nginx/access.log \
 && ln -sf /dev/stderr /var/log/nginx/error.log

COPY docker/nginx/nginx.conf.template /etc/nginx/templates/nginx.conf.template
COPY docker/nginx/docker-entrypoint.sh /docker-entrypoint-nginx-upstream.sh

RUN chmod 755 /docker-entrypoint-nginx-upstream.sh

EXPOSE 80 443

ENTRYPOINT ["/docker-entrypoint-nginx-upstream.sh"]

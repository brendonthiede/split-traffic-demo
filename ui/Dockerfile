FROM docker-virtual.artifactory.renhsc.com/roos-httpd

ARG DEPLOY_VERSION="v1"

COPY ./index.html /var/www/html/index.html
RUN sed -i "s/{{DEPLOY_VERSION}}/${DEPLOY_VERSION}/g" /var/www/html/index.html

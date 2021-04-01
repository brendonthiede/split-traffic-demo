#!/bin/bash

for _deploy_version in v1 v2 v3; do
    docker build . -t docker-virtual.artifactory.renhsc.com/split-test:${_deploy_version} --build-arg="DEPLOY_VERSION=${_deploy_version}"
    docker push docker-virtual.artifactory.renhsc.com/split-test:${_deploy_version}
done

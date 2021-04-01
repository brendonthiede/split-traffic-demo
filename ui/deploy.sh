#!/bin/bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

for _deploy_version in v1 v2 v3; do

    cat >"${DIR}/version_values.yaml" <<EOF
image:
  tag: "${_deploy_version}"

ingress:
  enabled: true
  annotations:
    cert-manager.io/cluster-issuer: vault-issuer
    cert-manager.io/common-name: internal.test-ci.nonprd.local-os
  hosts:
    - host: internal.test-ci.nonprd.local-os
      paths:
      - path: /split-test/${_deploy_version}/?(.*)
  tls:
  - hosts:
    - internal.test-ci.nonprd.local-os
    secretName: auto-ingress-tls
EOF

    helm upgrade --install ui-${_deploy_version} ${DIR}/helm -n split-test -f "${DIR}/version_values.yaml"
done

rm -f "${DIR}/version_values.yaml"

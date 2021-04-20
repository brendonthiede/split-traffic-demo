#!/bin/bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

echo "[INFO] $(date "+%Y-%m-%d %H:%M:%S") Installing linkerd Kubernetes objects"
linkerd install --disable-heartbeat --ha --registry=docker-virtual.artifactory.renhsc.com/linkerd | kubectl apply --record=true -f -
echo "[INFO] $(date "+%Y-%m-%d %H:%M:%S") Adding label to kube-system"
cat <<EOF | kubectl apply --record=true -f -
apiVersion: v1
kind: Namespace
metadata:
  name: kube-system
  labels:
    config.linkerd.io/admission-webhooks: disabled
EOF
linkerd check

echo "[INFO] $(date "+%Y-%m-%d %H:%M:%S") Setting up viz namespace"
cat <<EOF | kubectl apply --record=true -f -
apiVersion: v1
kind: Namespace
metadata:
  name: linkerd-viz
  annotations:
    linkerd.io/inject: enabled
EOF

echo "[INFO] $(date "+%Y-%m-%d %H:%M:%S") Installing viz components"
linkerd viz install | kubectl apply --record=true -f -
linkerd viz check

echo "[INFO] $(date "+%Y-%m-%d %H:%M:%S") Configuring the ingress controller for linkerd"
kubectl get deployment nginx-ingress-ingress-nginx-controller -n default -o yaml | linkerd inject --ingress - | kubectl apply --record=true -f -

echo "[INFO] $(date "+%Y-%m-%d %H:%M:%S") Setting up the split-test namespace"
cat <<EOF | kubectl apply --record=true -f -
apiVersion: v1
kind: Namespace
metadata:
  name: split-test
  annotations:
    linkerd.io/inject: enabled
EOF

for _deploy_version in v1 v2 v3; do
    cat >"${DIR}/version_values.yaml" <<EOF
image:
  tag: "${_deploy_version}"

ingress:
  hosts:
    - host: internal.test-ci.nonprd.local-os
      paths:
      - path: /split-test/${_deploy_version}/?(.*)
  tls:
  - hosts:
    - internal.test-ci.nonprd.local-os
    secretName: auto-ingress-tls
EOF

    echo "[INFO] $(date "+%Y-%m-%d %H:%M:%S") Deploying ${_deploy_version} of UI"
    helm upgrade --install ui-${_deploy_version} ${DIR}/helm -n split-test -f "${DIR}/version_values.yaml"
done

rm -f "${DIR}/version_values.yaml"

echo "[INFO] $(date "+%Y-%m-%d %H:%M:%S") Setting up traffic split"
cat <<EOF | kubectl apply --record=true -f -
apiVersion: split.smi-spec.io/v1alpha1
kind: TrafficSplit
metadata:
  name: traffic-split-test
  namespace: split-test
spec:
  service: ui-v3-split-test-ui
  backends:
  - service: ui-v1-split-test-ui
    weight: 333m
  - service: ui-v2-split-test-ui
    weight: 333m
  - service: ui-v3-split-test-ui
    weight: 333m
EOF

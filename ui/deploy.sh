#!/bin/bash

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

echo "[INFO] $(date "+%Y-%m-%d %H:%M:%S") Installing linkerd Kubernetes objects"
linkerd install --disable-heartbeat --ha --registry=docker-virtual.artifactory.renhsc.com/linkerd | sed -E 's/image: (cr.l5d.io\/|(prom\/))/image: docker-virtual.artifactory.renhsc.com\/\2/g' | kubectl apply --record=true -f -
echo "[INFO] $(date "+%Y-%m-%d %H:%M:%S") Adding label to kube-system"
cat <<EOF | kubectl apply --record=true -f -
apiVersion: v1
kind: Namespace
metadata:
  name: kube-system
  annotations:
    config.linkerd.io/debug-image: docker-virtual.artifactory.renhsc.com/linkerd/debug
    config.linkerd.io/init-image: docker-virtual.artifactory.renhsc.com/linkerd/proxy-init
    config.linkerd.io/proxy-image: docker-virtual.artifactory.renhsc.com/linkerd/proxy
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
    config.linkerd.io/debug-image: docker-virtual.artifactory.renhsc.com/linkerd/debug
    config.linkerd.io/init-image: docker-virtual.artifactory.renhsc.com/linkerd/proxy-init
    config.linkerd.io/proxy-image: docker-virtual.artifactory.renhsc.com/linkerd/proxy
    linkerd.io/inject: enabled
EOF

echo "[INFO] $(date "+%Y-%m-%d %H:%M:%S") Installing viz components"
linkerd viz install | sed -E 's/image: (cr.l5d.io\/|(prom\/))/image: docker-virtual.artifactory.renhsc.com\/\2/g' | kubectl apply --record=true -f -
linkerd viz check

echo "[INFO] $(date "+%Y-%m-%d %H:%M:%S") Configuring the ingress controller for linkerd"
kubectl get deployment nginx-ingress-ingress-nginx-controller -n default -o yaml | linkerd inject --ingress - | kubectl apply --record=true -f -

echo "[INFO] $(date "+%Y-%m-%d %H:%M:%S") Installing Flagger"
kustomize build github.com/fluxcd/flagger/kustomize/linkerd | sed 's/ghcr\.io/docker-virtual.artifactory.renhsc.com/g' | kubectl apply --record=true -f -

echo "[INFO] $(date "+%Y-%m-%d %H:%M:%S") Setting up the split-test namespace"
cat <<EOF | kubectl apply --record=true -f -
apiVersion: v1
kind: Namespace
metadata:
  name: split-test
  annotations:
    config.linkerd.io/debug-image: docker-virtual.artifactory.renhsc.com/linkerd/debug
    config.linkerd.io/init-image: docker-virtual.artifactory.renhsc.com/linkerd/proxy-init
    config.linkerd.io/proxy-image: docker-virtual.artifactory.renhsc.com/linkerd/proxy
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

echo "[INFO] $(date "+%Y-%m-%d %H:%M:%S") Setting up canary deployment"
cat <<EOF | kubectl apply -f -
apiVersion: flagger.app/v1beta1
kind: Canary
metadata:
  name: podinfo
  namespace: split-test
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: ui-v1-split-test-ui
  service:
    port: 443
  analysis:
    interval: 10s
    threshold: 5
    stepWeight: 10
    maxWeight: 100
    metrics:
    - name: request-success-rate
      thresholdRange:
        min: 99
      interval: 1m
    - name: request-duration
      thresholdRange:
        max: 500
      interval: 1m
EOF

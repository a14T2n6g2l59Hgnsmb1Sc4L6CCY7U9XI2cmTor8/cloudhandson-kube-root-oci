#!/bin/bash

# usage:
# bash ./bin/generate/generate.sh

set -feu

# Global variables
export GH_ORG="a14T2n6g2l59Hgnsmb1Sc4L6CCY7U9XI2cmTor8"
export GITHUB_TOKEN="ghp_***************"

# gh auth login --hostname github.com --with-token < token.txt

# Clean local repo
rm -rf tooling

tooling_list=$(gh repo list ${GH_ORG} --no-archived --limit 300 --topic tooling --json name | jq '.[].name' | tr -d '"' | sed 's/cloudhandson-kube-//')

for tooling in ${tooling_list}
do
  export tooling
  export namespace=tooling
  export application=tooling

  mkdir -p tooling/${tooling}

  if [ "${tooling}" == "splunk-uf" ]; then
    cat bin/generate/templates/ks.yaml \
      | envsubst '${application},${namespace}' \
      | yq '. *= load("bin/generate/templates/ks_splunk.yaml")' \
      > tooling/${tooling}/ks.yaml
  else
    cat bin/generate/templates/ks.yaml \
      | envsubst '${application},${namespace}' \
      > tooling/${tooling}/ks.yaml
  fi

  cat bin/generate/templates/ocirepo.yaml \
    | envsubst '${application},${namespace}' \
    > tooling/${tooling}/ocirepo.yaml

  if [ "${tooling}" == "aws-lb-controller" ]; then
    echo "dependsOn:" >> tooling/${tooling}/ks.yaml
    echo "  - name: cert-manager" >> tooling/${tooling}/ks.yaml
  fi
done

cd tooling
kustomize init --recursive --autodetect

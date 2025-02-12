#!/usr/bin/env bash
RELEASE_VERSION="${1}"
COMMITS="${2}"

UPSTREAM_REMOTE=upstream
MASTER_BRANCH="master"
TARGET_NAMESPACE="release"
SECRET_NAME=bot-token-github
PUSH_REMOTE="${PUSH_REMOTE:-${UPSTREAM_REMOTE}}" # export PUSH_REMOTE to your own for testing

CATALOG_TASKS="lint build tests"

set -e

[[ -z ${RELEASE_VERSION} ]] && {
    read -e -p "Enter a target release (i.e: v0.1.2): " RELEASE_VERSION
    [[ -z ${RELEASE_VERSION} ]] && { echo "no target release"; exit 1 ;}
}

[[ ${RELEASE_VERSION} =~ v[0-9]+\.[0-9]*\.[0-9]+ ]] || { echo "invalid version provided, need to match v\d+\.\d+\.\d+"; exit 1 ;}
lasttag=$(git describe --abbrev=0 --tags)
echo ${lasttag}|sed 's/\.[0-9]*$//'|grep -q ${RELEASE_VERSION%.*} && { echo "Minor version of ${RELEASE_VERSION%.*} detected"; minor_version=true ; }

cd ${GOPATH}/src/github.com/tektoncd/cli

git fetch -a ${UPSTREAM_REMOTE} >/dev/null
git checkout ${MASTER_BRANCH}
git reset --hard ${UPSTREAM_REMOTE}/${MASTER_BRANCH}
git checkout -B release-${RELEASE_VERSION}  ${MASTER_BRANCH} >/dev/null

if [[ -n ${minor_version} ]];then
    git reset --hard ${lasttag} >/dev/null

    if [[ -z ${COMMITS} ]];then
        echo "Showing commit between last minor tag '${lasttag} to '${MASTER_BRANCH}'"
        echo
        git log --reverse --no-merges --pretty=format:"%h | %s | %cd | %ae" ${lasttag}..${MASTER_BRANCH}
        echo
        read -e -p "Pick a list of ordered commits to cherry-pick space separated (* mean all of them): " COMMITS
    fi
    [[ -z ${COMMITS} ]] && { echo "no commits picked"; exit 1;}
    if [[ ${COMMITS} == "*" ]];then
        COMMITS=$(git log --reverse --no-merges --pretty=format:"%h" ${lasttag}..${MASTER_BRANCH})
    fi
    for commit in ${COMMITS};do
        git branch --contains ${commit} >/dev/null || { echo "Invalid commit ${commit}" ; exit 1;}
        echo "Cherry-picking commit: ${commit}"
        git cherry-pick ${commit} >/dev/null
    done

else
    echo "Major release ${RELEASE_VERSION%.*} detected: picking up ${UPSTREAM_REMOTE}/${MASTER_BRANCH}"
    git reset --hard ${UPSTREAM_REMOTE}/${MASTER_BRANCH}
fi

# TODO: toremove! this is temporary to disable the upload to homebrew
# need to find a way how to do this automatically (push to upstream/revert and
# then being able to cherry-pick if $PUSH_REMOTE != 'upstream/origin'?)
# git cherry-pick 052b0b4ce989fe9aee01027e67e61538b48e1179

# Add our VERSION so Makefile will pick it up when compiling
echo ${RELEASE_VERSION} > VERSION
git add VERSION
git commit -sm "New version ${RELEASE_VERSION}" -m "${COMMITS}" VERSION
git tag --sign -m \
    "New version ${RELEASE_VERSION}
COMMITS:
$(git log --reverse --no-merges --pretty=format:"%h | %s | %cd | %ae" ${lasttag}..${MASTER_BRANCH})" \
    --force ${RELEASE_VERSION}

git push --force ${PUSH_REMOTE} ${RELEASE_VERSION}

kubectl version 2>/dev/null >/dev/null || {
    echo "you need to have access to a kubernetes cluster"
    exit 1
}

kubectl get pipelineresource 2>/dev/null >/dev/null || {
    echo "you need to have tekton install onto the cluster"
    exit 1
}

kubectl create ${TARGET_NAMESPACE} 2>/dev/null || true

for task in ${CATALOG_TASKS};do
    kubectl -n ${TARGET_NAMESPACE} apply -f https://raw.githubusercontent.com/tektoncd/catalog/master/golang/${task}.yaml
done

kubectl -n ${TARGET_NAMESPACE} apply -f ./tekton/goreleaser.yml

if ! kubectl get secret ${SECRET_NAME} -o name >/dev/null 2>/dev/null;then
    github_token=$(git config --get github.oauth-token || true)

    [[ -z ${github_token} ]] && {
        read -e -p "Enter your Github Token: " github_token
        [[ -z ${github_token} ]] && { echo "no token provided"; exit 1;}
    }

    kubectl -n ${TARGET_NAMESPACE} create secret generic ${SECRET_NAME} --from-literal=bot-token=${github_token}
fi

kubectl -n ${TARGET_NAMESPACE} apply -f ./tekton/release-pipeline.yml

# Until tkn supports tkn create with parameters we do like this,
cat <<EOF | kubectl -n ${TARGET_NAMESPACE} apply -f-
apiVersion: tekton.dev/v1alpha1
kind: PipelineResource
metadata:
  name: tektoncd-cli-git
spec:
  type: git
  params:
  - name: revision
    value: ${RELEASE_VERSION}
  - name: url
    value: $(git remote get-url ${PUSH_REMOTE}|sed 's,git@github.com:,https://github.com/,')
EOF

# Start the pipeline, We can't use tkn start because until #272 and #262 are imp/fixed
cat <<EOF | kubectl -n ${TARGET_NAMESPACE} create -f-
apiVersion: tekton.dev/v1alpha1
kind: PipelineRun
metadata:
  generateName: cli-release-pipeline-run
spec:
  pipelineRef:
    name: cli-release-pipeline
  resources:
    - name: source-repo
      resourceRef:
        name: tektoncd-cli-git
EOF

type -p tkn >/dev/null 2>/dev/null || { echo  "Could not find the 'tkn' binary, you are on your own buddy"; exit 0 ;}

tkn pipeline logs cli-release-pipeline -f

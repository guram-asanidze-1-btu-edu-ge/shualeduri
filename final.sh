#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail

if [[ "${BASH_TRACE:-0}" == "1" ]]; then
    set -o xtrace
fi

cd "$(dirname "$0")"


REPOSITORY_CODE_LINK="$1"
REPOSITORY_NAME_CODE=$(basename "$REPOSITORY_CODE_LINK" .git)
REPOSITORY_OWNER=$(echo "$REPOSITORY_CODE_LINK" | awk -F':' '{print $2}' | awk -F'/' '{print $1}')
REPOSITORY_CODE_CI_LINK="$4"
CI_OWNER=$(echo "$REPOSITORY_CODE_CI_LINK" | awk -F':' '{print $2}' | awk -F'/' '{print $1}')
REPOSITORY_NAME_REPORT=$(basename "$REPOSITORY_CODE_CI_LINK" .git)
REPOSITORY_BRANCH_CODE="$2"
RELEASE_BRANCH_NAME="$3"
REPOSITORY_BRANCH_REPORT="$5"
REPOSITORY_PATH_CODE=$(mktemp --directory)
REPOSITORY_PATH_REPORT=$(mktemp --directory)
PYTEST_REPORT_PATH=$(mktemp)
BLACK_OUTPUT_PATH=$(mktemp)
BLACK_REPORT_PATH=$(mktemp)
PYTEST_RESULT=0
BLACK_RESULT=0

echo $CI_OWNER
echo $REPOSITORY_OWNER
echo $REPOSITORY_NAME_CODE
echo $REPOSITORY_NAME_REPORT
function github_api_get_request()
{
    curl --request GET \
        --header "Accept: application/vnd.github+json" \
        --header "Authorization: Bearer $" \
        --header "X-GitHub-Api-Version: 2022-11-28" \
        --output "$2" \
        --silent \
        "$1"
        #--dump-header /dev/stderr \
}

function github_post_request()
{
    curl --request POST \
        --header "Accept: application/vnd.github+json" \
        --header "Authorization: Bearer $GITHUB_PERSONAL_ACCESS_TOKEN" \
        --header "X-GitHub-Api-Version: 2022-11-28" \
        --header "Content-Type: application/json" \
        --silent \
        --output "$3" \
        --data-binary "@$2" \
        "$1"
        #--dump-header /dev/stderr \
}

function jq_update()
{
    local IO_PATH=$1
    local TEMP_PATH=$(mktemp)
    shift
    cat $IO_PATH | jq "$@" > $TEMP_PATH
    mv $TEMP_PATH $IO_PATH
}

function monitor_commits() {
  previous_commit=""
  echo "start monitoring"
  while true; do
    echo "monitoring"
    git fetch "$1" "$2" > /dev/null 2>&1
    check_commit=$(git rev-parse FETCH_HEAD)
    if [ "$check_commit" != "$previous_commit" ]; then
        if [ -z "$previous_commit" ]; then
            previous_commit=$check_commit
        else
            commits=$(git log --pretty=format:"%H" --reverse "$previous_commit..$check_commit")
            echo "commits is : $commits"
            previous_commit=$check_commit
        fi
    fi
    sleep 15
  done
}
monitor_commits REPOSITORY_CODE_LINK REPOSITORY_BRANCH_CODE &

git clone git@github.com:${REPOSITORY_OWNER}/${REPOSITORY_NAME_CODE}.git $REPOSITORY_PATH_CODE
pushd $REPOSITORY_PATH_CODE
git switch $REPOSITORY_BRANCH_CODE
COMMIT_HASH=$(git rev-parse HEAD)
AUTHOR_USER=$(git log -n 1 --format="%an")
# Check if pytest and black are installed
if ! command -v pytest &>/dev/null; then
    echo "Please install pytest"
    exit 1
else echo "Pytest is installed"
fi

if ! command -v black &>/dev/null; then
    echo "Please install black"
    exit 1
else echo 'Black is installed'
fi

# Run pytest and black tests concurrently

if pytest --verbose --html=$PYTEST_REPORT_PATH --self-contained-html & \
black --check --diff *.py


then
    PYTEST_RESULT=$?
    echo "PYTEST SUCCEEDED $PYTEST_RESULT"
else
    PYTEST_RESULT=$?
    echo "PYTEST FAILED $PYTEST_RESULT"
    # Find the exact commit which introduced unit tests fail
    pushd $REPOSITORY_PATH_CODE
    git bisect start
    git bisect bad HEAD
    git bisect good HEAD~10
    git bisect run pytest
    # The above command will automatically find the commit that introduced the unit tests fail
    export PYTEST_FAIL_ERROR=$(git rev-parse --short HEAD)
    git bisect reset
    popd
fi
echo "\$PYTEST_RESULT = $PYTEST_RESULT \$BLACK_RESULT=$BLACK_RESULT"

if black --check --diff *.py > $BLACK_OUTPUT_PATH
then
    BLACK_RESULT=$?
    echo "BLACK SUCCEEDED $BLACK_RESULT"
else
    BLACK_RESULT=$?
    echo "BLACK FAILED $BLACK_RESULT"
    cat $BLACK_OUTPUT_PATH | pygmentize -l diff -f html -O full,style=solarized-light -o $BLACK_REPORT_PATH
    pushd $REPOSITORY_PATH_CODE
    git bisect start
    git bisect bad HEAD
    git bisect good HEAD~10
    git bisect run black --check --diff *.py
    export BLACK_FAIL_ERROR=$(git rev-parse --short HEAD)
    git bisect reset
    popd
fi

echo "\$PYTEST_RESULT = $PYTEST_RESULT \$BLACK_RESULT=$BLACK_RESULT"

popd

git clone git@github.com:${CI_OWNER}/${REPOSITORY_NAME_REPORT}.git $REPOSITORY_PATH_REPORT

pushd $REPOSITORY_PATH_REPORT

git switch $REPOSITORY_BRANCH_REPORT
REPORT_PATH="${COMMIT_HASH}-$(date +%s)"
mkdir --parents $REPORT_PATH
mv $PYTEST_REPORT_PATH "$REPORT_PATH/pytest.html"
mv $BLACK_REPORT_PATH "$REPORT_PATH/black.html"
git add $REPORT_PATH
git commit -m "$COMMIT_HASH report."
git push


popd

rm -rf $REPOSITORY_PATH_CODE
rm -rf $REPOSITORY_PATH_REPORT
rm -rf $PYTEST_REPORT_PATH
rm -rf $BLACK_REPORT_PATH


if (( ($PYTEST_RESULT != 0) || ($BLACK_RESULT != 0) ))
then
    AUTHOR_USERNAME="$AUTHOR_USER"
    # https://docs.github.com/en/rest/search?apiVersion=2022-11-28#search-users
    RESPONSE_PATH=$(mktemp)

    TOTAL_USER_COUNT=$(cat $RESPONSE_PATH | jq ".total_count")

    if [[ $TOTAL_USER_COUNT == 1 ]]
    then
        USER_JSON=$(cat $RESPONSE_PATH | jq ".items[0]")
    fi

    REQUEST_PATH=$(mktemp)
    RESPONSE_PATH=$(mktemp)
    echo "{}" > $REQUEST_PATH

    BODY+="Automatically generated message

"

    if (( $PYTEST_RESULT != 0 ))
    then
        if (( $BLACK_RESULT != 0 ))
        then
            TITLE="${COMMIT_HASH::7} failed unit and formatting tests."
            BODY+="${COMMIT_HASH} failed unit and formatting tests.
            ${PYTEST_FAIL_ERROR} PYTEST FAILED
            ${BLACK_FAIL_ERROR} BLACK FAILED


"
            jq_update $REQUEST_PATH '.labels = ["ci-pytest", "ci-black"]'
        else
            TITLE="${COMMIT_HASH::7} failed unit tests."
            BODY+="${COMMIT_HASH} failed unit tests.
            ${PYTEST_FAIL_ERROR} PYTEST FAILED

"
            jq_update $REQUEST_PATH '.labels = ["ci-pytest"]'
        fi
    else
        TITLE="${COMMIT_HASH::7} failed formatting test."
        BODY+="${COMMIT_HASH} failed formatting test.
        ${BLACK_FAIL_ERROR} BLACK FAILED 
"
        jq_update $REQUEST_PATH '.labels = ["ci-black"]'
    fi

    BODY+="Pytest report: https://${CI_OWNER}.github.io/${REPOSITORY_NAME_REPORT}/$REPORT_PATH/pytest.html

"
    BODY+="Black report: https://${CI_OWNER}.github.io/${REPOSITORY_NAME_REPORT}/$REPORT_PATH/black.html

"

    jq_update $REQUEST_PATH --arg title "$TITLE" '.title = $title'
    jq_update $REQUEST_PATH --arg body  "$BODY"  '.body = $body'
    if [[ ! -z $AUTHOR_USERNAME ]]
    then

        jq_update $REQUEST_PATH --arg username "$AUTHOR_USERNAME"  '.assignees = [$username]'
    fi

    # https://docs.github.com/en/rest/issues/issues?apiVersion=2022-11-28#create-an-issue
    github_post_request "https://api.github.com/repos/${REPOSITORY_OWNER}/${REPOSITORY_NAME_CODE}/issues" $REQUEST_PATH $RESPONSE_PATH
    #cat $RESPONSE_PATH
    cat $RESPONSE_PATH | jq ".html_url"
    rm $RESPONSE_PATH
    rm $REQUEST_PATH
else
    # Merge revision into ${RELEASE_BRANCH_NAME} branch
    if git merge --no-commit $REPOSITORY_BRANCH_CODE >/dev/null 2>&1; then
      # Merge successful, push changes to remote repository
      git push origin ${RELEASE_BRANCH_NAME}
    else
      # Merge failed, handle conflict information and create GitHub issue
      CONFLICT_OUTPUT=$(git status --porcelain)
      REQUEST_PATH=$(mktemp)
      RESPONSE_PATH=$(mktemp)
      echo "{}" > $REQUEST_PATH
      TITLE="Merge conflict in ${RELEASE_BRANCH_NAME}"
      BODY+="There is a merge conflict in the ${RELEASE_BRANCH_NAME} branch with the branch ${REPOSITORY_BRANCH_CODE}.\n\n"
      BODY+="Conflict details:\n\n"
      BODY+="$CONFLICT_OUTPUT\n\n"
      jq_update $REQUEST_PATH --arg title "$TITLE" '.title = $title'
      jq_update $REQUEST_PATH --arg body "$BODY" '.body = $body'
      # Create GitHub issue
      github_post_request "https://api.github.com/repos/${REPOSITORY_OWNER}/${REPOSITORY_NAME_CODE}/issues" $REQUEST_PATH $RESPONSE_PATH
      cat $RESPONSE_PATH | jq ".html_url"
      rm $RESPONSE_PATH
      rm $REQUEST_PATH
    fi

    # Return to previous branch
    git checkout -

    REMOTE_NAME=$(git remote)
    git tag --force "${RELEASE_BRANCH_NAME}-ci-success" $COMMIT_HASH
    git push --force $REMOTE_NAME --tags
fi


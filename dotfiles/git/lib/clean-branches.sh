#!/bin/bash

onerror() {
  line=$1
  echo Error executing command on line $line: $BASH_COMMAND
  exit -1
}

trap 'onerror $LINENO' ERR

usage() {
  cat << EOF
usage: $0 [options]

Options:
  -o <offset>  Specify the cutoff offset for trashing a branch. Default: 14d
  -r           Clean remote branches instead of local branches
  -w           Perform a "what if" dry-run. Only prints out actions that would have been performed.
  -h           Shows this message and quits.
EOF
}

branchWhitelist=.git-branch-whitelist

cutoffOffset=14d
branchOpts=
emptyTrash=false
whatIf=false
remote=false

while getopts 'o:rewh' OPTION; do case $OPTION in
  h) usage; exit;;
  e) emptyTrash=true;;
  o) cutoffOffset=$OPTARG;;
  w) whatIf=true;;
  r) remote=true;;
  ?) usage; exit -1;;
esac; done

if $remote; then
  branchOpts='--remote';
  masterBranch='origin/master';
else
  masterBranch='master';
fi

cutoff=$(date -v -${cutoffOffset} +%s)

case "$emptyTrash $whatIf" in
  'true false')  verb='Deleting';;
  'true true')   verb='Would delete';;
  'false false') verb='Moving';;
  'false true')  verb='Would move';;
esac

sources=("<(git branch $branchOpts)")
egrepOpts=('-e (^|/)trash/')
if ! $emptyTrash; then
  sources+=("<(git branch $branchOpts --merged $masterBranch)")
  # don't include pointers, i.e. foo -> bar
  egrepOpts+=('-v' "-e ^${masterBranch}\$" '-e \->')

  if [[ -e $branchWhitelist ]]; then
    egrepOpts+=("-f $branchWhitelist")
  fi
fi

eval "sort -m ${sources[@]}" | cut -c 3- | egrep ${egrepOpts[@]} | {
  while read branch; do
    if $remote; then
      remoteName=${branch%%/*}
      remoteBranch=${branch#*/}
      oldBranch=$remoteBranch
      newBranch=trash/$remoteBranch
    else
      oldBranch=$branch
      newBranch=trash/$branch
    fi

    if $emptyTrash; then
      echo "$verb $branch"

      if $whatIf; then continue; fi

      if $remote; then
        git push --delete $remoteName $remoteBranch
      else
        git branch -D $branch
      fi 
    else
      branchDate=$(git show -s --format=%ct $branch)

      if [ "$branchDate" -lt "$cutoff" ]; then
        echo "$verb $oldBranch -> $newBranch (last commit was on $(date -j -f %s $branchDate))"

        if $whatIf; then continue; fi

        if $remote; then 
          git push $remoteName "$branch:refs/heads/$newBranch"
          git push --delete $remoteName $remoteBranch
        else
          git branch $newBranch $branch
          git branch -D $branch
        fi
      fi
    fi
  done
}
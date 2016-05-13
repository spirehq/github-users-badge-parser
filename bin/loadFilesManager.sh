#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CURRENT=$1
MIN=$1
MAX=$2
SETTINGS=$3
STEP=500000
STARTED_AT=`date +%s%3N`

while [ $CURRENT -lt $MAX ]
do
    echo $CURRENT
    NEXT=$[CURRENT+STEP]
    `$DIR/loadFiles.coffee --settings $SETTINGS --from $CURRENT --to $NEXT --startedAt $STARTED_AT --begin $MIN --end $MAX >> loadFiles.out 2>&1`
    RESULT=$?
    while [ $RESULT -ne 0 ]
    do
        echo "Process exit with code $RESULT"
        `$DIR/loadFiles.coffee --settings $SETTINGS --from $CURRENT --to $NEXT --startedAt $STARTED_AT --begin $MIN --end $MAX >> loadFiles.out 2>&1`
        RESULT=$?
    done

    CURRENT=$NEXT
done

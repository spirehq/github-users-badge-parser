#/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CREDENTIALS=admin:password
DATABASE=registry
DOCUMENT=_design/badge
VIEW=list

echo "Initialize database..."
curl -X PUT http://$CREDENTIALS@127.0.0.1:5984/$DATABASE

echo "Load design document with view..."
curl -X PUT -d @$DIR/couchScript.json http://$CREDENTIALS@127.0.0.1:5984/$DATABASE/$DOCUMENT

echo "Build index for the view..."
curl -X GET http://$CREDENTIALS@127.0.0.1:5984/$DATABASE/$DOCUMENT/_view/$VIEW?limit=10

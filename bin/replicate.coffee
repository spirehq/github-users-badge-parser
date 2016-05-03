Promise = require 'bluebird'
requestAsync = Promise.promisify((require "request"), {multiArgs: true})

# instruction is here: https://github.com/npm/npm-registry-couchapp
# /Users/YOUR_USER/Library/Application Support/CouchDB/etc/couchdb/local.ini



initDatabase = ->
	requestAsync {method: "PUT", url: 'http://localhost:5984/registry'}


initUser = ->
	requestAsync {method: "PUT", url: 'http://localhost:5984/_config/admins/admin', body: '"password"'}

replicate = ->
	requestAsync
		method: "POST"
		url: 'http://localhost:5984/_replicate'
		body: '{"source":"https://skimdb.npmjs.com/registry","target":"http://admin:password@127.0.0.1:5984/registry"}'
		headers:
			'Content-Type': 'application/json'

initDatabase()
.then replicate
.then -> console.log arguments

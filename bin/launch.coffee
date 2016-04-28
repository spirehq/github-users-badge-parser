_ = require 'underscore'
Promise = require 'bluebird'
createDependencies = require '../helper/dependencies'
settings = (require '../core/helper/settings')("settings/test.json")

RepoLoader = require '../lib/RepoLoader.coffee'
Calculator = require '../lib/Calculator.coffee'
RepositoriesCollection = require '../lib/model/Repositories.coffee'
PackagesCollection = require '../lib/model/Packages.coffee'
FilesCollection = require '../lib/model/Files.coffee'
dependencies = createDependencies(settings, 'RepoLoader')

# ensureIndex
Repositories = new RepositoriesCollection dependencies.mongodb
Packages = new PackagesCollection dependencies.mongodb
Files = new FilesCollection dependencies.mongodb

loader = new RepoLoader(settings.github, dependencies)
calculator = new Calculator(dependencies)

Promise.join Repositories.init(), Packages.init(), Files.init()
.then -> loader.syncRepositories()
.then -> calculator.run()
.then -> console.log "Done"
.then -> process.exit(0)

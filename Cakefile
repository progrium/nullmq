fs     = require 'fs'
{exec} = require 'child_process'
util   = require 'util'

task 'watch', 'Watch for changes in coffee files to build and test', ->
  invoke 'watch:coffee'
  invoke 'watch:tests'

task 'watch:coffee', 'Watch coffee files for changes to build', ->
    util.log "Building on changes in src and test"
    watchDir 'src', ->
      invoke 'build:src'
    watchDir 'test', ->
      invoke 'build:test'
    
task 'watch:tests', 'Watch test files for changes to test', ->
    util.log "Testing on changes in lib/test"
    watchDir 'lib/test', ->
      invoke 'test'

task 'test', 'Run the tests', ->
  util.log "Running tests..."
  exec "jasmine-node --nocolor lib/test", (err, stdout, stderr) -> 
    if err then handleError(parseTestResults(stdout)) else util.log lastLine(stdout)

task 'build', 'Build source and tests', ->
  invoke 'build:src'
  invoke 'build:test'

task 'build:src', 'Build the src files into lib', ->
  util.log "Compiling src..."
  exec "coffee -o lib/ -c src/", (err, stdout, stderr) -> 
    handleError(err) if err

task 'build:test', 'Build the test files into lib/test', ->
  util.log "Compiling test..."
  exec "coffee -o lib/test/ -c test/", (err, stdout, stderr) -> 
    handleError(err) if err

watchDir = (dir, callback) ->
  fs.readdir dir, (err, files) ->
      handleError(err) if err
      for file in files then do (file) ->
          fs.watchFile "#{dir}/#{file}", (curr, prev) ->
              if +curr.mtime isnt +prev.mtime
                  callback "#{dir}/#{file}"

parseTestResults = (data) ->
  lines = (line for line in data.split('\n') when line.length > 5)
  results = lines.pop()
  details = lines[1...lines.length-2].join('\n')
  results + '\n\n' + details + '\n'

lastLine = (data) ->
  (line for line in data.split('\n') when line.length > 5).pop()

handleError = (error) -> 
  util.log error
  displayNotification error
        
displayNotification = (message = '') -> 
  options = { title: 'CoffeeScript' }
  try require('growl').notify message, options
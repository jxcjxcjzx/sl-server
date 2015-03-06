kit = require 'nokit'
{ glob, path, Promise, log } = kit

tasks = [
    'build'
    'Build all source code.'
    ->
        srcPath = 'src'
        distPath = 'dist'
        coffee = require 'coffee-script'
        glob join(srcPath, '**', '*.coffee')
        .then (files) ->
            Promise.all files.map (path) ->
                jsPath = "#{replace(/(\.coffee)$/, '')}.js"

                kit.readFile(path, 'utf8').then (str) ->
                    try
                        return coffee.compile(str, {bare: true})
                    catch e
                        log ">> Error: #{path} \n#{e}".red
                .then (code) ->
                    kit.outputFile(jsPath, code).then ->
                        log '>> Compiled: '.cyan + path
]

cmd = require "commander"
slserver = require "./slserver"

cmd
    .version '1.0.0'
    .usage  '\n\n    slserver -l 100 -p 8233'
    .option '-p, --port <n>', 'server port, default is 8233'
    .option '-l, --limit <n>', 'turn speed limit on, unit is KB, set to 0 is unlimited, default is unlimited'
    .option '-w, --limitweb', 'speed limit also use in html/js/css file'
    .option '--nocache', 'disabled client cache'
    .option '--noopen', 'don\'t open browser when server start'
    .parse process.argv

options =
    port: cmd.port || 8233
    limit: if cmd.limit > 0 then cmd.limit else 0
    cache: !cmd.nocache
    weblimit: !!cmd.limitweb
    openbrowser: !cmd.noopen

slserver(options)

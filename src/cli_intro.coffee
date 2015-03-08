cmd = require "commander"
#TODO 路径的使用
#slserver = require "#{__dirname}/slserver"
slserver = require "./slserver"

cmd
    .version '0.1.0'
    .option '-p, --port <n>', 'server port, default is 8233'
    .option '-l, --limit <n>', 'turn speed limit on, unit is KB, set to 0 is unlimit, default is unlimit'
    .option '-w, --limitweb', 'speed limit also use in html/js/css file'
    .option '--nocache', 'disabled client cache'
    .option '--noopen', 'dont open browser when server start'
    .parse process.argv

options =
    port: cmd.port
    limit: if cmd.limit > 0 then cmd.limit else 0
    cache: !cmd.nocache
    weblimit: !!cmd.limitweb
    openbrowser: !cmd.noopen

slserver(options)

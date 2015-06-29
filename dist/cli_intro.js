var cmd, options, slserver, version;

cmd = require("commander");

slserver = require("./slserver");

version = require("../package.json").version;

cmd.version(version).usage('\n\n    slserver -l 100 -p 8233').option('-p, --port <n>', 'server port, default is 8233').option('-l, --limit <n>', 'turn speed limit on, unit is KB, set to 0 is unlimited, default is unlimited').option('-w, --limitweb', 'speed limit also use in HTML/JS/CSS file').option('-c, --crossorigin', 'support Cross-Origin by setting "Access-Control-Allow-Origin" header').option('--nocache', 'disabled client cache').option('--noopen', 'don\'t open browser when server start').parse(process.argv);

options = {
  port: cmd.port || 8233,
  limit: cmd.limit > 0 ? cmd.limit : 0,
  cache: !cmd.nocache,
  weblimit: !!cmd.limitweb,
  openbrowser: !cmd.noopen,
  crossorigin: !!cmd.crossorigin
};

slserver(options);

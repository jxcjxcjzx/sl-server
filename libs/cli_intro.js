var cli = require("commander");

cli
    .version('0.0.3')
    .option('-p, --port <n>','customize server port,default is 8233')
    .option('-l, --limit <n>','open speed limit,unit is KB,set to 0 is unlimit,default unlimit')
    .parse(process.argv);

var options = {
    port: cli.port,
    limit:cli.limit
};

require(__dirname+"/slserver").run(options);

var Promise, colors, isDevelopment,
  slice = [].slice;

Promise = require('bluebird');

colors = require('colors');

isDevelopment = process.env.NODE_ENV === 'development';

module.exports = {
  open: function(args) {
    var cmd;
    switch (process.platform) {
      case 'darwin':
        cmd = 'open ';
        break;
      case 'win32':
        cmd = 'start';
    }
    return require('child_process').exec(cmd + args);
  },
  "default": function() {
    var defaults, item, k, target, v;
    target = arguments[0], defaults = 2 <= arguments.length ? slice.call(arguments, 1) : [];
    item = defaults.pop();
    while (item) {
      for (k in item) {
        v = item[k];
        if (target[k] == null) {
          target[k] = v;
        }
      }
      item = defaults.pop();
    }
    return target;
  },
  promisify: function(fn, self) {
    return function() {
      var args;
      args = 1 <= arguments.length ? slice.call(arguments, 0) : [];
      return new Promise(function(resolve, reject) {
        args.push(function() {
          if (arguments[0] != null) {
            return reject(arguments[0]);
          } else {
            return resolve(arguments[1]);
          }
        });
        return fn.apply(self, args);
      });
    };
  },
  parseRange: function(str, fileLen) {
    var end, matches, start;
    if (!str) {
      return;
    }
    matches = str.match(/^(.+)=\s*(\d+)?\s*-\s*(\d+)?,?/);
    if (!matches) {
      return;
    }
    start = matches[2];
    end = matches[3];
    if (start == null) {
      start = fileLen - end;
      end = fileLen - 1;
    } else if (end == null) {
      end = fileLen - 1;
    }
    if (end > fileLen - 1) {
      end = fileLen - 1;
    }
    if ((start == null) || (end == null) || +start > +end || start < 0) {
      return {
        error: true
      };
    }
    return {
      unit: matches[1],
      start: +start,
      end: +end
    };
  },
  getIp: function() {
    var k, netObj, o, os, output, v;
    os = require('os');
    netObj = os.networkInterfaces();
    output = [];
    for (k in netObj) {
      v = netObj[k];
      if (Array.isArray(v)) {
        o = v.reduce(function(p, c, i) {
          if (c.family === 'IPv4' && !c.internal) {
            p.push(c.address);
          }
          return p;
        }, []);
      }
      output = output.concat(o);
    }
    return output;
  },
  debug: function() {
    var msgs, title;
    title = arguments[0], msgs = 2 <= arguments.length ? slice.call(arguments, 1) : [];
    if (!isDevelopment) {
      return;
    }
    if (arguments.length === 1) {
      title = "";
      msgs = title;
    }
    console.log(("debug " + title + " >>>>>>> ").yellow);
    console.log(msgs);
    return console.log('<<<<<<<<<'.yellow);
  },
  log: function(msg) {
    return console.log(msg);
  }
};

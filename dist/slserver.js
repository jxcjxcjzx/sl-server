var DEFAULT_OPTIONS, NO_LIMIT_EXT, PF, Promise, ResJob, SlServer, StatP, colors, etag, fs, http, kit, mime, path, url,
  slice = [].slice;

fs = require('fs');

http = require('http');

path = require('path');

mime = require('mime');

colors = require('colors');

url = require('url');

etag = require('etag');

Promise = require('bluebird');

kit = require('./kit');

DEFAULT_OPTIONS = {
  interval: 50
};

NO_LIMIT_EXT = {
  html: true,
  js: true,
  css: true
};

StatP = kit.promisify(fs.stat, fs);

PF = function(func) {
  return function() {
    var args, self;
    args = 1 <= arguments.length ? slice.call(arguments, 0) : [];
    self = this;
    return new Promise(function(resolve, reject) {
      return func.call(self, resolve, reject);
    });
  };
};

SlServer = function(options) {
  var ip, opt, server;
  opt = kit["default"](options, DEFAULT_OPTIONS);
  opt.root = path.normalize(process.cwd() + path.sep);
  opt.bytes = Math.floor(1024 * opt.limit * opt.interval / 1000);
  server = http.createServer().on('request', function(req, res) {
    return ResJob.onRequest(req, res, opt);
  });
  server.listen(opt.port);
  ip = kit.getIp();
  ip.unshift('127.0.0.1');
  ip = ip.map(function(m) {
    return m + ":" + opt.port;
  });
  if (opt.openbrowser) {
    kit.open("http://127.0.0.1:" + opt.port);
  }
  kit.debug('Sl-Server Options', opt);
  kit.log('Server Start: '.blue + ip.join(' / '));
  return kit.log('Speed Limit: '.blue + (opt.limit ? opt.limit : 'unlimited') + ' KB'.blue);
};

ResJob = (function() {
  ResJob.onRequest = function(req, res, opt) {
    return new this(req, res, opt);
  };

  function ResJob(req, res, opt) {
    var promise, self;
    this.opt = opt;
    this.limit = this.opt.limit;
    this.req = req;
    this.res = res;
    this.url = req.url;
    self = this;
    this.headers = {
      "Server": "Sl-Server",
      "Accept-Ranges": "bytes",
      "Date": new Date().toUTCString()
    };
    kit.log('Req: '.blue + self.url);
    promise = new Promise(function(resolve, reject) {
      kit.debug(">> Step : start <<".cyan);
      return resolve();
    });
    promise.then(function() {
      kit.debug(">> Step : fileStat <<".cyan);
      return self.fileStat();
    }).then(function() {
      kit.debug(">> Step : cacheJudge <<".cyan);
      return self.cacheJudge();
    }).then(function() {
      kit.debug(">> Step : responseData <<".cyan);
      return self.responseData();
    })["catch"](function(err) {
      var code;
      kit.debug(">> Step : catch error <<".cyan);
      code = 500;
      if (typeof err === 'number') {
        code = err;
      } else {
        kit.log(err);
        kit.log(err.stack);
      }
      return self.sendError(code);
    });
  }

  ResJob.prototype.fileStat = PF(function(resolve, reject) {
    var filepath, pathname, root, urlStr;
    urlStr = this.req.url;
    switch (urlStr) {
      case 'favicon.ico':
        return this.reject(404);
      case '/':
        pathname = 'index.html';
        break;
      default:
        pathname = url.parse(urlStr).pathname;
    }
    root = this.opt.root;
    this.filepath = filepath = path.normalize(path.join(this.opt.root, pathname));
    kit.debug("filename", "filename: ".yellow + filepath);
    if (filepath.substr(0, root.length) !== root) {
      return reject(403);
    }
    return StatP(filepath).then((function(_this) {
      return function(st) {
        var charset, contentType, ext, type;
        if (!st.isFile()) {
          return reject(404);
        }
        _this.stat = st;
        _this.lastModified = _this.headers["Last-Modified"] = st.mtime.toUTCString();
        _this.etag = _this.headers["ETag"] = etag(st);
        type = mime.lookup(filepath);
        charset = mime.charsets.lookup(type);
        contentType = type + (charset ? "; charset=" + charset : '');
        _this.headers["Content-Type"] = contentType;
        if (!_this.opt.weblimit) {
          ext = path.extname(filepath);
          if (ext === '.html' || ext === '.js' || ext === '.css') {
            _this.limit = 0;
          }
        }
        return resolve();
      };
    })(this))["catch"]((function(_this) {
      return function(err) {
        if (err.code === 'ENOENT') {
          return reject(404);
        } else {
          return reject(err);
        }
      };
    })(this));
  });

  ResJob.prototype.cacheJudge = PF(function(resolve, reject) {
    var cacheControl, etags, headers, lastModified, matchEtag, modifiedSince, noneMatch, req;
    if (!this.opt.cache) {
      return resolve();
    }
    req = this.req;
    headers = req.headers;
    cacheControl = headers['cache-control'];
    modifiedSince = headers['if-modified-since'];
    noneMatch = headers['if-none-match'];
    kit.debug('req cache headers cacheControl,modifiedSince,noneMatch', cacheControl, modifiedSince, noneMatch);
    if (cacheControl && ~cacheControl.indexOf('no-cache') || (!modifiedSince && !noneMatch)) {
      return resolve();
    }
    if (noneMatch) {
      etags = noneMatch.split(/ *, */);
      kit.debug('etag', noneMatch, etags);
      if (etags) {
        matchEtag = ~etags.indexOf(noneMatch) || '*' === etags[0];
      }
      if (!matchEtag) {
        return resolve();
      }
    }
    if (modifiedSince) {
      modifiedSince = new Date(modifiedSince);
      lastModified = new Date(lastModified);
      if (lastModified > modifiedSince) {
        return resolve();
      }
    }
    return reject(304);
  });

  ResJob.prototype.responseData = PF(function(resolve, reject) {
    var bytes, checkNext, endFlag, fsOpt, interval, pipe, range, reqHeaders, res, self, source, sourceLen, stat, statusCode;
    self = this;
    statusCode = 200;
    reqHeaders = this.req.headers;
    fsOpt = {};
    stat = this.stat;
    range = kit.parseRange(reqHeaders["range"], stat.size);
    kit.debug('range', stat.size, reqHeaders["range"], range);
    if (range) {
      if (range.error) {
        return reject(416);
      }
      fsOpt.start = range.start;
      fsOpt.end = range.end;
      statusCode = 206;
      this.headers["Accept-Ranges"] = range.unit;
      this.headers["Content-Range"] = range.unit + " " + range.start + "-" + range.end + "/" + stat.size;
      this.headers["Content-Length"] = range.end - range.start + 1;
    } else {
      this.headers["Content-Length"] = stat.size;
    }
    if (!this.opt.cache) {
      this.headers["Expires"] = 'Wed, 11 Jan 1984 05:00:00 GMT';
      this.headers["Cache-Control"] = 'no-cache, must-revalidate, max-age=0';
      this.headers["Pragma"] = 'no-cache';
    }
    kit.debug('fsOpt', fsOpt);
    kit.debug('respond headers', this.headers);
    res = this.res;
    res.writeHead(statusCode, this.headers);
    res.on('finish', function() {
      kit.log(("Done (" + statusCode + "): " + self.url).green);
      return resolve();
    });
    source = fs.createReadStream(this.filepath, fsOpt);
    if (this.limit > 0) {
      endFlag = false;
      bytes = this.opt.bytes;
      interval = this.opt.interval;
      sourceLen = this.headers["Content-Length"];
      kit.debug("read loop", "speed limit " + this.limit + " KB, interval: " + interval + " ms, bytes: " + bytes + " B");
      checkNext = function() {
        if (endFlag) {
          return res.end();
        } else {
          return pipe();
        }
      };
      res.on('drain', function() {
        return checkNext();
      });
      return (pipe = function() {
        return setTimeout(function() {
          var buf, r;
          buf = source.read(bytes);
          if (!buf) {
            endFlag = true;
            return checkNext();
          }
          r = res.write(buf);
          if (r) {
            return checkNext();
          }
        }, interval);
      })();
    } else {
      kit.debug('unlimited speed');
      return source.pipe(res);
    }
  });

  ResJob.prototype.sendError = function(statusCode) {
    var err, headers, msg;
    msg = http.STATUS_CODES[statusCode];
    if (statusCode >= 400) {
      err = true;
      headers = void 0;
    }
    this.res.writeHead(statusCode, headers);
    this.res.end(msg);
    if (err) {
      kit.log(("Err (" + statusCode + "): ").red + this.url);
    } else {
      kit.log(("Not Modified (" + statusCode + "): ").green + this.url);
    }
    return false;
  };

  return ResJob;

})();

module.exports = SlServer;

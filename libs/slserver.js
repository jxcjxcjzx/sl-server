var DEFAULT_OPTION = {
    clientcache: false,
    port: 8233,
    limit: 0
};

var LIB_PATH = __dirname + '/',
    RES_CHARSET = 'utf-8',
    S_BUFFER_SIZE = 65536;

var notLimitExt = {
    html:true,
    js:true,
    css:true
};

var fs = require("fs"),
    http = require("http"),
    pathKit = require("path"),
    mime = require("mime"),
    colors = require("colors"),
    H = require(LIB_PATH+'helper');

function triggerError(res,errorCode){
    errorCode = errorCode || 404;
    res.writeHead(errorCode);
    res.end();
}

//  APP  //
var app = {};
app.run = function(options){
    var opt = H.extend(DEFAULT_OPTION,options),
        server = http.createServer(),
        timeMs = opt.limit?Math.ceil(S_BUFFER_SIZE * 1000 / 1024 / options.limit):0;

    server.on('request',function(req,res){
        var reqUrl = req.url,
            statusCode = 200,
            file,filename,fileExt,
            header,requestRange;

        H.log(' req'.yellow+' : '+reqUrl);

        switch(reqUrl){
            case '/':
                filename = "index.html";
                break;
            case '/favicon.ico':
                return triggerError(res);
            default:
                filename = reqUrl.substr(1);
        }

        fileExt = pathKit.extname(filename);

        file = {
            name:filename,
            path:"./"+filename,
            ext:fileExt.length && fileExt.substr(1),
            mime: mime.lookup(filename)
        };

        header = {
            "Server":"Sl-Server",
            "Content-Type": file.mime + (file.mime.substr(0,4) === 'text'?';charset=' + RES_CHARSET:''),
            "Connection":"close"
        };

        // User Agent Cache Control
        if (!opt.clientcache) {
            header["Expires"] = 'Wed, 11 Jan 1984 05:00:00 GMT';
            header["Cache-Control"] = 'no-cache, must-revalidate, max-age=0';
            header["Pragma"] = 'no-cache';
        }

        fs.open(file.path,"r",function(err,fd) {
            if(err){
                H.logError('Open file: '+file.path);
                return triggerError(res,404);
            }

            try{
                file.size = fs.fstatSync(fd).size;
            }catch(e){
                H.logError('Get filesize: '+file.path);
                return triggerError(res,500);
            }

            // Content Range Control
            if(req.headers.range && (requestRange=H.parseRequestRange(req.headers.range))){
                H.logWarn('Partial Content from '+requestRange.start);
                statusCode = 206;
                requestRange.end = requestRange.end || file.size;
                requestRange.length = (requestRange.end - requestRange.start) || 0;
                header["Accept-Ranges"] = requestRange.unit;
                header["Content-Range"] = requestRange.unit+" "+requestRange.start+"-"+(file.size-1)+"/"+file.size;
                header["Content-Length"] = requestRange.length;
            }else{
                header["Content-Length"] = file.size;
            }

            // Limit Server Core
            var isNotLimit = !opt.limit || !file.ext || notLimitExt[file.ext],
                buffers = {},
                allsize = file.size,
                fileReadStart = requestRange && requestRange.start || 0,
                index = fileReadStart,
                loopTime = 0,loopFn,nextTickFn;

            // release all buffer memory
            res.on('finish',function(){
                buffers = null;
            });

            loopFn = function(){
                buffers[loopTime] = new Buffer(S_BUFFER_SIZE);//avoid havn't drained but rewriter buffer
                fs.read(fd,buffers[loopTime],0,buffers[loopTime].length,index,function(err,bytesRead,buf){
                    if(err){
                        fs.close(fd);
                        return triggerError(500);
                    }

                    if(bytesRead < S_BUFFER_SIZE){
                        buffers[loopTime] = buf.slice(0,bytesRead);
                    }

                    res.write(buffers[loopTime]);
                    loopTime++;

                    index += bytesRead;
                    //console.log('('+index+'/'+allsize+')'+":"+loopTime);
                    if(index >= allsize){
                        res.end();
                        fs.close(fd);
                        H.log('done'.green+' : '+reqUrl);
                        return;
                    }

                    nextTickFn();
                });
            };

            nextTickFn = isNotLimit ? function(){
                process.nextTick(loopFn);
            } : function(){
                setTimeout(loopFn,timeMs);
            };

            res.writeHead(statusCode,header);
            nextTickFn();
        });
    });

    server.listen(opt.port);
    H.log('Limit speed : [ '+ opt.limit?(opt.limit.toString().yellow + ' KB'):'unlimit'+' ]');
    H.log('Server listen : ' + ('0.0.0.0:'+opt.port).blue);
    H.open("http://127.0.0.1:"+opt.port);
};

module.exports = app;

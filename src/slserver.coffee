fs = require 'fs'
http = require 'http'
path = require 'path'
mime = require 'mime'
colors = require 'colors'
url = require 'url'
kit = require './kit'

DEFAULT_OPTIONS =
    port: 8233
    limit: 0
    cache: false # 默认启用还是不启用
    interval: 50

NO_LIMIT_EXT =
    html: true
    js: true
    css: true

class App
    constructor: (options) ->
        unless @ instanceof App
            return new App(options)

        @opt = kit.default options, DEFAULT_OPTIONS
        @root = path.normalize process.cwd() + path.sep
        @stat = kit.promisify(fs.stat, fs)
        @server = http.createServer().on('request', requestHandle)

    requestHandle: (req, res) =>
        promise = new Promise (resolve, reject) =>
            sendError = (status) ->
                resolve @sendError(status, res)
            cacheJudge = (etag, lastModified) ->
                cacheControl = req['cache-control']
                modifiedSince = req['if-modified-since']
                noneMatch = req['if-none-match']
                matchEtag = matchDate = true
                if cacheControl and ~cacheControl.indexOf('no-cache')
                    return false
                if noneMatch
                    matchEtag = false
                    etags = noneMatch.split / *, */
                    if etags
                        matchEtag = ~etags.indexOf(etag) or '*' is etags[0]
                if modifiedSince
                    modifiedSince = new Date modifiedSince
                    lastModified = new Date lastModified
                    matchDate = lastModified <= modifiedSince
                return matchEtag && matchDate

            urlStr = req.url
            switch urlStr
                when 'favicon.ico' then return sendError(404)
                when '/' then pathname += "index.html"
                else pathname = url.parse(urlStr).pathname

            fullpath = path.normalize path.join(@root, pathname)
            if fullpath.substr(0, @root.length) != @root
                return sendError(403)

            stat = undefined
            headers = undefined
            @stat(fullpath).then (st) =>
                unless st.isFile()
                    return sendError(404)
                stat = st
            .catch (err) ->
                if err.code is 'ENOENT'
                    sendError(404)
                else
                    reject err
            .then =>
                # Common Headers
                headers =
                    "Server": "Sl-Server"
                    "Accept-Ranges": "bytes"
                    "Date": new Date().toUTCString()
                    "Last-Modified": stat.mtime.toUTCString()
                    "ETag": etag(stat)

                # 304
                if @.opt.cache and cacheJudge()
                    res._headers = headers
                    res.writeHead(304)
                    res.end()
                    return resolve()

                # Content-Type
                type = mime.lookup path
                charset = mime.charsets.lookup(type)
                contentType = type + if charset then "; charset=#{ charset }" else ''
                headers["Content-Type"] = contentType

                unless @.opt.cache
                    headers["Expires"] = 'Wed, 11 Jan 1984 05:00:00 GMT'
                    headers["Cache-Control"] = 'no-cache, must-revalidate, max-age=0'
                    headers["Pragma"] = 'no-cache'

                statusCode = 200
                fsOpt = {}
                range = kit.parseRange req.headers["range"], stat.size
                if range
                    if range.error
                        sendError(416)
                    fsOpt.start = range.start
                    fsOpt.end = range.end
                    statusCode = 206
                    headers["Content-Range"] = "#{range.unit} #{range.start}-#{range.end}/#{stat.size}"
                    headers["Content-Length"] = range.end - range.start + 1
                else
                    headers["Content-Length"] = stat.size

                res.on 'end', ->
                    resolve()
                source = fs.createReadStream(path, fsOpt)
                if @opt.limit
                    endFlag = false
                    bytes = @opt.limit * 1024
                    loopTime = Math.floor bytes * @opt.interval / 1000
                    sourceLen = headers["Content-Length"]
                    checkNext = ->
                        if endFlag
                            res.end()
                        else
                            pipe()
                    res.on 'drain', ->
                        checkNext()
                    pipe = () ->
                        setTimeout () ->
                            buf = source.read bytes
                            if !buf
                                endFlag = true
                                return
                            r = res.write buf
                            if r
                                checkNext()
                        , loopTime
                else
                    source.pipe res

            if limit <= 0
                source.pipe res
            else
                time = 50
                bytesInterval = @opt.limit

        promise.catch (err) =>
            @sendError(500, res)

    sendError: (statusCode, res) ->
        msg = http.STATUS_CODES[statusCode]
        res._headers = undefined
        res.statusCode = status
        res.end(msg)

module.exports = App


SlServer = (options) ->
    opt = kit.default options, DEFAULT_OPTIONS
    opt.root = path.normalize process.cwd() + path.sep
    server = http.createServer().on('request', ResJob.onRequest)
    server.listen opt.port
    # TODO log(ip)
    if opt.openbrowser
        kit.open "http://127.0.0.1:#{opt.port}"

class ResJob
    @onRequest: (req, res, opt) -> new @ req, res, opt
    @stat: kit.promisify(fs.stat, fs)
    @P: (func) ->
        (args...) ->
            new Promise (resolve, reject) ->
                func(resolve, reject)
    constructor: (req, res, opt) ->
        @req = req
        @res = res
        self = @

        @promise = new Promise (resolve, reject) ->
            res.on 'finish' ->
                resolve()
            self.resolve = resolve
            self.reject = reject
            self.run()
        @promise.catch (err) ->
            # TODO log
            if typeof err is 'number'
                self.sendError err
            else
                self.sendError 500
    run: ->
        @headers =
            "Server": "Sl-Server"
            "Accept-Ranges": "bytes"
            "Date": new Date().toUTCString()
        getFileStat()
        .then end
        if end


    # 怎么 promise 用 then
    getFileStat: ResJob.P ->
        urlStr = @req.url
        switch urlStr
            when 'favicon.ico' then return @reject 404
            when '/' then pathname = 'index.html'
            else pathname = url.parse(urlStr).pathname
        root = @opt.root
        filepath = path.normalize path.join(@opt.root, pathname)
        if filepath.substr(0, root) != root
            return @reject 403
        ResJob.stat(filepath).then (st) =>
            unless st.isFile()
                return @reject 404
            @stat = st
            @headers["Last-Modified"] = st.mtime.toUTCString()
            @headers["ETag"] = etag(st)
        .catch (err) =>
            if err.code is 'ENOENT'
                @reject 404
            else
                @reject err

    cacheJudge: ResJob.P ->

    sendError: (statusCode) ->
        msg = http.STATUS_CODES[statusCode]
        @res._headers = undefined
        @res.statusCode = status
        @res.end(msg)
        false

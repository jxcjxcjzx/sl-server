fs = require 'fs'
http = require 'http'
path = require 'path'
mime = require 'mime'
colors = require 'colors'
url = require 'url'
etag = require 'etag'
Promise = require 'bluebird'
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

StatP = kit.promisify(fs.stat, fs)
PF = (func) ->
    (args...) ->
        self = @
        new Promise (resolve, reject) ->
            func.call(self ,resolve, reject)

SlServer = (options) ->
    opt = kit.default options, DEFAULT_OPTIONS
    opt.root = path.normalize process.cwd() + path.sep
    opt.bytes = Math.floor 1024 * opt.limit * opt.interval / 1000
    server = http.createServer().on('request', (req, res) ->
        ResJob.onRequest(req, res, opt)
    )
    server.listen opt.port
    ip = kit.getIp()
    ip.unshift('127.0.0.1')
    ip = ip.map (m) -> "#{m}:#{opt.port}"
    if opt.openbrowser
        kit.open "http://127.0.0.1:#{opt.port}"
    kit.debug 'Sl-Server Options', opt
    kit.log 'Server Start: '.blue + ip.join ' / '
    kit.log 'Speed Limit: '.blue + (if opt.limit then opt.limit else 'unlimited') + ' KB'.blue

class ResJob
    @onRequest: (req, res, opt) -> new @ req, res, opt
    constructor: (req, res, opt) ->
        @opt = opt
        @limit = @opt.limit
        @req = req
        @res = res
        @url = req.url
        self = @
        @headers =
            "Server": "Sl-Server"
            "Accept-Ranges": "bytes"
            "Date": new Date().toUTCString()
        kit.log 'Req: '.blue + self.url
        promise = new Promise (resolve, reject) ->
            debug ">> Step : start <<".cyan
            resolve()
        # should wrap? yes
        promise.then ->
            debug ">> Step : fileStat <<".cyan
            self.fileStat()
        .then ->
            debug ">> Step : cacheJudge <<".cyan
            self.cacheJudge()
        .then ->
            debug ">> Step : responseData <<".cyan
            self.responseData()
        .catch (err) ->
            debug ">> Step : catch error <<".cyan
            console.log arguments
            code = 500
            if typeof err is 'number'
                code = err
            else
                console.log err
                console.log err.stack
            self.sendError code

    # 怎么 promise 用 then
    fileStat: PF (resolve, reject) ->
        urlStr = @req.url
        switch urlStr
            when 'favicon.ico' then return @reject 404
            when '/' then pathname = 'index.html'
            else pathname = url.parse(urlStr).pathname
        root = @opt.root
        @filepath = filepath = path.normalize path.join(@opt.root, pathname)
        debug "filename: ".yellow + filepath
        if filepath.substr(0, root.length) != root
            return reject 403
        StatP(filepath).then (st) =>
            unless st.isFile()
                return reject 404
            @stat = st
            @lastModified = @headers["Last-Modified"] = st.mtime.toUTCString()
            @etag = @headers["ETag"] = etag(st)
            type = mime.lookup filepath
            charset = mime.charsets.lookup(type)
            contentType = type + if charset then "; charset=#{ charset }" else ''
            @headers["Content-Type"] = contentType
            unless @opt.weblimit
                ext = path.extname filepath
                if ext in ['.html', '.js', '.css']
                    @limit = 0
            resolve()
        .catch (err) =>
            if err.code is 'ENOENT'
                reject 404
            else
                reject err

    cacheJudge: PF (resolve, reject) ->
        unless @opt.cache
            return resolve()
        req = @req
        headers = req.headers
        cacheControl = headers['cache-control']
        modifiedSince = headers['if-modified-since']
        noneMatch = headers['if-none-match']
        debug ['req cache headers', cacheControl, modifiedSince, noneMatch]
        if (cacheControl and ~cacheControl.indexOf('no-cache') or (!modifiedSince and !noneMatch))
            return resolve()
        if noneMatch
            etags = noneMatch.split `/ *, */`
            debug ['etag', noneMatch, etags]
            if etags
                matchEtag = ~etags.indexOf(noneMatch) or '*' is etags[0]
            if !matchEtag
                return resolve()
        if modifiedSince
            modifiedSince = new Date modifiedSince
            lastModified = new Date lastModified
            if lastModified > modifiedSince
                return resolve()
        reject 304

    responseData: PF (resolve, reject) ->
        self = @
        statusCode = 200
        reqHeaders = @req.headers
        fsOpt = {}
        stat = @stat
        range = kit.parseRange reqHeaders["range"], stat.size
        debug ['range', stat.size, reqHeaders["range"], range]
        if range
            if range.error
                return reject 416
            fsOpt.start = range.start
            fsOpt.end = range.end
            statusCode = 206
            @headers["Accept-Ranges"] = range.unit
            @headers["Content-Range"] = "#{range.unit} #{range.start}-#{range.end}/#{stat.size}"
            @headers["Content-Length"] = range.end - range.start + 1
        else
            @headers["Content-Length"] = stat.size
        unless @.opt.cache
            @headers["Expires"] = 'Wed, 11 Jan 1984 05:00:00 GMT'
            @headers["Cache-Control"] = 'no-cache, must-revalidate, max-age=0'
            @headers["Pragma"] = 'no-cache'

        debug ['fsOpt', fsOpt]
        debug ['respond headers', @headers]
        res = @res
        res.writeHead statusCode, @headers
        res.on 'finish', ->
            console.log "Done (#{statusCode}): #{self.url}".green
            resolve()
        # TODO client close？
        source = fs.createReadStream(@filepath, fsOpt)
        if @limit > 0
            endFlag = false
            bytes = @opt.bytes
            interval = @opt.interval
            sourceLen = @headers["Content-Length"]
            debug "speed limit #{@limit} KB, interval: #{interval} ms, bytes: #{bytes} B"
            checkNext = ->
                if endFlag
                    res.end()
                else
                    pipe()
            res.on 'drain', ->
                checkNext()
            do pipe = () ->
                setTimeout () ->
                    buf = source.read bytes
                    if !buf
                        endFlag = true
                        return checkNext()
                    r = res.write buf
                    if r
                        checkNext()
                , interval

        else
            debug 'unlimited speed'
            source.pipe res

    sendError: (statusCode) ->
        msg = http.STATUS_CODES[statusCode]
        if statusCode >= 400
            err = true
            headers = undefined
        @res.writeHead statusCode, headers
        @res.end(msg)
        if err
            console.log "Err (#{statusCode}): ".red + @url
        else
            console.log "Not Modified (#{statusCode}): ".green + @url
        false

module.exports = SlServer

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
            kit.debug ">> Step : start <<".cyan
            resolve()
        promise.then ->
            kit.debug ">> Step : fileStat <<".cyan
            self.fileStat()
        .then ->
            kit.debug ">> Step : cacheJudge <<".cyan
            self.cacheJudge()
        .then ->
            kit.debug ">> Step : responseData <<".cyan
            self.responseData()
        .catch (err) ->
            kit.debug ">> Step : catch error <<".cyan
            code = 500
            if typeof err is 'number'
                code = err
            else
                kit.log err
                kit.log err.stack
            self.sendError code

    fileStat: PF (resolve, reject) ->
        urlStr = @req.url
        switch urlStr
            when 'favicon.ico' then return @reject 404
            when '/' then pathname = 'index.html'
            else pathname = url.parse(urlStr).pathname
        root = @opt.root
        @filepath = filepath = path.normalize path.join(@opt.root, pathname)
        kit.debug "filename" ,"filename: ".yellow + filepath
        return reject 403 if filepath.substr(0, root.length) != root
        StatP(filepath).then (st) =>
            return reject 404 unless st.isFile()
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
        return resolve() unless @opt.cache
        req = @req
        headers = req.headers
        cacheControl = headers['cache-control']
        modifiedSince = headers['if-modified-since']
        noneMatch = headers['if-none-match']
        kit.debug 'req cache headers cacheControl,modifiedSince,noneMatch', cacheControl, modifiedSince, noneMatch
        return resolve() if (cacheControl and ~cacheControl.indexOf('no-cache') or (!modifiedSince and !noneMatch))
        if noneMatch
            etags = noneMatch.split `/ *, */`
            kit.debug 'etag', noneMatch, etags
            if etags
                matchEtag = ~etags.indexOf(noneMatch) or '*' is etags[0]
            return resolve() if not matchEtag

        if modifiedSince
            modifiedSince = new Date modifiedSince
            lastModified = new Date lastModified
            return resolve() if lastModified > modifiedSince
        reject 304

    responseData: PF (resolve, reject) ->
        self = @
        statusCode = 200
        reqHeaders = @req.headers
        fsOpt = {}
        stat = @stat
        range = kit.parseRange reqHeaders["range"], stat.size
        kit.debug 'range', stat.size, reqHeaders["range"], range
        if range
            return reject 416 if range.error
            fsOpt.start = range.start
            fsOpt.end = range.end
            statusCode = 206
            @headers["Content-Range"] = "#{range.unit} #{range.start}-#{range.end}/#{stat.size}"
            @headers["Content-Length"] = range.end - range.start + 1
        else
            @headers["Content-Length"] = stat.size
        unless @.opt.cache
            @headers["Expires"] = 'Wed, 11 Jan 1984 05:00:00 GMT'
            @headers["Cache-Control"] = 'no-cache, must-revalidate, max-age=0'
            @headers["Pragma"] = 'no-cache, no-store'

        kit.debug 'fsOpt', fsOpt
        kit.debug 'respond headers', @headers
        res = @res
        res.writeHead statusCode, @headers
        res.on 'finish', ->
            kit.log "Done (#{statusCode}): #{self.url}".green
            resolve()
        # TODO client close？
        source = fs.createReadStream(@filepath, fsOpt)
        if @limit > 0
            endFlag = false
            bytes = @opt.bytes
            interval = @opt.interval
            sourceLen = @headers["Content-Length"]
            kit.debug "read loop", "speed limit #{@limit} KB, interval: #{interval} ms, bytes: #{bytes} B"
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
            kit.debug 'unlimited speed'
            source.pipe res

    sendError: (statusCode) ->
        msg = http.STATUS_CODES[statusCode]
        if statusCode >= 400
            err = true
        @res.statusCode = statusCode
        @res._headers = undefined
        @res.writeHead statusCode, headers
        @res.end(msg)
        if err
            kit.log "Err (#{statusCode}): ".red + @url
        else
            kit.log "Not Modified (#{statusCode}): ".green + @url
        false

module.exports = SlServer

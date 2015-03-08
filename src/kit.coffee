Promise = require 'bluebird'
colors = require 'colors'

isDevelopment = process.env.NODE_ENV is 'development'

module.exports =
    open: (args) ->
        switch process.platform
            when 'darwin' then cmd = 'open '
            when 'win32' then cmd = 'start'
        require 'child_process'
            .exec cmd + args

    default: (target, defaults...) ->
        item = defaults.pop()
        while item
            for k, v of item
                unless target[k]?
                    target[k] = v
            item = defaults.pop()
        target

    promisify: (fn, self) ->
        (args...) ->
            new Promise (resolve, reject) ->
                args.push ->
                    if arguments[0]?
                        reject arguments[0]
                    else
                        resolve arguments[1]
                fn.apply self, args

    parseRange: (str, fileLen) ->
        unless str
            return
        matches = str.match /^(.+)=\s*(\d+)?\s*-\s*(\d+)?,?/
        unless matches
            return
        start = matches[2]
        end = matches[3]
        if not start? # -nnn
            start = fileLen - end
            end = fileLen - 1
        else if not end? # nnn-
            end = fileLen - 1
        if end > fileLen - 1
            end = fileLen - 1
        if not start? or not end? or +start > +end or start < 0
            console.log [ '>>' ,start, end, '<<']
            return error: true
        return {
            unit: matches[1]
            start: +start
            end: +end
        }

    getIp: () ->
        os = require 'os'
        netObj = os.networkInterfaces()
        output = []
        for k, v of netObj
            if Array.isArray(v)
                o = v.reduce( (p, c, i) ->
                    if c.family is 'IPv4' and !c.internal
                        p.push c.address
                    p
                [])
            output = output.concat o
        output

    debug: (title, msgs...) ->
        unless isDevelopment
            return
        if arguments.length is 1
            title = ""
            msgs = title
        console.log "debug #{title} >>>>>>> ".yellow
        console.log msgs
        console.log '<<<<<<<<<'.yellow

    log: (msg) ->
        console.log msg

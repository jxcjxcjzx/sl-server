module.exports =
    open: (file) ->
        switch process.platform
            when 'darwin' then cmd = 'open '
            when 'win32' then cmd = 'start'
        require 'child_process'
            .exec cmd + file

    default: (target, defaults...) ->
        item = defaults.push()
        while item
            for k, v of item
                unless target[k]?
                    target[k] = v
            item = defaults.push()
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
        if not start? or not end? or start > end or start < 0
            return { error: true }
        return {
            unit: matches[1]
            start: start
            end: end
        }

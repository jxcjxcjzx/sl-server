var helper = {
    open:function(file){
        var cmd = '';
        switch(process.platform){
            case 'darwin':
                cmd = 'open ';
                break;
            case 'win32':
                cmd = 'start ';
                break;
        }
        require('child_process').exec(cmd + file);
    },
    parseRequestRange:function(str){
        var matches;
        if (matches = str.match(/^(\w+)=(\d+)-(\d+)?/)){
            return {
                unit: matches[1],
                start: +matches[2],
                end: +matches[3]
            };
        }
        return null;
    },
    extend:function(src){
        var i,prop,item,tempValue
        for(i = 1;i<arguments.length;i++){
            item = arguments[i];
            for(prop in item){
                tempValue = item[prop];
                if(tempValue === void 0){
                    continue;
                }
                src[prop] = tempValue;
            }
        }
        return src;
    },
    log:function(str){
        console.log(str);
    },
    logWarn:function(str){
        console.log(str.yellow);
    },
    logError:function(str){
        console.log('error'.red+' : '+str);
    }
};

module.exports = helper;

# A simple speed limit static server
## Overview
一个简单的静态限速服务器

初衷是想要研究下 Web Media 的缓冲机制，本地调试时秒缓存没有条件，所以就有了这个简单的限速服务器

## Start
切换到静态文件根目录
```
cd ~/project/
```
运行
```
slserver
```

## Options
* 限制速度`-l|--limit`(单位KB,默认不限制)
```
slserver -l 500
```

* 设置server接口`-p|--port`(默认8233)
```
slserver -p 8080
```

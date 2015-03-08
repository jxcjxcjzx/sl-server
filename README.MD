# A simple speed limit static server
## Overview
一个简单的静态限速服务器，可以用于模拟差的网络环境

初衷是想要研究下 Web Media 的缓冲机制，本地调试时秒缓冲没有条件，所以就有了这个简单的限速服务器

## Install
```
npm install -g sl-server
```

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

* 完整选项列表

```
Usage:

  slserver -l 100 -p 8233

Options:

  -h, --help       output usage information
  -V, --version    output the version number
  -p, --port <n>   服务器端口，默认8233
  -l, --limit <n>  开启限速，即nKB，单位为KB
  -w, --limitweb   HTML/JS/CSS 文件不限速
  --nocache        禁用HTTP缓存
  --noopen         开启服务器的时候不自动打开浏览器
```

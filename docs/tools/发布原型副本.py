#!/usr/bin/env python3
# 生成 Artifact 发布副本：剥掉外壳标签（发布工具会自己包一层），其余原样
# 用法：python3 docs/tools/发布原型副本.py <输出路径>
import sys
src='docs/KONNEXT_UI原型.html'
dst=sys.argv[1] if len(sys.argv)>1 else 'konnext-ui-prototype.html'
t=open(src,encoding='utf-8').read()
for tag in ['<!doctype html>','<html lang="zh-CN">','<head>','<meta charset="utf-8">',
            '<meta name="viewport" content="width=device-width,initial-scale=1">',
            '</head>','<body>','</body>','</html>']:
    t=t.replace(tag+'\n','',1) if tag+'\n' in t else t.replace(tag,'',1)
open(dst,'w',encoding='utf-8').write(t)
print('发布副本已生成',dst,len(t),'字节')

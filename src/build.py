# -*- coding: utf-8 -*-
"""把 dict.json 灌入 injector.js 的 DICT 行（injector.js 是唯一模板，PATTERNS/逻辑手改）。"""
import json, re, io, os
BASE = os.path.dirname(os.path.abspath(__file__))
d = json.load(open(os.path.join(BASE, 'dict.json'), encoding='utf-8'))
src = open(os.path.join(BASE, 'injector.js'), encoding='utf-8').read()
line = '  var DICT = ' + json.dumps(d, ensure_ascii=False, sort_keys=False) + ';'
new, n = re.subn(r'^  var DICT = \{.*?\};$', lambda m: line, src, count=1, flags=re.M|re.S)
assert n == 1, 'DICT line not found'
open(os.path.join(BASE, 'injector.js'), 'w', encoding='utf-8').write(new)
print('injector.js rebuilt, DICT entries:', len(d), 'bytes:', len(new.encode('utf-8')))

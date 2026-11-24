# -*- coding: utf-8 -*-
"""极简 CDP 客户端：只依赖标准库，用裸 socket 说 WebSocket 协议。

用法：
    import cdp
    tgt = cdp.main_target()                 # 找主窗口 page
    w   = cdp.WS(tgt['webSocketDebuggerUrl'])
    print(cdp.js(w, 'document.title'))
"""
import base64
import json
import os
import socket
import struct
import urllib.request


def _get(url, timeout=10):
    # 本地调试端口必须绕过系统代理
    op = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    return op.open(url, timeout=timeout).read()


def pages(port=9223):
    """列出所有 page target。需要 Antigravity 以 --remote-debugging-port=<port> 启动。"""
    return json.loads(_get('http://127.0.0.1:%d/json/list' % port))


def main_target(port=9223):
    """主窗口：排除 data: 空壳、plugin:// iframe、onboarding 页。"""
    for p in pages(port):
        u = p.get('url', '')
        if (p.get('type') == 'page' and 'data:' not in u and '127.0.0.1' in u
                and 'plugin://' not in u and '/onboarding' not in u):
            return p
    return None


class WS(object):
    def __init__(self, url, timeout=20):
        # url 形如 ws://127.0.0.1:9223/devtools/page/<ID>
        rest = url.split('://', 1)[1]
        hostport, path = rest.split('/', 1)
        host, port = hostport.split(':')
        self.sock = socket.create_connection((host, int(port)), timeout=timeout)
        key = base64.b64encode(os.urandom(16)).decode()
        req = ('GET /%s HTTP/1.1\r\nHost: %s\r\nUpgrade: websocket\r\n'
               'Connection: Upgrade\r\nSec-WebSocket-Key: %s\r\n'
               'Sec-WebSocket-Version: 13\r\n\r\n') % (path, hostport, key)
        self.sock.sendall(req.encode())
        buf = b''
        while b'\r\n\r\n' not in buf:
            buf += self.sock.recv(4096)
        self._id = 0
        self._buf = b''

    def _send_frame(self, payload):
        data = payload.encode('utf-8')
        hdr = bytearray([0x81])
        n = len(data)
        mask = os.urandom(4)
        if n < 126:
            hdr.append(0x80 | n)
        elif n < 65536:
            hdr.append(0x80 | 126)
            hdr += struct.pack('>H', n)
        else:
            hdr.append(0x80 | 127)
            hdr += struct.pack('>Q', n)
        hdr += mask
        masked = bytearray(b ^ mask[i % 4] for i, b in enumerate(data))
        self.sock.sendall(bytes(hdr) + bytes(masked))

    def _recv_exact(self, n):
        while len(self._buf) < n:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise IOError('CDP socket closed')
            self._buf += chunk
        out, self._buf = self._buf[:n], self._buf[n:]
        return out

    def recv_msg(self):
        while True:
            b0, b1 = self._recv_exact(2)
            op = b0 & 0x0F
            n = b1 & 0x7F
            if n == 126:
                n = struct.unpack('>H', self._recv_exact(2))[0]
            elif n == 127:
                n = struct.unpack('>Q', self._recv_exact(8))[0]
            payload = self._recv_exact(n) if n else b''
            if op == 0x8:
                raise IOError('CDP closed by peer')
            if op in (0x9, 0xA):
                continue
            return json.loads(payload.decode('utf-8'))

    def call(self, method, params=None):
        self._id += 1
        mid = self._id
        self._send_frame(json.dumps({'id': mid, 'method': method,
                                     'params': params or {}}))
        while True:
            msg = self.recv_msg()
            if msg.get('id') == mid:
                return msg

    def close(self):
        try:
            self.sock.close()
        except Exception:
            pass


def js(ws, expr, timeout=20):
    """执行 JS 表达式，返回完整 CDP 报文。取值必须 r['result']['result'].get('value')。"""
    return ws.call('Runtime.evaluate', {
        'expression': expr, 'returnByValue': True,
        'awaitPromise': True, 'userGesture': True,
    })


def jsval(ws, expr):
    """执行 JS 并直接返回可用的值（失败返回 None）。"""
    r = js(ws, expr)
    try:
        return r['result']['result'].get('value')
    except Exception:
        return None

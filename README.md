# Antigravity 汉化

给 [Google Antigravity](https://antigravity.google/) 桌面客户端加一层**运行时中文界面**。

官方 2.34.0 没有任何多语言支持——设置里没有语言选项，前端 bundle 里一个中文字符都没有（`main.js` 12.5MB，CJK 计数 0）。所以这个项目不是「翻译文件」，而是往主窗口 `preload.js` 末尾追加一个注入器，在 DOM 渲染后把英文文案就地换成中文，并用 `MutationObserver` 持续跟踪后插入的节点。

只追加，不改业务逻辑；`uninstall.ps1` 一条命令完整还原。

---

## 效果

主界面：

```
Antigravity   工作区  视图  窗口  新对话  自动化  自定义  项目  对话  设置
欢迎回来，渡边彻。我们从哪里继续？
给我做一个 Web 应用 / 在我的应用里加一个 Gemini 功能 / 从其他 Agentic 开发工具迁移我的配置
无项目
随便问，@ 提及，/ 执行操作          Gemini 3.8 Flash 高          请求审核
```

设置页 8 个面板（外观 / 通用 / 浏览器 / 账户 / 模型 / 自定义 / 通知 / 应用）、Marketplace 全部插件卡片、快捷键页 200 多条 `aria-label`、反馈表单、自动化面板、终端与文件预览菜单——都是中文。

残留英文按设计保留：品牌名（Google Workspace、Chrome DevTools、Atlassian Teamwork Graph CLI 等）、URL、键位串（`Ctrl+Enter`）、本地路径。实测设置页残留 2 条、菜单面板残留 14 条，全是上述类型。

---

## 安装

要求：Windows、PowerShell 5.1+、已安装 Antigravity。**不需要 Python，不需要 Node。**

```powershell
git clone https://github.com/<you>/Antigravity-zh.git
cd Antigravity-zh
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

看到 `安装完成。启动 Antigravity 即可看到中文界面。` 后启动 Antigravity 即可。

安装脚本做三件事：

1. 探测 Antigravity 安装目录（`%LOCALAPPDATA%\Programs\antigravity` 等常见位置，找不到就用 `-AppDir` 指定）。
2. 把 `resources\app.asar` 解包成 `resources\app\` 目录，原包改名 `app.asar.orig` 留作备份。Electron 见到目录会优先从目录加载，于是 `preload.js` 变成可直接编辑的普通文件。
3. 在 `resources\app\dist\preload.js` 末尾追加 `src/injector.js`。

先看看会做什么、当前是什么状态：

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1 -Check
```

```
[*] Antigravity 版本 : 2.34.0
[*] 安装目录         : C:\Users\你\AppData\Local\Programs\antigravity
[*] 目录加载模式     : 是
[*] 汉化层已注入     : 是
[*] 词表条目         : 806
```

---

## 卸载

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

从 `preload.js` 剥掉注入器 → 把 `app.asar.orig` 改回 `app.asar` → 删掉解包目录。下次启动就是原版英文界面。

只想关掉中文、保留目录加载模式（比如你想自己改点别的）：

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1 -KeepUnpacked
```

---

## 升级 Antigravity 之后

Antigravity 自动更新会把 `resources\app` 整个覆盖回 `app.asar`，中文就没了。重新跑一次 `install.ps1` 即可——脚本会检测 `app.asar` 比 `package.json` 新，自动重新解包并重新注入。

---

## 改词表

词表 806 条，单一数据源是 `src/dict.py`。它按功能分 17 组 `for k,v in {...}.items(): add(k,v)`，末尾导出 `src/dict.json`。

```powershell
# 改 src/dict.py，加一行 "Your Word": "你的词",
powershell -ExecutionPolicy Bypass -File .\build.ps1
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

`build.ps1` 需要 Python 3（只是把 `dict.json` 灌回 `injector.js` 的 `var DICT = {...};` 那一行）。普通用户装的时候不需要它。

含变量的句子不进词表，进 `src/injector.js` 的 `PATTERNS` 数组——40 条正则，处理问候语、`Select model, current: X`、相对时间、`Add shortcut for X` 这类：

```js
[/^Good to see you, (.+)\. What's next\?$/,
 function (m) { return '很高兴见到你，' + m[1] + '。接下来做什么？'; }],
```

处理函数**返回 `null` 表示放弃这条规则**，继续往下查词表。`Add (.+)$` 就靠这个避免把 `Add Auth0 authentication to any app: ...` 整句吃掉。

---

## 它是怎么工作的

```
Antigravity.exe
  └─ Electron 主进程
       └─ BrowserWindow
            ├─ preload.js   ← 注入器挂在这里（isolated world）
            └─ 页面 DOM      ← 与 preload 共享，可读可改
```

三个关键事实，都是实测出来的：

**1. preload 和页面共享同一个 DOM。** preload 虽然 `process.contextIsolated === true`，但 `document` 是同一个对象，直接改立即生效。所以不需要 `webFrame.executeJavaScript` 跨世界注入——最初的设计绕了远路。

**2. `NODE_OPTIONS=--require` 走不通。** Electron 的 fuse 把这个环境变量禁了，探测脚本一次都没执行。`Antigravity.exe` 里的 fuse wire magic（`dL7p2K9x`）也已被裁掉，改 fuse 开关的路同样堵死。`preload.js` 是唯一可用的注入点。

**3. 必须解包 asar。** `preload.js` 在 `app.asar` 里，改不了。而 Electron 支持「asar 与同名目录并存时优先用目录」，于是解包 + 改名就能让它变成可编辑文件，不用重打包。

注入器本身（`src/injector.js`，68KB）：

```js
tr(s)              // 先 PATTERNS，再判 CJK，最后查 DICT
  ↓
walk(root)         // TreeWalker 遍历 SHOW_TEXT|SHOW_ELEMENT
  ↓
doText(node)       // 改写文本节点，保留前后空白
doAttrs(el)        // 改写 placeholder / title / aria-label / alt
```

- `SKIP_TAGS` 跳过 `SCRIPT/STYLE/CODE/PRE/TEXTAREA/INPUT/KBD/SAMP/NOSCRIPT`
- `SKIP_SEL` 跳过 Monaco、xterm、CodeMirror、`contenteditable`
- `ATTR_SKIP_SEL` 比 `SKIP_SEL` 少一个 `contenteditable` —— 这样输入框里的 placeholder 还能翻，但框里的内容不动
- `MutationObserver` 监听 childList / characterData / 四个属性，队列上限 400，`setTimeout(flush, 0)` 批处理
- 首屏补扫 7 轮（120ms → 10s），加一个 2.5s 常驻扫兜底（React 分批渲染，面板是后挂载的）
- 全程幂等：已含中文的字符串直接跳过，重复扫不会叠加损耗

注入器挂在 preload 的 isolated world 里，**页面主世界看不到它的任何变量**（`window.__AG_ZH_ACTIVE__` 在 DevTools 控制台里是 `undefined`，这是正常的）。它能改 DOM 是因为两个世界共享同一个 `document`，不是因为能共享 `window`。所以调试时别指望从控制台手动触发重扫——改完词表就重装。

---

## 已知边界

- **只影响主窗口。** 原生对话框、右键菜单走的是 Electron 的 `locales\zh-CN.pak`，那是另一套机制，本项目不碰（你要的话自己把 `locales` 里的 `zh-CN.pak` 重命名成 `en-US.pak` 即可，但会影响所有 Electron 应用的习惯，不建议）。
- **Markdown 渲染出的代码块不翻。** `CODE`/`PRE` 在 `SKIP_TAGS` 里，翻了会破坏代码。
- **用户输入的内容不翻。** `contenteditable` 在 `SKIP_SEL` 里。
- **Linux / macOS 未测试。** 脚本是 PowerShell，逻辑上把路径和进程名换掉就能用，但没验证过。
- **没有 Jinja 那种编译期替换。** 这是 DOM 后处理，理论上存在极短的「先显示英文再变中文」的闪烁；首屏 `walk` 在 `DOMContentLoaded` 之前跑，实际肉眼看不到。

---

## 关于登录超时（顺带说明）

如果你是因为「Antigravity 登录谷歌一直超时」找过来的：那是代理问题，和汉化无关。

`language_server.exe` 是 Go 写的，**不读 Windows 系统代理**，只认 `HTTPS_PROXY` / `HTTP_PROXY` / `ALL_PROXY` 环境变量。Antigravity 主进程（Electron）读系统代理，所以浏览器能打开授权页，但 token 交换那一步由 language_server 直连 `oauth2.googleapis.com` —— 于是超时。

用带环境变量的方式启动即可：

```bat
@echo off
set HTTP_PROXY=http://127.0.0.1:7890
set HTTPS_PROXY=http://127.0.0.1:7890
set ALL_PROXY=socks5://127.0.0.1:7890
set NO_PROXY=localhost,127.0.0.1,::1
start "" "%LOCALAPPDATA%\Programs\antigravity\Antigravity.exe"
```

（端口换成你自己的代理端口。）

---

## 目录

```
install.ps1        安装：探测目录 → 解包 asar → 注入 preload
uninstall.ps1      卸载：剥注入器 → 还原 app.asar → 删解包目录
build.ps1          改完词表后重建 injector.js（需 Python 3）
src/dict.py        词表单一数据源，806 条，17 组
src/build.py       把 dict.json 灌回 injector.js 的 DICT 行
src/injector.js    注入器本体，68KB，40 条 PATTERNS
tools/cdp.py       调试用 CDP 客户端（只依赖标准库，裸 socket 实现 WebSocket）
```

---

## License

MIT

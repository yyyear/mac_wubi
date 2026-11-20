# 四方五笔（macOS）

一个轻量、原生的 macOS 五笔输入法，Swift 编写，基于 InputMethodKit。

- **字典**：五笔86（Rime wubi86，13.7 万词条 / 9.9 万编码），编译成 2.9 MB 只读二进制，内存映射加载
- **检索**：编码打包成 27 进制整数，二分查找，精确与前缀查询都在同一张有序表上完成
- **内存**：空闲时常驻约 30 MB（含 AppKit），字典按页换入，不整块解码
- **候选**：自绘非激活面板，不抢焦点，跟随光标，支持数字选词、翻页、鼠标点选
- **学习**：按上屏概率重排候选，记录在独立侧表，不动原始字典

## 快速开始

```bash
git clone <repo> && cd WubiInput
swift test                 # 单元测试
swift run wubi-cli type wqiy   # 命令行试打
swift run wubi-preview     # 带界面的预览程序（不用安装）
./Scripts/install.sh       # 安装到 ~/Library/Input Methods
./Scripts/uninstall.sh     # 卸载
```

安装后启用：系统设置 → 键盘 → 输入法 → 编辑… → **+** → 中文（简体）→「四方五笔」。
若列表中没有，注销重新登录一次，或改用系统级安装：

```bash
./Scripts/install.sh --system   # /Library/Input Methods，需要管理员密码
```

## 中文输入方案与词库

启用四方五笔后，打开 macOS 状态栏的输入法菜单。点击所需方案，或用 ↑ / ↓ 选中后按回车确认；带 ✓ 的是当前方案。三种方案共用一个系统输入源，升级保留已有选择。

- **只五笔**：沿用五笔 86、四码及原有自动上屏设置。
- **只拼音**：输入全拼，例如 `nihao` → 你好、`chongqing` → 重庆；`ü` 用 `v`，可用英文单引号分隔音节。
- **拼音五笔混合**：同一串按键同时查两类编码；完整匹配先于前缀候选，同词只显示一次。不会在第四码自动截断拼音。这是逐词查表，不是整句智能组句，也不是在同一个词内混拼两种编码。

方案切换和「偏好设置…」均不绑定快捷键；旧版保存的方案快捷键不再生效。

**模糊音**：在 **偏好设置 → 输入 → 模糊音** 勾选需要的音对。默认双向匹配 z/zh、c/ch、s/sh、an/ang、en/eng、in/ing；n/l、f/h、l/r 默认关闭。完整准确拼写的候选优先。例如开启 z/zh 后，输入 `zongguo` 也可找「中国」。只五笔不受影响。

**偏好设置 → 词库**：选「拼音」或「五笔」再选文件。支持标准带显式编码的 Rime `.dict.yaml`（词条、编码、可选权重，制表符分隔）、常见搜狗拼音细胞词库 `.scel` 和 UTF-8 `.tsv` / `.txt`。不支持只列汉字而无编码的 Rime 文件、自动解析 `import_tables` 或厂商加密备份。单文件上限 16 MiB，每类最多 30 万条。可多次导入，按方案合并，重复的编码与词条只保留一份。导入不覆盖内置词库。

可先用[自定义拼音词库示例](Examples/自定义拼音词库.tsv)试导入，再输入 `sifangwubi`。升级时若设置已选拼音但仍按四码上屏，请确认运行中的输入法是新版；系统菜单里的输入源名称仍是「四方五笔」，候选窗口提示的是实际方案。

**日常快输**：导入[日常拼音快输词表](Examples/日常拼音快输.tsv)可用 `mywt` → 没有问题、`qcsfj` → 请查收附件。全拼仍可使用。

**本机其他输入法**：若已按标准系统路径安装清歌，可在「词库」点「导入本机清歌拼音词库…」，按原表的候选顺序转换公共词表。不读个人学习记录。青简自带的小型 `dict.tsv` 可按拼音导入，`.qj` 主库、微信专有二进制库与系统输入法核心词库不可直接导入。

通用词表的列间为 Tab，词频可省略：

```text
shurufa	输入法	100
```

## 使用

| 按键 | 行为 |
| --- | --- |
| `a`–`z` | 输入五笔编码（最多 4 码）或连续全拼；可显示前缀候选 |
| `空格` | 上屏第一个候选 |
| `1`–`9` | 上屏对应候选（每页数量可配 1–10） |
| `,` `.` / `←` `→` / PageUp PageDown | 候选翻页 |
| `回车` | 上屏当前编码原文 |
| `Esc` | 取消当前编码 |
| `删除` | 删掉最后一个编码 |
| `Shift`（单击）/ `Shift+空格` | 中/英切换；已打编码先上屏，光标处弹出「中」/「A」徽标 |
| 标点 | 中文模式自动转换全角，引号成对切换 |

### 候选与配置

输入 1–3 码时，除了该编码本身的候选，还会列出**编码以当前输入开头**的词，
所以 `w` 一按下就有 `人/他/个/你/们` 可选，不必等打完四码。

排序按**上屏概率**：每上屏一次就是一次投票，某词在该编码下的命中比例越高排得越前；
没上屏过的词保持字典原序。数据存在 `userfreq.tsv`，菜单里可一键清空。

每页候选数量由 `pageSize` 控制（默认 5，范围 1–10）：

```json
{ "pageSize": 5, "prefixCandidates": true, "showModeHUD": true }
```

### 中英切换提示

单击 `Shift`（或 `Shift+空格`）切换中英文：

- 已经输入的编码会**先上屏**，不会丢字
- 在**输入光标处**弹出一个 44pt 徽标：中文是蓝底「中」，英文是灰底「A」，0.9 秒后淡出
- 客户端拿不到光标位置时，徽标出现在**屏幕右上角**；
客户端拿不到光标位置时，徽标出现在**屏幕右上角**。
## 结构

```
Sources/
  WubiCore/            纯逻辑，无 AppKit 依赖，可测试
    CodePacker.swift       编码打包 / 前缀区间
    WubiDictionary.swift   二进制字典 + 二分检索
    InputEngine.swift      输入状态机（编码、候选、翻页、上屏）
    UserLexicon.swift      词频学习与持久化
    Punctuation.swift      标点映射
    Settings.swift         配置读写
  WubiUI/              候选面板（两个 target 共用）
    CandidatePanel.swift
  WubiInput/           InputMethodKit 服务端
    main.swift             IMKServer 启动
    WubiInputController.swift  NSEvent → 引擎 → 上屏
  WubiPreview/         独立预览程序，验证同一套引擎与面板
  WubiCLI/             命令行 harness
Tools/
  build_dict.py        字典编译（Rime dict.yaml → wubi86.bin）
Scripts/
  build.sh             打包 .app 并签名
  install.sh           安装 + 注册输入源
  uninstall.sh         卸载
  make_icon.swift      生成图标
Resources/
  Info.plist           输入法 bundle 描述
```

## 字典格式

`Tools/build_dict.py` 把 Rime 的 `wubi86.dict.yaml` 编译成 `wubi86.bin`：

```
magic "WUB1" | version | 词条数 | 编码数 | 字符串区大小
keys     编码数 × u32        升序，a..z → 1..26，四位 27 进制
index    编码数 × (u32 偏移, u32 数量)
records  词条数 × (u32 字符串偏移, u16 权重, u8 长度, u8 flags)
blob     UTF-8 字符串区
```

编码零填充后，字典序与数值序一致，因此"某编码的全部候选"和"某前缀的全部编码"都是连续区间，一次二分即可定位。

重新生成字典：

```bash
curl -L -o /tmp/wubi86.dict.yaml https://raw.githubusercontent.com/rime/rime-wubi/master/wubi86.dict.yaml
python3 Tools/build_dict.py /tmp/wubi86.dict.yaml Sources/WubiCore/Resources/wubi86.bin
```

## 配置

`~/Library/Application Support/WubiInput/config.json`（首次运行按默认值生成）：

```json
{
  "autoCommitUnique": true,
  "candidateLimit": 128,
  "chinesePunctuation": true,
  "pageSize": 5,
  "shiftTogglesEnglish": true,
  "showCodeHint": true,
  "userLearning": true
}
```

词频记录在 `userfreq.tsv`，删掉即可重置；输入法菜单里也有「清除用户词频」。

## 性能（实测）

Apple Silicon、release 构建：

| 指标 | 数值 |
| --- | --- |
| 按键吞吐 | 约 228 万键/秒（`wubi-cli bench 20000`） |
| 单次四码查询 | 亚微秒级 |
| 字典文件 | 2.85 MB（mmap，不整块解码） |
| App 包体 | 3.4 MB |
| 可执行文件 | 216 KB |
| 常驻内存 | 约 60 MB（含 AppKit 与共用框架） |

## 设置界面

输入法菜单里有「偏好设置…」，打开一个分栏式设置窗口（左侧分类、右侧面板），
所有选项都直接写回 `config.json`，运行中的输入法立刻生效，无需重启。

| 分类 | 可配置项 |
| --- | --- |
| 词库 | 选择本地拼音或五笔词库文件并导入 |
| 输入 | 查看当前输入方案、四码唯一自动上屏、拼音模糊音 |
| 候选 | 每页数量（1–10）、候选上限（8–256）、前缀候选、编码提示、按上屏概率排序 |
| 标点 | 中文标点转换、**Shift + 标点输入英文标点** |
| 中英文 | 单击 Shift 切换、Shift+空格切换、切换提示徽标 |
| 按键说明 | 查看选词、翻页及中英文切换等按键 |
| 关于 | 版本、字典规模、打开配置目录、清除词频、恢复默认 |

设置保存后会发出分布式通知，输入法进程收到即重载配置；也可以直接编辑配置文件。

## 分发（做成安装器）

```bash
./Scripts/build_pkg.sh          # → build/四方五笔-0.3.1.pkg
./Scripts/build_pkg.sh --sign   # 有 Developer ID 时同时签名
```

安装器做的事：

1. 覆盖安装到 `/Library/Input Methods/WubiInput.app`，保持同一安装位置。
2. 为当前登录用户检查四方五笔模式，按需启用，不强制切换输入源。

如果系统仍显示旧名称，请注销后重新登录一次。

### 关于签名与公证

当前包是**未签名**的：第一次双击会被 Gatekeeper 拦下，用户需右键 →「打开」。
要彻底消除这一步，需要 Apple 开发者账号（$99/年）的两张证书：

| 证书 | 用途 |
| --- | --- |
| Developer ID Application | 签 App 本体 |
| Developer ID Installer | 签 pkg |

拿到后：

```bash
./Scripts/build_pkg.sh --sign
xcrun notarytool submit "build/四方五笔-0.3.1.pkg" \
    --apple-id <你的 Apple ID> --team-id <TeamID> --password <App 专用密码> --wait
xcrun stapler staple "build/四方五笔-0.3.1.pkg"
```

公证过的包双击即可安装，无任何提示。

## 安装说明（macOS 输入法的坑）

macOS 只接受结构完全正确的输入法 bundle，**任何一处写错都会被静默丢弃**——不报错，`TISRegisterInputSource` 返回 noErr，但输入源永远不出现。踩过的三个坑：

| 字段 | 错误写法 | 正确写法 |
| --- | --- | --- |
| `tsInputMethodCharacterRepertoireKey` | `["zh_Hans"]` | `["Hans"]`（必须是脚本标签） |
| 顶层 `TISInputSourceID` | 等于模式 ID | 等于 `CFBundleIdentifier` |
| 模式 ID（`tsInputModeListKey` 的键） | 随意后缀（如 `com.x.y.wubi`） | 与 bundle id 相同，或 bundle id + 语言标签（`com.x.y.Hans`） |

另外 `InputMethodType` 必须是 `Keyboard`；bundle 放在 `/Library/Input Methods`（推荐）或 `~/Library/Input Methods`，属主 `root:wheel`、权限 755，否则系统进程读不到。

装好后**新装的输入法要下次登录才会出现在列表里**：系统在登录时扫描输入法目录并缓存。验证：

```bash
./Scripts/doctor.sh
```

字段全部显示「结构 正确」且 mode 级条目 `enabled=true selectable=true` 后，重新登录即可在「系统设置 → 键盘 → 输入法 → 编辑… → + → 简体中文」里看到「五笔」。

## 输入源出问题时的修复

macOS 的输入源列表由 `com.apple.HIToolbox` 偏好 + `hisd` 会话缓存共同维护，
偶尔会出现「输入法从列表里消失」「重启后又变回 ABC」这类状态错乱。一条命令修复：

```bash
./Scripts/repair-input-sources.sh
```

修复命令只确保四方五笔的可切换模式已启用，不改写系统的输入源列表，也不修改青简等其他输入法。若已有重复条目，请勿反复运行安装器；注销并重新登录后再核对列表。

### 为什么列表里要有英文键盘

macOS 把输入源分成两类：`Keyboard Layout`（ABC、Irish…）和 `Keyboard Input Method`
（四方五笔、微信输入法…）。IMK 应用只能是后者。系统强制至少保留一个键盘布局
（密码框等场景需要它），所以 ABC 无法被"删除"，也不该删。

日常不需要切到它：单击 `Shift` 就能在输入法内部切中英文。

## 已知限制

- 只做 macOS，仅在 macOS 26/27 + Apple Silicon 上验证
- 未实现：拼音反查五笔码、Z 键通配、交互造词、皮肤、词库导出
- **系统收录**：macOS 在**登录时**扫描输入法目录并缓存输入源列表，
  运行中的新装输入法不会被枚举（`TISRegisterInputSource` 返回 noErr 但列表不变）。
  第一次安装后需要**注销并重新登录**（或重启）才会出现在「系统设置 → 键盘 → 输入法」里。
  想安装后立刻看到效果，可以先用 `swift run wubi-preview` 的预览窗口验证引擎与候选面板。
  可用 `./Scripts/doctor.sh` 查看安装位置、签名、Gatekeeper 判定和系统是否已收录

## License

MIT

macOS 五笔输入法 原生
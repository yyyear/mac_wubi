# 内置全拼词库

运行时只读 [pinyin.tsv](../../Sources/WubiCore/Resources/pinyin.tsv)，不联网、不做逐字转写。每行（无表头）为：无声调小写全拼、汉字词、UInt16 优先权，用两个 TAB 分隔。整表按 ASCII 编码升序，同码按优先权降序，平局按 Unicode 码点顺序。65,538 条记录、39,405 个编码、64,788 个不同字词（其中 16,472 个不同单字），约 1.15 MiB。

## 数据与授权

* [Rime 袖珍简化字拼音的固定版本](https://github.com/rime/rime-pinyin-simp/tree/0c6861ef7420ee780270ca6d993d18d4101049d0)源自 [AOSP PinyinIME](https://android.googlesource.com/platform/packages/inputmethods/PinyinIME/)，采用 [Apache License 2.0](https://github.com/rime/rime-pinyin-simp/blob/0c6861ef7420ee780270ca6d993d18d4101049d0/LICENSE)。本目录的 [gzip 快照](pinyin_simp.dict.yaml.gz) 是该版本原始 pinyin_simp.dict.yaml 的无损压缩，未压缩 SHA-256：`e341598343a0f0f2035bb1aafc34a7f3bb7887deeecb3f60796262aaa2983e6b`。生成时验证此摘要。它只用于开发，不必进入应用包。
* 保留上游实际词组读音（如重庆、银行、音乐）以及单字的多种读音；没有将所有多音字逐字组合。上游已有键盘拼法 nv/lv；lue/nue 同时保留，并增加 lve/nve 拼法。
* 本项目原创的 [增补表](extra.tsv) 与派生数据同样按 Apache-2.0 分发，估计权重用于日常对话与现代词汇，不代表当代语料的实测频次。
* [随包声明和完整许可证](../../Sources/WubiCore/Resources/Pinyin-NOTICE.txt) 应与生成词库一起分发。修改内容包括合并音节、补充词条与拼法、去重和重排，不是未修改的上游原件。

## 离线重建

在仓库根目录执行（Python 3 标准库，不需要安装第三方库，不依赖 ICU 版本）：

~~~sh
python3 Tools/build_pinyin.py
python3 Tools/build_pinyin.py --check
~~~

同一个 (code, word) 取最大权重；按所有不同频数的稠密排名压缩到 1…3629，保留原频数的相对次序，不会将高频同音字一起截断到 65535。校验模式重新计算并逐字节比较资源。当前 TSV SHA-256：`2168f7b3a46a43a17c3c0b46546f82a11bf9a709ea2d51cb8ef376aa0cde07e3`。

## 日常短语与 0.2.0 快输包

新增 **331** 个原表没有精确匹配的全拼编码，覆盖问候、聊天、出行、办公、会议、用餐和生活服务。它们不是从用户输入记录或第三方私有词库采集的。采用原词频尺度中已有的 500 作为保守权重；从生成结果过滤掉这 331 条，剩余 65,207 行的字节、权重与顺序均与 0.2.0 完全相同。在启用前缀提示时，新增短语仍可能成为较短编码的补全候选。

[日常拼音快输.tsv](../../Examples/日常拼音快输.tsv) 可直接在 **0.2.0 → 偏好设置 → 词库 → 拼音 → 选择文件** 导入，切换至「只拼音」或「拼音五笔混合」使用。它使用导入格式 `编码<TAB>词条<TAB>权重`（UTF-8），不是本目录增补表的「词、分音节读音、权重」格式。381 条全拼包括全部新增短语及一些已有首选，例如：

- `daojialema` → 到家了吗
- `qingchashoufujian` → 请查收附件
- `shoudaoqinghuifu` → 收到请回复
- `xinkudajiale` → 辛苦大家了

文件末尾另有 **29 个可选的显式简拼**，例如 `wsm` → 为什么、`mywt` → 没有问题、`xk` → 辛苦、`qcsfj` → 请查收附件。这些简拼**不写入内置词库**，也不表示引擎自动支持任意词的首字母匹配。已核对每个简拼都不与新旧出厂全拼精确编码重名；使用者自定义编码、混合方案中的五笔码及输入中的前缀仍可能同码。只想用全拼的，请在**首次导入前**复制文件并删除「可选简拼」以下全部内容；重复导入仅合并，不会删除以前导入的简码。

## 原有首选回归

预期首选示例：nihao → 你好，zhongguo → 中国，chongqing → 重庆，yinhang → 银行，yinyue → 音乐，nv → 女，lve → 略，weixin → 微信，meiwenti → 没问题。

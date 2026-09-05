# Agent Note: 仓库文件浏览与有界文件预览

Status: implemented

## Problem

Flutter 能选择工作区目录（基于 `directoryPicker/list` 的 Miller 列浏览器），
但看不到文件内容：宿主 seam 按约定只列举目录——文件被跳过——也没有任何
Remote 动词读取文件内容。计划的 Phase 3 要求复用文件系统策略实现仓库访问
与预览，而不是另起平行的 seam。

## Decision

在既有目录选择 seam 上生长只读的文件面，不发明新东西：

- `DirectoryEntry` 增加必需的 `kind: 'directory' | 'file'` 戳。
  `list` 接受 `options?: { includeFiles?: boolean }`；缺省时与此前完全一致地
  只列举目录（React 从不发送该标志，看到的行除了惰性戳外逐字节一致）。
  文件行覆盖普通文件与指向文件的符号链接；fifo、socket、设备与断链仍不列出。
- `readFile(path, options?, signal?)` 加入 browse 能力：一个有界文本页
  （`{ path, text, truncated, totalBytes, totalLines? }`），行窗口
  （`offset`/`count`）与页字节上限（`maxBytes`，永不超过配置的
  `maxReadBytes`，默认 262,144）。只返回完整行——被预算截断的尾部残行被
  丢弃，在下一页被完整重读。沿用与 `list` 相同的完全限定路径栅栏；目录、
  缺失路径、二进制内容（NUL 探测）与超限读取回答 `file-unreadable`。分块
  句柄读取使内存保持 O(页大小），中止/关闭规则沿用 seam 既有 discipline。
- `ctx.remote.directoryPicker` 增加 `readFile`（按 `createDirectory` 的先例
  做 zod 校验，非法载荷回答 `gateway/bad-request`），`list` 透传
  `includeFiles`。seam 的 `file-unreadable` 映射到既有
  `directory-picker/unreadable` 协议码——不新增失败词汇。
- Flutter：`WorkspacesService.listDirectory(includeFiles:)` 与 `readFile`；
  每个 workspace tile 推出仓库文件浏览器（目录导航，文件开预览底页，带
  翻页与复制）；两个动词的线协议测试；导航、翻页、位置文案与失败重试的
  widget 测试。面向选择的 Miller 浏览器原样不动。

有意延期：写操作（seam 按设计保持基本只读——创建仍是唯一的变更）、全文
搜索（属于搜索 seam，不是 picker）、预览语法高亮（纯等宽文本与其它代码面一致）。

## Verification

- 浏览后端：真实目录树 spec 加一个只 mock `open` 边界的 fault spec，
  迫使 stat 成功之后出现 EACCES（按政策属于非确定性输入）。单文件
  100% 语句/分支/函数/行，包括抽出的纯 `probedRow` 判定（构造上跨平台——
  Windows 覆盖 lane 建不出文件符号链接），`v8 ignore` 只留给 TOCTOU 短读
  中断与被抛弃关闭路径，各有理由。
- Controller host spec：动词面、选项透传、失败映射、永不分发的坏请求校验、
  原生拒绝。单文件 100%。
- `pnpm run build:lib:host` 全绿，Typert 描述符已重生
  （`directoryPicker/readFile`、`includeFiles`）；新线协议类型指向
  workspace 子系统页面的文档链接已登记。
- Flutter：api-contract 增补与文件浏览器 widget 套件全绿；变更文件上
  analyzer 干净。

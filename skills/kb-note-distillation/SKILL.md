---
name: kb-note-distillation
description: This skill should be used when the user asks to organize/index/"整理" their 如流知识库(ku.baidu-int.com) notes into agent memory, when a new KB topic line needs a distilled index under reference/, or when the KB migrates and existing index pointers must be re-anchored. Covers the ku CLI call patterns, the distill-not-copy rule, and the dual-anchor (title + docGuid) migration-robust format.
version: 0.1.0
---

# KB 笔记提炼成记忆索引

## Overview
把用户如流知识库(KB)里的笔记变成 agent 记忆里的**提炼索引**,而不是原文拷贝。
核心原则(用户已认可):记忆的价值 = 「提炼后的结论 + 回原文的指针」。
- 提炼正文自包含,存在 agent 的 git 记忆里,KB 迁移/删除都不影响 → 这是真资产。
- `docGuid` / 如流 URL 是**脆指针**,KB 一迁移就断 → 每条必须同时留**人可读的标题(和仓库名)**作稳定锚点。
- 不要为分类而分类:先确认某条线是否已在记忆里(如训练线已在 `reference/m300/xpytorch_work.md`),已覆盖就别搬家,免得打断 `[[...]]` 链接。

## Steps

1. **定位用户的库**
   ```bash
   ku=~/.letta/skills/ku-doc-manage/bin/ku      # 需 SANDBOX_USERNAME=<用户名>
   SANDBOX_USERNAME=<user> $ku query-user-info          # 拿 personal repo 的 repositoryGuid/space/group
   ```

2. **拉整棵目录树**(注意是 `--repo-id`,不是 `--repo`)
   ```bash
   SANDBOX_USERNAME=<user> $ku query-repo-dir --repo-id <repoId> --depth -1 > /tmp/ku_tree.json
   ```
   用 python 递归打印 `docGuid | name` 做成干净大纲,再挑值得读的。

3. **批量读正文**
   ```bash
   SANDBOX_USERNAME=<user> $ku query-content --doc-id <guid> > /tmp/ku_<guid>.json
   python3 -c "import json;print(json.load(open('/tmp/ku_<guid>.json'))['result']['text'])"
   ```

4. **分级**:有实料的(用户自己写的分析、踩坑记录、可复现命令)→ 提炼;脚本/符号 dump → 一句话标注"原始素材,需要时回原文";空壳标题 → 记一句"以后填了再提炼",别硬凑内容。

5. **写索引文件** `reference/<topic>/index.md`(或并入已有主题文件),frontmatter 的 `description` 写明主题 + KB 链接格式 `https://ku.baidu-int.com/knowledge/<space>/<group>/<repo>/<docGuid>`。每条格式:
   ```
   ## <中文标题>(一句话定位)`<docGuid>`
   - 用户干的核心活 / 关键技术结论 / 踩过并解决的坑(带具体命令、参数)
   ```
   文件头加一段**迁移鲁棒性说明**:脆指针 vs 稳定锚点 vs 自包含正文,以及迁移时的修法(①确认新平台定位方式 ②批量换指针 ③正文不动)。

6. **加发现路径**:在 `system/human.md` 相应句子里补 `[[reference/<topic>/index.md]]` 链接,再 commit。

7. **KB 迁移时**:不要提前重构。等用户说迁完了,拿新的访问方式,按标题锚点批量把 guid/URL 换成新指针,提炼正文一个字不动。

## Common Pitfalls
- `query-content` 的正文在 `result['text']`,**不在 `result['content']`**(content 常为 null)——直接取 content 会拿到一片 None。
- `query-repo-dir` 的 flag 是 `--repo-id`;超大库(上万篇)返回 `dataMode: "DOWNLOAD"`、`data: []`,真正的树在响应里的 bcebos `download.url`,得先把那个 json 下下来再解析。
- **ku 没有全文搜索**子命令。想找某个主题只能拉树、按标题筛,再批量拉正文 grep;查不到就直说查不到,别编。
- 拷贝原文进记忆是反模式:占上下文、迁移时还要判断哪份是旧快照。
- KB 里的「XX使用技巧」类文档经常是**只有标题的空壳**,别把标题当成有答案。
- KB 正文可能含 AK/SK、密码等凭据;提炼时不要把凭据抄进记忆或回显给用户,按名字引用即可。

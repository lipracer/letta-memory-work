---
description: User's instruction for the "relayH100" trigger phrase.
---
当用户说"relayH100"时(不是"登录H100",旧触发词已废弃),立即弹出新的 iTerm2 窗口,并直接进入 H100 容器。之后由用户自己操作,不要干预。

实现方式:osascript 打开 iTerm2 新窗口,执行 ~/.local/bin/h100(expect 脚本:relay-cli → ssh qa_work@172.19.53.15 → docker exec -it chenlonglong01_dev bash → interact 交还用户)。

注意:
- 必须是新窗口(new window),不是新标签页
- 直接进入容器,不要先打开 shell 再让用户手动进
- 进入后停止,把控制权交给用户
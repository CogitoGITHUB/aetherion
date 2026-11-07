# `aiu-shell-history stats`

aiu-shell-history 还可以根据你的历史记录进行计算统计数据 - 目前这只是一个小的基本功能，但更多功能即将推出

```
$ aiu-shell-history stats day last friday

+---------------------+------------+
| Statistic           | Value      |
+---------------------+------------+
| Most used command   | git status |
+---------------------+------------+
| Commands ran        |        450 |
+---------------------+------------+
| Unique commands ran |        213 |
+---------------------+------------+

$ aiu-shell-history stats day 01/01/21 # 也接受绝对日期
```

它还可以计算所有已知历史记录的统计数据。

```
$ aiu-shell-history stats all

+---------------------+-------+
| Statistic           | Value |
+---------------------+-------+
| Most used command   |    ls |
+---------------------+-------+
| Commands ran        |  8190 |
+---------------------+-------+
| Unique commands ran |  2996 |
+---------------------+-------+
```

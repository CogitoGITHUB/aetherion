# `aiu-shell-history stats`

aiu-shell-history также может выводить статистику, основанную на истории. Пока что в очень простом виде,
но скоро должно появиться больше возможностей.

Статистика выводится пока только на английском
# TODO

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

$ aiu-shell-history stats day 01/01/21 # also accepts absolute dates
```

Также, может быть выведена статистика всей известной aiu-shell-history истории:

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

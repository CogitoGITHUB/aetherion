# stats

aiu-shell-history can also calculate stats based on your history - this is currently a
little basic, but more features to come.

## 1-day stats

You provide the starting point, and aiu-shell-history computes the stats for 24h from that point.
Date parsing is provided by `interim`, which supports different formats
for full or relative dates. Certain formats rely on the dialect option in your
[configuration](../configuration/config.md#dialect) to differentiate day from month.
Refer to [the module's documentation](https://docs.rs/interim/0.1.0/interim/#supported-formats) for more details on the supported date formats.

```
$ aiu-shell-history stats last friday

+---------------------+------------+
| Statistic           | Value      |
+---------------------+------------+
| Most used command   | git status |
+---------------------+------------+
| Commands ran        |        450 |
+---------------------+------------+
| Unique commands ran |        213 |
+---------------------+------------+

# A few more examples:
$ aiu-shell-history stats 2018-04-01
$ aiu-shell-history stats April 1
$ aiu-shell-history stats 01/04/22
$ aiu-shell-history stats last thursday 3pm  # between last thursday 3:00pm and the following friday 3:00pm
```

## Full history stats

```
$ aiu-shell-history stats
# or
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

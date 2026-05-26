# 船舶加油交易数据处理项目流程计划

## 0. 项目目标

本项目的最终目标是：将原始船舶加油记录整理为 **transaction-level 数据集**，即 **一行代表一次 transaction**。

每个 transaction 需要完整保留：

- 船舶信息；
- transaction 全过程起止时间与时长；
- 每一次 `STS-bunkering` 的起止时间、小时和时长；
- 每一次 `STS-bunkering` 对应的 supplier；
- 港口识别结果；
- 与锚地开放数据匹配得到的开放时长变量；
- 与气象预报数据匹配得到的预报开放时长变量；
- 质量检查日志，便于后续人工核验。

> 核心原则：最终数据是一行一个 transaction，但 STS 信息不能按 supplier 去重聚合；同一个 supplier 多次出现，也必须按每一次 STS 记录分别展开。

---

## 1. 推荐仓库结构

建议将项目整理为如下结构：

```text
project_root/
│
├── data_raw/
│   ├── Bunkering Record v3.xlsx
│   ├── 锚地开放.dta
│   └── 气象预报.dta
│
├── data_intermediate/
│   ├── 01_bunkering_preprocessed.xlsx
│   ├── 02_transaction_level_base.xlsx
│   ├── 03_transaction_with_anchor.dta
│   └── 04_transaction_with_weather.dta
│
├── data_final/
│   └── bunkering_transaction_final.dta
│
├── logs/
│   ├── unmatched_ports.xlsx
│   ├── multi_port_transactions.xlsx
│   ├── duplicate_records.xlsx
│   ├── multi_sts_cases.xlsx
│   ├── same_supplier_multi_sts_cases.xlsx
│   ├── time_rounding_cross_day_cases.xlsx
│   └── processing_summary.md
│
├── code/
│   ├── 00_config.py
│   ├── 01_preprocess_bunkering.py
│   ├── 02_build_transaction_level.py
│   ├── 03_match_anchor_open.do
│   ├── 04_match_weather_forecast.do
│   ├── 05_quality_checks.py
│   └── run_all.sh
│
├── docs/
│   ├── PROJECT_PLAN.md
│   └── data_processing_requirements.html
│
└── README.md
```

---

## 2. 总体执行流程

建议将流程拆成五个阶段：

| 阶段 | 脚本 | 目标 | 主要输出 |
|---|---|---|---|
| Stage 1 | `01_preprocess_bunkering.py` | 读取 v3 原始数据，完成行级预处理 | `01_bunkering_preprocessed.xlsx` |
| Stage 2 | `02_build_transaction_level.py` | 聚合为一行一个 transaction，并按每次 STS 展开 | `02_transaction_level_base.xlsx` |
| Stage 3 | `03_match_anchor_open.do` | 匹配锚地开放数据 | `03_transaction_with_anchor.dta` |
| Stage 4 | `04_match_weather_forecast.do` | 匹配气象预报数据 | `04_transaction_with_weather.dta` |
| Stage 5 | `05_quality_checks.py` | 全面质量检查与日志输出 | `bunkering_transaction_final.dta` 与 logs |

---

## 3. Stage 1：原始数据预处理

### 3.1 输入文件

```text
data_raw/Bunkering Record v3.xlsx
```

必须使用修正后的 `Bunkering Record v3.xlsx`，不要再使用旧版本文件。

### 3.2 主要任务

1. 读取原始 Excel；
2. 根据第一列 vessel 信息是否非空识别 transaction 起点；
3. 生成 `transaction_id`；
4. 对 vessel 信息向下填充；
5. 解析船舶信息；
6. 解析时间；
7. 修正小时四舍五入与跨日进位；
8. 提取 duration；
9. 提取 draught 数字部分；
10. 识别 `anchorage` 与 `STS-bunkering`；
11. 从 `Location details` 中提取 supplier；
12. 从 anchorage 行中匹配 port；
13. 输出预处理后的行级数据。

### 3.3 必须生成的行级变量

| 变量 | 含义 |
|---|---|
| `row_id` | 原始行号 |
| `transaction_id` | transaction 编号 |
| `vessel_raw` | 原始 vessel 信息 |
| `vessel_name` | 船名 |
| `vessel_code` | 船舶代码 |
| `vessel_type` | 船舶类型 |
| `in_service_commission` | 船舶状态 |
| `dwt` | 载重吨，numeric |
| `gt` | 总吨，numeric |
| `operation` | 原始 operation |
| `is_anchorage` | 是否为 anchorage |
| `is_sts` | 是否为 STS-bunkering |
| `start_raw` | 原始开始时间 |
| `end_raw` | 原始结束时间 |
| `start_dt` | 解析后的开始 datetime |
| `end_dt` | 解析后的结束 datetime |
| `start_dt_round` | 四舍五入后的开始 datetime |
| `end_dt_round` | 四舍五入后的结束 datetime |
| `startdate_round` | 四舍五入后的开始日期 |
| `starthour_round` | 四舍五入后的开始小时 |
| `enddate_round` | 四舍五入后的结束日期 |
| `endhour_round` | 四舍五入后的结束小时 |
| `duration_hours` | 时长，小时 |
| `draught` | 吃水深度 numeric |
| `location_details` | 原始位置详情 |
| `supplier_raw` | STS 行中提取出的 supplier |
| `port_matched` | anchorage 行匹配到的中文港口 |

### 3.4 时间处理规则

所有输出到最终数据的日期与小时都必须来自四舍五入后的 datetime。

正确逻辑：

```python
if minute >= 30:
    datetime = datetime + 1 hour
datetime = datetime.replace(minute=0, second=0, microsecond=0)
```

错误逻辑：

```python
hour = hour + 1
if hour == 24:
    hour = 0
# 但日期没有推进
```

必须额外输出跨日检查日志：

```text
logs/time_rounding_cross_day_cases.xlsx
```

该日志应包含所有分钟数导致日期进位的记录，便于人工检查。

---

## 4. Stage 2：构建 transaction-level 数据

### 4.1 输入文件

```text
data_intermediate/01_bunkering_preprocessed.xlsx
```

### 4.2 核心原则

最终数据必须是：

```text
一行 = 一次 transaction
```

但 STS 展开必须是：

```text
每一次 STS-bunkering 记录 = 一个 STS slot
```

不能按 supplier 去重。

也就是说：

| 原始情况 | 正确处理 |
|---|---|
| supplier A 出现 1 次 STS | 生成 `supplier1 = A` |
| supplier A 连续出现 2 次 STS | 生成 `supplier1 = A`, `supplier2 = A` |
| supplier A 和 supplier B 各出现 1 次 STS | 生成 `supplier1 = A`, `supplier2 = B` |
| supplier A 出现 2 次、supplier B 出现 1 次 | 生成 `supplier1 = A`, `supplier2 = A`, `supplier3 = B` |

### 4.3 transaction 全过程变量

对每个 transaction：

| 变量 | 规则 |
|---|---|
| `startdate` | 全部行中最早 `start_dt_round` 的日期 |
| `starthour` | 全部行中最早 `start_dt_round` 的小时 |
| `enddate` | 全部行中最晚 `end_dt_round` 的日期 |
| `endhour` | 全部行中最晚 `end_dt_round` 的小时 |
| `duration` | `end_dt_round - start_dt_round`，单位小时，四舍五入 |

### 4.4 STS 展开变量

对每个 transaction，筛选 `is_sts == 1` 的行，并按 `start_dt_round` 排序。

第 k 条 STS 记录生成：

| 变量 | 含义 |
|---|---|
| `supplier{k}` | 第 k 次 STS 对应 supplier |
| `start_STS{k}` | 第 k 次 STS 开始日期 |
| `starthour_STS{k}` | 第 k 次 STS 开始小时 |
| `end_STS{k}` | 第 k 次 STS 结束日期 |
| `endhour_STS{k}` | 第 k 次 STS 结束小时 |
| `duration_STS{k}` | 第 k 次 STS 时长 |

同时生成：

| 变量 | 规则 |
|---|---|
| `supplier_n` | STS 记录数，不是 unique supplier 数 |
| `duration_STS` | 所有 `duration_STS{k}` 加总 |
| `end_STS_final` | 最后一条 STS 的结束日期 |
| `endhour_STS_final` | 最后一条 STS 的结束小时 |

### 4.5 max_STS 的确定

`max_STS` 应该等于所有 transaction 中最大的 STS 记录数，而不是最大的 unique supplier 数。

示例：

```python
max_STS = (
    df[df["is_sts"] == 1]
    .groupby("transaction_id")
    .size()
    .max()
)
```

然后动态生成：

```text
supplier1 ... supplierN
start_STS1 ... start_STSN
starthour_STS1 ... starthour_STSN
end_STS1 ... end_STSN
endhour_STS1 ... endhour_STSN
duration_STS1 ... duration_STSN
```

### 4.6 港口 port 识别规则

对每个 transaction：

1. 只从 `is_anchorage == 1` 的行中识别 port；
2. 只有对照表中的港口才算有效；
3. 如果没有匹配到对照表港口，`port` 留空；
4. 如果出现一个有效港口和若干无效港口，使用有效港口；
5. 如果出现多个有效港口，不能随意取第一个，必须：
   - 保留一个主变量 `port`；
   - 生成 `port_multi_flag = 1`；
   - 生成 `port_all_matched`，记录所有匹配到的港口；
   - 输出至 `logs/multi_port_transactions.xlsx` 供人工核查。

### 4.7 Stage 2 输出

```text
data_intermediate/02_transaction_level_base.xlsx
```

该文件应包含：

- transaction_id；
- vessel 信息；
- transaction 全过程时间；
- 每次 STS 展开变量；
- supplier_n；
- duration_STS；
- end_STS_final；
- endhour_STS_final；
- port；
- port_multi_flag；
- port_all_matched；
- draught；
- unmatched_port。

---

## 5. Stage 3：匹配锚地开放数据

### 5.1 输入文件

```text
data_intermediate/02_transaction_level_base.xlsx
data_raw/锚地开放.dta
```

### 5.2 匹配键

使用：

```text
port + startdate + starthour
```

为了计算窗口变量，需要先把 transaction 开始时点转换成可加减小时的 datetime。

### 5.3 时间窗口定义

按需求，窗口是以 transaction 开始时点为中心的前后窗口：

| 变量 | 窗口 |
|---|---|
| `openhour_6` | 从 t-6 到 t+6 |
| `openhour_12` | 从 t-12 到 t+12 |
| `openhour_24` | 从 t-24 到 t+24 |

注意：如果包含 t 本身，则窗口长度分别是 13、25、49 小时。代码和文档必须明确这一点。

### 5.4 计算逻辑

对每个 transaction：

1. 生成 `t-6` 到 `t+6` 的所有小时；
2. 按 `port + date + hour` 匹配 `锚地开放.dta`；
3. 统计 `status == "open"` 或 `status == "Open"` 的小时数；
4. 生成 `openhour_6`；
5. 对 12 和 24 小时重复同样操作。

### 5.5 缺失值处理

不要简单把所有 missing 都替换为 0。

应区分：

| 情况 | 处理 |
|---|---|
| port 为空 | `openhour_* = .`，并标记 `anchor_match_flag = 0` |
| port 不为空，但外部数据无对应 date-hour-port | `openhour_* = .`，并输出日志 |
| 成功匹配，但窗口内没有开放小时 | `openhour_* = 0` |
| 成功匹配，部分小时缺失 | 保留实际加总，并生成 `anchor_window_coverage_*` |

建议生成：

| 变量 | 含义 |
|---|---|
| `anchor_match_flag` | 是否至少匹配到一条锚地开放记录 |
| `anchor_window_coverage_6` | 6 小时窗口内成功匹配的小时数 |
| `anchor_window_coverage_12` | 12 小时窗口内成功匹配的小时数 |
| `anchor_window_coverage_24` | 24 小时窗口内成功匹配的小时数 |

---

## 6. Stage 4：匹配气象预报数据

### 6.1 输入文件

```text
data_intermediate/03_transaction_with_anchor.dta
data_raw/气象预报.dta
```

### 6.2 需要生成的变量

版本 1：

| 变量 | 规则 |
|---|---|
| `openhourf_6_v1` | 气象指数 2、3、4 记为开放，1 记为不开放 |
| `openhourf_12_v1` | 同上 |
| `openhourf_24_v1` | 同上 |

版本 2：

| 变量 | 规则 |
|---|---|
| `openhourf_6_v2` | 按开放概率加总 |
| `openhourf_12_v2` | 按开放概率加总 |
| `openhourf_24_v2` | 按开放概率加总 |

### 6.3 版本 1 计算规则

```text
weather_index == 1 -> open = 0
weather_index in {2, 3, 4} -> open = 1
```

窗口定义与 Stage 3 完全一致。

### 6.4 版本 2 计算规则

```text
open probability = 1 - closure frequency
```

使用 `closure_frequency.csv` 的 `Average` 列：

| MIO | closure frequency | open probability |
|---:|---:|---:|
| 1 | 72% | 0.28 |
| 2 | 27% | 0.73 |
| 3 | 13% | 0.87 |
| 4 | 12% | 0.88 |

### 6.5 closure frequency 来源

`data_raw/closure_frequency.csv`。正式计算使用 `Average`，不使用 port-specific 列。

示例：

| port | weather_index | closure_frequency |
|---|---:|---:|
| 条帚门 | 1 | 1.00 |
| 条帚门 | 2 | 0.35 |
| 条帚门 | 3 | 0.10 |
| 条帚门 | 4 | 0.00 |

版本 2 计算：

```text
open_probability = 1 - closure_frequency
openhourf_N_v2 = sum(open_probability over t-N to t+N)
```

---

## 7. Stage 5：最终质量检查

### 7.1 必做检查

| 检查项 | 目标 |
|---|---|
| transaction 数量 | 与原始 transaction_id 数一致，扣除重复后需说明 |
| STS 数量 | 最终所有 STS slot 数应等于原始 STS 行数 |
| supplier_n | 应等于每个 transaction 的 STS 行数 |
| duration_STS | 应等于所有 `duration_STS{k}` 加总 |
| end_STS_final | 应等于最后一条 STS 的结束日期 |
| port | 只能来自港口对照表 |
| 多港口 | 必须输出人工核查日志 |
| 未匹配港口 | 必须输出日志 |
| 跨日四舍五入 | 必须输出日志 |
| duplicate | 必须输出删除前后数量和明细 |
| 锚地开放匹配 | 必须输出匹配率和窗口覆盖率 |
| 气象预报匹配 | 必须输出匹配率和窗口覆盖率 |
| forecast v2 | 必须说明 closure frequency 来源 |

### 7.2 推荐检查代码逻辑

#### 检查 supplier_n 是否等于 STS 行数

```python
raw_sts_count = (
    preprocessed[preprocessed["is_sts"] == 1]
    .groupby("transaction_id")
    .size()
)

final_supplier_n = final.set_index("transaction_id")["supplier_n"]

check = raw_sts_count.compare(final_supplier_n)
```

如果 `check` 非空，说明 STS 展开不符合需求。

#### 检查 duration_STS

```python
duration_cols = [c for c in final.columns if c.startswith("duration_STS") and c != "duration_STS"]

final["duration_STS_check"] = final[duration_cols].sum(axis=1)

mismatch = final[final["duration_STS"] != final["duration_STS_check"]]
```

#### 检查 supplier 重复但 STS 未拆开的情况

```python
same_supplier_multi_sts = (
    preprocessed[preprocessed["is_sts"] == 1]
    .groupby(["transaction_id", "supplier_raw"])
    .size()
    .reset_index(name="sts_count")
)

same_supplier_multi_sts = same_supplier_multi_sts[same_supplier_multi_sts["sts_count"] > 1]
```

该表必须输出到：

```text
logs/same_supplier_multi_sts_cases.xlsx
```

---

## 8. 最终输出变量清单

最终数据至少应包含以下变量。

### 8.1 识别变量

```text
transaction_id
```

### 8.2 船舶信息

```text
vessel_name
vessel_code
vessel_type
in_service_commission
dwt
gt
draught
```

### 8.3 transaction 全过程时间

```text
startdate
starthour
enddate
endhour
duration
```

### 8.4 港口变量

```text
port
port_multi_flag
port_all_matched
unmatched_port
```

### 8.5 STS / supplier 变量

```text
supplier1
supplier2
...
supplierN

supplier_n

start_STS1
starthour_STS1
end_STS1
endhour_STS1
duration_STS1

start_STS2
starthour_STS2
end_STS2
endhour_STS2
duration_STS2

...

duration_STS
end_STS_final
endhour_STS_final
```

注意：`N = max_STS`，其中 `max_STS` 是所有 transaction 中最大的 STS 记录数，不是最大 supplier 去重数量。

### 8.6 锚地开放变量

```text
openhour_6
openhour_12
openhour_24

anchor_match_flag
anchor_window_coverage_6
anchor_window_coverage_12
anchor_window_coverage_24
```

### 8.7 气象预报变量

```text
openhourf_6_v1
openhourf_12_v1
openhourf_24_v1

openhourf_6_v2
openhourf_12_v2
openhourf_24_v2

weather_match_flag
weather_window_coverage_6
weather_window_coverage_12
weather_window_coverage_24
```

---

## 9. 当前仓库需要重点修正的地方

### 9.1 必须修正：STS 展开逻辑

当前不应按 unique supplier 聚合。

应从：

```text
按 supplier 分组，合并同一 supplier 的多次 STS
```

改为：

```text
按 STS 行逐条展开，同一 supplier 多次出现也保留多列
```

### 9.2 必须修正：supplier_n 定义

当前不应表示 unique supplier 数。

应改为：

```text
supplier_n = 当前 transaction 中 STS-bunkering 记录数量
```

### 9.3 必须修正：max_STS 定义

当前不应使用 max unique suppliers。

应改为：

```text
max_STS = 每个 transaction 的 STS 行数最大值
```

### 9.4 建议修正：缺失匹配值不能全部替换为 0

锚地开放和气象预报匹配时，missing 与真实 0 含义不同。

必须区分：

```text
没有匹配到数据
```

和

```text
匹配到了数据，但开放小时数为 0
```

### 9.5 forecast v2 口径

forecast v2 已有正式来源：`data_raw/closure_frequency.csv` 的 `Average` 列。不得把 port-specific 列或经验估计结果混入正式 `openhourf_*_v2` 变量。

---

## 10. 分步骤执行建议

### Step 1：先只修正 Stage 2

优先修正 `02_build_transaction_level.py`，不要一开始就重写所有外部匹配代码。

目标：

- 一行一个 transaction；
- 每次 STS 单独展开；
- supplier_n 等于 STS 行数；
- duration_STS 等于所有 STS 时长加总；
- 同 supplier 多 STS 能正确保留。

完成后先跑质量检查：

```text
raw STS rows == final expanded STS slots
```

如果这一步不通过，不要继续做 Stage 3 和 Stage 4。

### Step 2：修正 port 多港口逻辑

增加：

```text
port_multi_flag
port_all_matched
logs/multi_port_transactions.xlsx
logs/unmatched_ports.xlsx
```

### Step 3：重新跑锚地开放匹配

重点确认：

- date-hour-port 是否正确；
- 跨日窗口是否正确；
- missing 是否被错误替换为 0；
- 是否输出窗口覆盖率。

### Step 4：重新跑气象预报匹配

重点确认：

- v1 是否完成；
- v2 是否有 closure frequency 表；
- 如果没有 closure frequency 表，不要把经验估计结果当成正式结果。

### Step 5：生成最终检查报告

最终必须输出：

```text
logs/processing_summary.md
```

建议报告包含：

```text
1. 原始行数
2. 原始 transaction 数
3. 原始 STS 行数
4. 最终 transaction 数
5. 最终 STS slot 数
6. 删除 duplicate 数
7. 港口匹配率
8. 未匹配港口数量
9. 多港口 transaction 数
10. 锚地开放匹配率
11. 气象预报匹配率
12. forecast v2 closure frequency 来源
13. 所有质量检查是否通过
```

---

## 11. 最终验收标准

只有同时满足以下条件，才能认为项目完成：

- 使用 `Bunkering Record v3.xlsx`；
- 最终数据一行一个 transaction；
- 每次 STS-bunkering 都单独展开；
- 同 supplier 多次 STS 没有被合并；
- `supplier_n` 等于 STS 记录次数；
- `duration_STS` 等于所有 STS 时长之和；
- `end_STS_final` 与 `endhour_STS_final` 来自最后一次 STS；
- `port` 只来自港口对照表；
- 港口模糊匹配可处理截断名称；
- duplicate 已处理并留痕；
- 锚地开放变量 `openhour_6/12/24` 已生成；
- 气象预报变量 `openhourf_*_v1` 已生成；
- 气象预报变量 `openhourf_*_v2` 有明确 closure frequency 来源；
- 未匹配港口、多港口、多 STS、同 supplier 多 STS、跨日四舍五入、duplicate 均有检查日志；
- Python 阶段输出 `.xlsx` 中间表，Stata 阶段输出 `.dta` 结果表；
- 最终输出 `bunkering_transaction_final.dta`；
- `logs/processing_summary.md` 明确说明所有检查结果。

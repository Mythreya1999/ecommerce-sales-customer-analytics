# 03_customer_analysis.sql


### Result 1: `WITH cb AS (`

*1 rows returned*

|   buying_customers |   one_time_customers |   repeat_customers |   repeat_rate_pct |   pct_revenue_from_one_time |   pct_revenue_from_repeat |   avg_orders_per_customer |   avg_revenue_per_customer |
|-------------------:|---------------------:|-------------------:|------------------:|----------------------------:|--------------------------:|--------------------------:|---------------------------:|
|              22208 |                 4399 |              17809 |             80.19 |                         4.4 |                      95.6 |                      3.93 |                    96662.1 |


### Result 2: `WITH base AS (`

*8 rows returned*

| segment                 |   customers |   pct_customers |     revenue |   pct_revenue |   avg_revenue |   avg_orders |   avg_recency_days |   avg_rfm_score |
|:------------------------|------------:|----------------:|------------:|--------------:|--------------:|-------------:|-------------------:|----------------:|
| 1. Champions            |        3085 |           13.89 | 6.79048e+08 |         31.63 |      220113   |         7.32 |                 49 |            4.58 |
| 5. At Risk (high value) |        2359 |           10.62 | 5.23511e+08 |         24.39 |      221921   |         7.35 |                713 |            3.57 |
| 2. Loyal                |        2655 |           11.96 | 3.40125e+08 |         15.84 |      128107   |         6.11 |                211 |            3.86 |
| 8. Occasional           |        4798 |           21.6  | 2.12776e+08 |          9.91 |       44346.8 |         3.05 |                383 |            2.72 |
| 6. Cannot Lose          |         917 |            4.13 | 1.37058e+08 |          6.38 |      149464   |         2.33 |                725 |            2.72 |
| 4. Needs Attention      |        1812 |            8.16 | 9.72109e+07 |          4.53 |       53648.4 |         2.55 |                301 |            2.68 |
| 3. New / Promising      |        3004 |           13.53 | 9.4928e+07  |          4.42 |       31600.5 |         1.55 |                 63 |            2.65 |
| 7. Lost                 |        3578 |           16.11 | 6.20157e+07 |          2.89 |       17332.5 |         1.45 |                737 |            1.52 |


### Result 3: `WITH cb AS (`

*20 rows returned*

| customer_id   | customer_segment   | loyalty_tier   | city               | state          |   orders |   distinct_products |          revenue |      aov |   margin_pct | first_order   | last_order   |   days_since_last_order |   pct_of_total_revenue |
|:--------------|:-------------------|:---------------|:-------------------|:---------------|---------:|--------------------:|-----------------:|---------:|-------------:|:--------------|:-------------|------------------------:|-----------------------:|
| CUST117355    | Premium            | Platinum       | Noida              | Uttar Pradesh  |       12 |                  30 |      1.10741e+06 |  92284.1 |         5.03 | 2025-02-18    | 2025-11-09   |                      52 |                  0.052 |
| CUST124072    | Premium            | Platinum       | Surat              | Gujarat        |       11 |                  29 |      1.1019e+06  | 100173   |         8.2  | 2023-03-06    | 2023-05-19   |                     957 |                  0.051 |
| CUST108876    | Premium            | Platinum       | Bhopal             | Madhya Pradesh |        9 |                  25 |      1.04158e+06 | 115731   |         1.59 | 2024-03-22    | 2025-12-23   |                       8 |                  0.049 |
| CUST119192    | Premium            | Platinum       | Vadodara           | Gujarat        |       13 |                  35 |      1.03916e+06 |  79935.1 |         6.63 | 2023-08-26    | 2025-12-12   |                      19 |                  0.048 |
| CUST102738    | Premium            | Platinum       | Hyderabad          | Telangana      |       14 |                  29 |      1.02881e+06 |  73486.3 |         2.95 | 2025-12-02    | 2025-12-31   |                       0 |                  0.048 |
| CUST123291    | Premium            | Platinum       | Thiruvananthapuram | Kerala         |       20 |                  48 | 983411           |  49170.6 |         2.15 | 2023-12-21    | 2024-03-16   |                     655 |                  0.046 |
| CUST117572    | Premium            | Platinum       | Warangal           | Telangana      |       15 |                  35 | 968447           |  64563.2 |         6.54 | 2024-12-23    | 2025-11-30   |                      31 |                  0.045 |
| CUST103572    | Premium            | Platinum       | Kanpur             | Uttar Pradesh  |        7 |                  18 | 927460           | 132494   |        10.75 | 2025-08-29    | 2025-11-11   |                      50 |                  0.043 |
| CUST113657    | Premium            | Platinum       | Mysuru             | Karnataka      |       15 |                  37 | 913360           |  60890.7 |         0.75 | 2024-05-31    | 2024-08-07   |                     511 |                  0.043 |
| CUST110963    | Premium            | Platinum       | New Delhi          | Delhi          |        6 |                  16 | 910787           | 151798   |        -2.76 | 2024-05-01    | 2024-09-01   |                     486 |                  0.042 |
| CUST100299    | Premium            | Platinum       | Jodhpur            | Rajasthan      |       14 |                  36 | 904611           |  64615.1 |         9.29 | 2023-05-20    | 2025-10-25   |                      67 |                  0.042 |
| CUST111776    | Premium            | Platinum       | Coimbatore         | Tamil Nadu     |       11 |                  34 | 891453           |  81041.2 |        -0.02 | 2023-09-16    | 2024-07-26   |                     523 |                  0.042 |
| CUST119367    | Premium            | Platinum       | Surat              | Gujarat        |       16 |                  40 | 886691           |  55418.2 |         1.12 | 2023-04-04    | 2023-05-25   |                     951 |                  0.041 |
| CUST101461    | Premium            | Platinum       | New Delhi          | Delhi          |       14 |                  39 | 884293           |  63163.8 |         3.52 | 2023-06-30    | 2023-09-02   |                     851 |                  0.041 |
| CUST113691    | Premium            | Platinum       | Visakhapatnam      | Andhra Pradesh |       13 |                  35 | 873962           |  67227.8 |         0.15 | 2023-03-07    | 2023-08-03   |                     881 |                  0.041 |
| CUST106941    | Premium            | Platinum       | Mumbai             | Maharashtra    |       15 |                  40 | 869904           |  57993.6 |         1.89 | 2025-09-26    | 2025-12-12   |                      19 |                  0.041 |
| CUST108730    | Premium            | Platinum       | Ahmedabad          | Gujarat        |        9 |                  31 | 866607           |  96289.6 |        -6.85 | 2023-06-12    | 2023-10-23   |                     800 |                  0.04  |
| CUST119804    | Premium            | Platinum       | Mumbai             | Maharashtra    |       16 |                  41 | 866255           |  54140.9 |         2.27 | 2023-12-19    | 2024-11-09   |                     417 |                  0.04  |
| CUST121965    | Premium            | Platinum       | Bengaluru          | Karnataka      |       12 |                  29 | 866112           |  72176   |         5.68 | 2025-12-05    | 2025-12-31   |                       0 |                  0.04  |
| CUST112006    | Premium            | Platinum       | Coimbatore         | Tamil Nadu     |       10 |                  30 | 864236           |  86423.6 |         6.77 | 2024-07-05    | 2025-03-12   |                     294 |                  0.04  |


### Result 4: `WITH cb AS (`

*1 rows returned*

|   total_buying_customers |   customers_for_50pct_revenue |   customers_for_80pct_revenue |   pct_customers_for_80pct |   pct_customers_for_50pct |
|-------------------------:|------------------------------:|------------------------------:|--------------------------:|--------------------------:|
|                    22208 |                          3212 |                          7839 |                      35.3 |                      14.5 |


### Result 5: `WITH cb AS (`

*4 rows returned*

| loyalty_band   |   customers |   avg_orders |   avg_customer_revenue |   total_revenue |   pct_revenue |   margin_pct |   avg_lifespan_days |
|:---------------|------------:|-------------:|-----------------------:|----------------:|--------------:|-------------:|--------------------:|
| 1. One-time    |        4399 |         1    |                21492.9 |     9.45472e+07 |          4.4  |         8.04 |                   0 |
| 2. Repeat 2-3  |        8356 |         2.46 |                54758.8 |     4.57564e+08 |         21.32 |         8.34 |                 136 |
| 3. Repeat 4-6  |        5273 |         4.67 |               112545   |     5.93449e+08 |         27.65 |         8.13 |                 218 |
| 4. Repeat 7+   |        4180 |         9.05 |               239501   |     1.00111e+09 |         46.64 |         7.82 |                 269 |


### Result 6: `SELECT customer_segment,`

*4 rows returned*

| customer_segment   |   customers |   orders |     revenue |   pct_revenue |     aov |   revenue_per_customer |   margin_pct |   return_rate_pct |   avg_delivery_days |
|:-------------------|------------:|---------:|------------:|--------------:|--------:|-----------------------:|-------------:|------------------:|--------------------:|
| Regular            |       10707 |    43841 | 1.04417e+09 |         48.64 | 23817.3 |                97522.6 |         8.02 |              5.33 |                4.1  |
| Premium            |        2989 |    26096 | 7.382e+08   |         34.39 | 28287.8 |               246972   |         7.89 |              5.1  |                4.12 |
| Budget             |        6468 |    14299 | 3.01127e+08 |         14.03 | 21059.3 |                46556.4 |         8.59 |              5.66 |                4.09 |
| New                |        2044 |     3124 | 6.3172e+07  |          2.94 | 20221.5 |                30906.1 |         7.03 |              5.13 |                4.07 |


### Result 7: `SELECT loyalty_tier,`

*4 rows returned*

| loyalty_tier   |   customers |     revenue |   revenue_per_customer |      aov |   margin_pct |
|:---------------|------------:|------------:|-----------------------:|---------:|-------------:|
| Gold           |        3391 | 7.80576e+08 |               230191   | 35126.3  |         6.46 |
| Silver         |        6754 | 6.44793e+08 |                95468.3 | 21357.8  |         8.93 |
| Platinum       |        1135 | 5.054e+08   |               445287   | 48151.7  |         6.25 |
| Bronze         |       10928 | 2.15903e+08 |                19756.9 |  8829.67 |        15.16 |


### Result 8: `WITH cb AS (`

*10 rows returned*

| acquisition_channel      |   customers_acquired |   customers_who_bought |   activation_rate_pct |   avg_orders |   repeat_rate_pct |     revenue |   revenue_per_buyer |
|:-------------------------|---------------------:|-----------------------:|----------------------:|-------------:|------------------:|------------:|--------------------:|
| Organic Search           |                 5505 |                   4943 |                 89.79 |         4.06 |             73.86 | 4.98458e+08 |            100841   |
| Direct/App               |                 3022 |                   2766 |                 91.53 |         4.55 |             76.7  | 3.06222e+08 |            110709   |
| Paid Search              |                 3473 |                   3067 |                 88.31 |         3.77 |             70.43 | 2.81144e+08 |             91667.3 |
| Social Media - Instagram |                 3013 |                   2618 |                 86.89 |         3.5  |             65.72 | 2.2569e+08  |             86207.2 |
| Email Marketing          |                 2014 |                   1833 |                 91.01 |         4.19 |             74.23 | 1.87668e+08 |            102383   |
| Social Media - Facebook  |                 2179 |                   1871 |                 85.87 |         3.56 |             65.95 | 1.6665e+08  |             89070   |
| Referral                 |                 1534 |                   1403 |                 91.46 |         4.41 |             75.88 | 1.50373e+08 |            107180   |
| Affiliate                |                 1743 |                   1503 |                 86.23 |         3.64 |             67.87 | 1.34697e+08 |             89618.7 |
| Influencer Marketing     |                 1499 |                   1312 |                 87.53 |         3.75 |             69.38 | 1.19783e+08 |             91297.8 |
| SMS Marketing            |                 1018 |                    892 |                 87.62 |         3.44 |             66.8  | 7.5988e+07  |             85188.3 |


### Result 9: `WITH first_order AS (`

*36 rows returned*

| cohort_month   |   cohort_size |   m0_pct |   m1_pct |   m3_pct |   m6_pct |   m9_pct |   m12_pct |
|:---------------|--------------:|---------:|---------:|---------:|---------:|---------:|----------:|
| 2023-01        |           226 |      100 |     57.1 |     23   |     10.2 |      5.8 |       2.7 |
| 2023-02        |           421 |      100 |     45.1 |     25.7 |     12.4 |      9.5 |       4.3 |
| 2023-03        |           661 |      100 |     39.6 |     21.8 |     12.3 |      8.8 |       5.4 |
| 2023-04        |           752 |      100 |     37.5 |     20.5 |     12.8 |      7.4 |       4.7 |
| 2023-05        |           782 |      100 |     36.8 |     22.8 |     15.6 |      7.8 |       4.6 |
| 2023-06        |           864 |      100 |     34.8 |     23   |     15.6 |     10.2 |       7.2 |
| 2023-07        |           844 |      100 |     31.8 |     24.6 |     11.3 |      7.7 |       4.1 |
| 2023-08        |           778 |      100 |     28.5 |     28.3 |     14.9 |      8.2 |       5.8 |
| 2023-09        |           603 |      100 |     26   |     21.6 |     13.6 |      8.3 |       5.5 |
| 2023-10        |           652 |      100 |     31.4 |     19.6 |     15.2 |      8.6 |       9.5 |
| 2023-11        |           741 |      100 |     26.6 |     15.7 |     13   |      9.9 |       8.8 |
| 2023-12        |           580 |      100 |     25.2 |     18.6 |      9.7 |      6.4 |       8.1 |
| 2024-01        |           468 |      100 |     23.5 |     18.6 |     12.2 |      9.6 |       9.4 |
| 2024-02        |           439 |      100 |     30.3 |     17.3 |     10.5 |     10   |       5.2 |
| 2024-03        |           509 |      100 |     25.3 |     16.5 |     11.8 |     10   |       4.5 |
| 2024-04        |           469 |      100 |     26.7 |     16   |     15.8 |      9.2 |       6.6 |
| 2024-05        |           437 |      100 |     26.8 |     18.3 |     15.3 |      6.9 |       5.5 |
| 2024-06        |           455 |      100 |     24   |     20.2 |     13.2 |     12.3 |       7   |
| 2024-07        |           439 |      100 |     28.7 |     25.5 |     14.1 |      8.9 |       5.9 |
| 2024-08        |           478 |      100 |     25.3 |     23.6 |     11.3 |      7.9 |       7.7 |
| 2024-09        |           468 |      100 |     29.3 |     18.6 |     17.5 |     12   |       9.4 |
| 2024-10        |           596 |      100 |     34.7 |     19.6 |     15.6 |     10.2 |      11.2 |
| 2024-11        |           677 |      100 |     31.6 |     19.6 |     14.2 |     10.5 |       9.3 |
| 2024-12        |           596 |      100 |     30   |     24.2 |     14.9 |     10.7 |       9.7 |
| 2025-01        |           575 |      100 |     30.3 |     22.6 |     14.4 |     15.3 |     nan   |
| 2025-02        |           477 |      100 |     29.8 |     23.3 |     19.7 |     15.3 |     nan   |
| 2025-03        |           591 |      100 |     30.1 |     24   |     16.6 |     14.6 |     nan   |
| 2025-04        |           542 |      100 |     29.5 |     22.9 |     27.7 |    nan   |     nan   |
| 2025-05        |           617 |      100 |     31.1 |     27.4 |     23.3 |    nan   |     nan   |
| 2025-06        |           599 |      100 |     31.7 |     27.5 |     23.9 |    nan   |     nan   |
| 2025-07        |           562 |      100 |     36.1 |     36.3 |    nan   |    nan   |     nan   |
| 2025-08        |           615 |      100 |     40.3 |     35   |    nan   |    nan   |     nan   |
| 2025-09        |           628 |      100 |     49.5 |     36.1 |    nan   |    nan   |     nan   |
| 2025-10        |          1052 |      100 |     56.4 |    nan   |    nan   |    nan   |     nan   |
| 2025-11        |          1009 |      100 |     56.9 |    nan   |    nan   |    nan   |     nan   |
| 2025-12        |          1006 |      100 |    nan   |    nan   |    nan   |    nan   |     nan   |


### Result 10: `WITH cb AS (`

*10 rows returned*

| orders_placed   |   customers |   pct_customers |   cumulative_pct |
|:----------------|------------:|----------------:|-----------------:|
| 10+             |        1337 |            6.02 |             6.02 |
| 9               |         636 |            2.86 |             8.88 |
| 8               |         927 |            4.17 |            13.06 |
| 7               |        1280 |            5.76 |            18.82 |
| 6               |         950 |            4.28 |            23.1  |
| 5               |        1635 |            7.36 |            30.46 |
| 4               |        2688 |           12.1  |            42.57 |
| 3               |        3813 |           17.17 |            59.74 |
| 2               |        4543 |           20.46 |            80.19 |
| 1               |        4399 |           19.81 |           100    |


### Result 11: `SELECT customer_status,`

*3 rows returned*

| customer_status   |   customers |   orders |   historical_revenue |   pct_of_revenue |   revenue_per_customer |   avg_days_since_order |
|:------------------|------------:|---------:|---------------------:|-----------------:|-----------------------:|-----------------------:|
| Churned           |       13105 |    48785 |          1.19183e+09 |            55.52 |                90944.8 |                    672 |
| Active            |        7033 |    30685 |          7.66929e+08 |            35.73 |               109047   |                    153 |
| At Risk           |        2070 |     7890 |          1.87912e+08 |             8.75 |                90778.9 |                    284 |


### Result 12: `WITH seq AS (`

*5 rows returned*

| gap_band       |   order_pairs |   pct |   avg_gap_days |
|:---------------|--------------:|------:|---------------:|
| 1. <= 7 days   |         16628 | 25.52 |            3.3 |
| 2. 8-30 days   |         20724 | 31.81 |           17   |
| 3. 31-60 days  |         10994 | 16.87 |           43.5 |
| 4. 61-120 days |          8915 | 13.68 |           85.5 |
| 5. 120+ days   |          7891 | 12.11 |          223.8 |


### Result 13: `SELECT customer_segment,`

*88 rows returned*

| customer_segment   | category               |          revenue |   pct_of_segment_revenue |      aov |
|:-------------------|:-----------------------|-----------------:|-------------------------:|---------:|
| Budget             | Electronics            |      1.50357e+08 |                    49.93 | 51775.8  |
| Budget             | Appliances             |      4.73449e+07 |                    15.72 | 25843.3  |
| Budget             | Furniture              |      2.01612e+07 |                     6.7  | 44213.2  |
| Budget             | Home & Kitchen         |      1.96065e+07 |                     6.51 |  6509.46 |
| Budget             | Fashion                |      1.73533e+07 |                     5.76 |  3731.08 |
| Budget             | Footwear               |      9.99159e+06 |                     3.32 |  6107.33 |
| Budget             | Bags                   |      7.4755e+06  |                     2.48 |  4623.07 |
| Budget             | Health & Wellness      |      3.92526e+06 |                     1.3  |  2080.16 |
| Budget             | Toys                   |      3.12763e+06 |                     1.04 |  2096.27 |
| Budget             | Sports                 |      3.06469e+06 |                     1.02 |  4428.75 |
| Budget             | Beauty                 |      3.0616e+06  |                     1.02 |  2447.32 |
| Budget             | Watches                |      2.7319e+06  |                     0.91 | 10348.1  |
| Budget             | Books                  |      2.45546e+06 |                     0.82 |  1604.88 |
| Budget             | Grocery                |      2.19912e+06 |                     0.73 |  1243.14 |
| Budget             | Musical Instruments    |      2.1796e+06  |                     0.72 | 10044.3  |
| Budget             | Personal Care          |      1.72396e+06 |                     0.57 |  1583.06 |
| Budget             | Mobile Accessories     |      1.35609e+06 |                     0.45 |  1344    |
| Budget             | Stationery             | 977555           |                     0.32 |   845.64 |
| Budget             | Pet Supplies           | 807774           |                     0.27 |  2665.92 |
| Budget             | Baby Care              | 800108           |                     0.27 |  1847.82 |
| Budget             | Automotive Accessories | 224598           |                     0.07 |  1268.92 |
| Budget             | Office Supplies        | 201554           |                     0.07 |  1028.34 |
| New                | Electronics            |      3.35674e+07 |                    53.14 | 53707.8  |
| New                | Appliances             |      9.45858e+06 |                    14.97 | 25563.7  |
| New                | Home & Kitchen         |      4.3225e+06  |                     6.84 |  6949.35 |
| New                | Fashion                |      3.59559e+06 |                     5.69 |  3665.23 |
| New                | Furniture              |      2.8183e+06  |                     4.46 | 36601.3  |
| New                | Footwear               |      2.07678e+06 |                     3.29 |  5866.61 |
| New                | Bags                   |      1.34069e+06 |                     2.12 |  4229.32 |
| New                | Health & Wellness      | 808649           |                     1.28 |  2001.61 |
| New                | Sports                 | 688968           |                     1.09 |  4655.19 |
| New                | Musical Instruments    | 640588           |                     1.01 | 14897.4  |
| New                | Toys                   | 574425           |                     0.91 |  2044.22 |
| New                | Beauty                 | 529207           |                     0.84 |  2321.08 |
| New                | Books                  | 527017           |                     0.83 |  1559.22 |
| New                | Watches                | 518771           |                     0.82 |  9432.2  |
| New                | Grocery                | 498973           |                     0.79 |  1263.22 |
| New                | Personal Care          | 354910           |                     0.56 |  1510.26 |
| New                | Mobile Accessories     | 283781           |                     0.45 |  1344.93 |
| New                | Stationery             | 178098           |                     0.28 |   739    |
| New                | Pet Supplies           | 175771           |                     0.28 |  2704.16 |
| New                | Baby Care              | 146440           |                     0.23 |  1807.9  |
| New                | Automotive Accessories |  35133.9         |                     0.06 |  1097.94 |
| New                | Office Supplies        |  31515.3         |                     0.05 |   808.09 |
| Premium            | Electronics            |      3.69807e+08 |                    50.1  | 53923.5  |
| Premium            | Appliances             |      1.23184e+08 |                    16.69 | 28567.8  |
| Premium            | Home & Kitchen         |      4.70885e+07 |                     6.38 |  6899.41 |
| Premium            | Furniture              |      4.42817e+07 |                     6    | 42092.9  |
| Premium            | Fashion                |      4.15008e+07 |                     5.62 |  3988.16 |
| Premium            | Footwear               |      2.43325e+07 |                     3.3  |  6268.04 |
| Premium            | Bags                   |      1.65258e+07 |                     2.24 |  4527.61 |
| Premium            | Health & Wellness      |      9.89963e+06 |                     1.34 |  2243.29 |
| Premium            | Sports                 |      7.69948e+06 |                     1.04 |  4564.01 |
| Premium            | Beauty                 |      7.15466e+06 |                     0.97 |  2413.04 |
| Premium            | Toys                   |      7.15383e+06 |                     0.97 |  2036.97 |
| Premium            | Watches                |      6.62594e+06 |                     0.9  | 10773.9  |
| Premium            | Musical Instruments    |      6.22195e+06 |                     0.84 | 12345.1  |
| Premium            | Books                  |      5.85612e+06 |                     0.79 |  1605.74 |
| Premium            | Grocery                |      5.52029e+06 |                     0.75 |  1268.16 |
| Premium            | Personal Care          |      4.29953e+06 |                     0.58 |  1625.53 |
| Premium            | Mobile Accessories     |      3.17747e+06 |                     0.43 |  1342.97 |
| Premium            | Stationery             |      2.47334e+06 |                     0.34 |   847.91 |
| Premium            | Pet Supplies           |      2.18092e+06 |                     0.3  |  2979.39 |
| Premium            | Baby Care              |      2.14753e+06 |                     0.29 |  2093.11 |
| Premium            | Automotive Accessories | 576813           |                     0.08 |  1319.94 |
| Premium            | Office Supplies        | 491415           |                     0.07 |  1219.39 |
| Regular            | Electronics            |      5.2043e+08  |                    49.84 | 53279.1  |
| Regular            | Appliances             |      1.73755e+08 |                    16.64 | 27567.1  |
| Regular            | Home & Kitchen         |      6.67462e+07 |                     6.39 |  6617.7  |
| Regular            | Furniture              |      6.27801e+07 |                     6.01 | 41714.3  |
| Regular            | Fashion                |      5.94476e+07 |                     5.69 |  3853.48 |
| Regular            | Footwear               |      3.58344e+07 |                     3.43 |  6229.9  |
| Regular            | Bags                   |      2.36341e+07 |                     2.26 |  4590.92 |
| Regular            | Health & Wellness      |      1.34523e+07 |                     1.29 |  2157.2  |
| Regular            | Sports                 |      1.15933e+07 |                     1.11 |  4860.91 |
| Regular            | Toys                   |      1.05853e+07 |                     1.01 |  2092.37 |
| Regular            | Beauty                 |      9.69286e+06 |                     0.93 |  2364.11 |
| Regular            | Musical Instruments    |      9.16701e+06 |                     0.88 | 12337.8  |
| Regular            | Watches                |      8.95552e+06 |                     0.86 |  9692.12 |
| Regular            | Books                  |      8.79693e+06 |                     0.84 |  1624.55 |
| Regular            | Grocery                |      7.85086e+06 |                     0.75 |  1259.56 |
| Regular            | Personal Care          |      6.33734e+06 |                     0.61 |  1634.18 |
| Regular            | Mobile Accessories     |      4.62363e+06 |                     0.44 |  1343.3  |
| Regular            | Stationery             |      3.43782e+06 |                     0.33 |   845.09 |
| Regular            | Baby Care              |      2.87904e+06 |                     0.28 |  1934.84 |
| Regular            | Pet Supplies           |      2.8419e+06  |                     0.27 |  2675.99 |
| Regular            | Automotive Accessories | 680678           |                     0.07 |  1204.74 |
| Regular            | Office Supplies        | 652278           |                     0.06 |  1085.32 |

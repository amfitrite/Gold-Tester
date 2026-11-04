# London/NY VWAP Trend Pullback (`london_ny_vwap_pullback`)

Strategi intraday XAUUSD yang menggabungkan **session VWAP**, **bias EMA-200**, dan
**rejection candle** di jam London/New York. Targetnya: win rate tinggi, equity
growth stabil, dan drawdown kecil.

> **Timeframe: M5 saja.** Logika yang sama di M1 menghasilkan expectancy negatif
> karena noise dan biaya transaksi. Gunakan M5.

---

## 1. Konsep

VWAP harian adalah harga rata-rata pasar untuk hari berjalan. Saat harga sedang
trend (di atas/bawah EMA-200) lalu pullback ke VWAP dan ditolak dengan candle
yang kembali searah trend, peluang lanjutan trend lebih besar daripada melawan
trend. Strategi ini hanya mengambil setup tersebut pada jam likuiditas tinggi.

- **Bias**: close di atas EMA-200 = hanya long; close di bawah EMA-200 = hanya short.
- **Sesi**: jam 07:00-17:59 UTC (London + New York overlap).
- **VWAP**: di-reset setiap 00:00 UTC, memakai typical price `(H+L+C)/3` dan volume.
- **Entry**: next bar open setelah candle rejection close.
- **Exit**: SL/TP masing-masing `1.25 x ATR(14)`, atau time stop 24 bar M5 (2 jam).
- **Posisi**: maksimal satu posisi pada satu waktu.

## 2. Aturan Entry

### Long

1. `low <= session VWAP`
2. `close > session VWAP`
3. `close > open` (candle bullish)
4. `close > EMA-200`
5. Jam candle 07:00-17:59 UTC

### Short

1. `high >= session VWAP`
2. `close < session VWAP`
3. `close < open` (candle bearish)
4. `close < EMA-200`
5. Jam candle 07:00-17:59 UTC

Entry dilakukan di **open bar berikutnya**. SL/TP dihitung dari entry yang sudah
memasukkan biaya spread/slippage.

## 3. Exit & Money Management

| Komponen | Nilai |
|---|---|
| Stop loss | `1.25 x ATR(14)` |
| Take profit | `1.25 x ATR(14)` (RR 1:1) |
| Time stop | 24 bar M5 (2 jam) |
| Biaya riset | $0.12 per sisi ($0.24 round-turn) |
| Risiko rekomendasi | 1.0-1.5% per trade |
| Posisi | 1 posisi pada satu waktu |

RR dikunci di 1:1 karena target inilah yang menghasilkan win rate dan equity
curve paling halus. UI/CLI akan otomatis memakai RR 1.0 untuk strategi ini.

## 4. Hasil Backtest Resmi

**Data:** XAUUSD M5, 6 Oktober 2026 00:00 - 4 November 2026 17:55 UTC (6.000 bar).
**Modal:** $10.000. **Risiko:** 1.5% per trade. **Biaya:** $0.12 per sisi.

| Metrik | Nilai |
|---|---:|
| Total trade | 75 |
| Win / Loss | 51 / 24 |
| Win rate | **68.0%** |
| Profit factor | 1.96 |
| Net profit | **+$4.308,22** |
| Growth | **+43.08%** |
| Max drawdown | **$559,47 (4.54%)** |
| Avg win | $172,11 |
| Avg loss | $186,22 |
| Total R | +24.43R |
| Expectancy | +0.326R per trade |
| Max drawdown (R) | 3.07R |
| Saldo akhir | **$14.308,22** |

Laporan lengkap: [report_london_ny_vwap_pullback_latest.html](report_london_ny_vwap_pullback_latest.html)

## 5. Tabel Risiko

Simulasi compounding dengan urutan trade yang sama:

| Risiko/trade | Saldo akhir | Growth | Max DD |
|---:|---:|---:|---:|
| 0.5% | $11.288,86 | +12.89% | 1.53% |
| 1.0% | $12.720,71 | +27.21% | 3.04% |
| **1.5%** | **$14.308,22** | **+43.08%** | **4.54%** |
| 2.0% | $16.064,81 | +60.65% | 6.02% |
| 2.5% | $18.004,55 | +80.05% | 7.48% |
| 3.0% | $20.142,25 | +101.42% | 8.93% |

Rekomendasi: **1.5%** untuk keseimbangan growth/DD. Gunakan **1.0%** jika ingin
DD di bawah 3.5%.

## 6. Validasi

- **Train/test split (70/30):** train 52 trade, WR 67.3%, +0.308R/trade; test 23
  trade, WR **69.6%**, +0.367R/trade. Edge tidak hilang di data test.
- **Konsistensi mingguan:** 5 dari 5 minggu positif.
  - 5-11 Okt: 14 trade, WR 71.4%, +5.66R
  - 12-18 Okt: 20 trade, WR 70.0%, +7.53R
  - 19-25 Okt: 14 trade, WR 57.1%, +0.88R
  - 26 Okt-1 Nov: 19 trade, WR 63.2%, +4.56R
  - 2-8 Nov: 8 trade, WR 87.5%, +5.79R
- **Long vs short:** long 44 trade, WR 65.9%, +12.11R; short 31 trade, WR 71.0%,
  +12.32R. Kedua arah berkontribusi.
- **Exit:** sekitar 50 TP, 24 SL, 1 time exit.
- **Max consecutive losses:** 3.
- **Tanpa look-ahead:** sinyal memakai candle yang sudah close, entry di open bar
  berikutnya; tidak ada data masa depan.

## 7. Catatan Eksekusi

1. **Timeframe M5.** Jangan pindah ke M1 hanya karena data M1 tersedia.
2. **Zona waktu MT5.** Sesi 07:00-17:59 UTC. Jika server MT5 memakai GMT+2/GMT+3,
   konversikan jamnya; jangan hardcode 07:00 di server time.
3. **VWAP reset 00:00 UTC**, bukan 00:00 server time.
4. **Spread/slippage.** Backtest memakai $0.12 per sisi. Broker dengan spread lebih
   lebar akan menurunkan WR dan expectancy; uji ulang dengan biaya broker Anda.
5. **Satu posisi.** Jangan menambah posisi saat trade sebelumnya masih terbuka.
6. **Berita besar.** Strategi tidak memiliki filter berita. Pertimbangkan menghindari
   entry beberapa menit sebelum rilis NFP/FOMC/CPI.
7. **Bukan jaminan.** Hasil masa lalu tidak menjamin hasil masa depan. Risiko 1.5%
   per trade berarti drawdown 3-5% adalah hal normal.

## 8. Cara Menjalankan

Dari folder `engine`:

```powershell
python backtest_runner.py `
  --file ..\..\xauusd_m5.csv `
  --strategy london_ny_vwap_pullback `
  --capital 10000 `
  --risk-pct 1.5 `
  --rr 1.0 `
  --timeframe M5 `
  --trend ema `
  --report-out ..\reports\report_london_ny_vwap_pullback_latest.html `
  --json-out ..\reports\result_london_ny_vwap_pullback_latest.json `
  --set-out ..\reports\strategy_london_ny_vwap_pullback_latest.set
```

File pendukung:

- [Laporan HTML interaktif](report_london_ny_vwap_pullback_latest.html)
- [Hasil JSON](result_london_ny_vwap_pullback_latest.json)
- [MT5 .set](strategy_london_ny_vwap_pullback_latest.set)

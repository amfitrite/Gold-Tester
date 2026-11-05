# Volume-Profile Failed Auction (`volume_profile_failed_auction`)

Strategi intraday XAUUSD M5 yang memanfaatkan **failed auction** di bawah
**value area hari sebelumnya**. Targetnya bukan mengejar trend besar, tetapi
mengambil snap-back berprobabilitas tinggi ke arah POC dengan target kecil
(0.5R). Ini edge yang berbeda dari BB, VWAP, ICT, ORB, atau S/R: level datang
dari distribusi volume harga hari sebelumnya, bukan dari indikator harga.

> **Timeframe: M5 saja.** Sesi sinyal 09:00-11:59 UTC. Rekomendasi risiko
> **1.0% per trade**; 1.25% hanya untuk toleransi drawdown yang lebih tinggi.

---

## 1. Konsep

Volume profile hari sebelumnya membagi harga menjadi bin $5 dan menghitung
volume yang diperdagangkan di setiap bin. Tiga level penting:

- **POC** — bin dengan volume terbesar, harga “fair value” hari itu.
- **VAL** — batas bawah value area 80%.
- **VAH** — batas atas value area 80%.

Di sesi London pagi, harga kadang turun di bawah VAL tetapi gagal bertahan di
luar value area: candle ditutup kembali di atas VAL. Jika:

1. close bar sebelumnya sudah berada di dalam `[VAL, VAH]`,
2. POC masih di atas close saat ini,
3. candle rejection bullish,

maka breakdown tersebut dianggap **failed auction**. Harga biasanya ditarik
kembali ke arah POC. Strategi masuk long di open bar berikutnya dengan target
kecil 0.5R, karena edge-nya adalah frekuensi snap-back, bukan besar pergerakan.

## 2. Aturan Entry

### Long (hanya long)

1. Profil volume dari **hari perdagangan sebelumnya** (hari Minggu diabaikan).
2. Candle sinyal berada di jam **09:00-11:59 UTC**.
3. `VAL <= close bar sebelumnya <= VAH`.
4. `low < VAL` dan `close > VAL` — gagal breakdown.
5. `close > open` — candle bullish/rejection.
6. `POC > close` — masih ada ruang menuju fair value.
7. Entry di **open bar berikutnya**, dengan biaya half-spread $0.12.

Tidak ada sinyal short. Posisi maksimal satu pada satu waktu.

## 3. Exit & Money Management

| Komponen | Nilai |
|---|---|
| Stop loss | `low candle sinyal - 0.50 x ATR(14)` |
| Take profit | `entry + 0.50 x risk` (0.5R) |
| Time stop | 48 bar M5 (4 jam) |
| Biaya riset | $0.12 per sisi ($0.24 round-turn) |
| Risiko rekomendasi | **1.0%** per trade (maksimum 1.25%) |
| Posisi | 1 posisi pada satu waktu |
| Same-bar SL/TP | Dianggap **SL lebih dulu** (konservatif) |

RR dikunci di 0.5 karena target inilah yang menghasilkan win rate dan equity
curve paling halus. UI/CLI otomatis memakai RR 0.5 untuk strategi ini.

## 4. Hasil Backtest Resmi

**Data:** XAUUSD M5, 5 November 2025 - 4 November 2026 (12 bulan, 70.891 bar
mentah; hari Minggu diabaikan oleh strategi).
**Modal:** $10.000. **Risiko utama:** 1.0% per trade. **Biaya:** $0.12 per sisi.

| Metrik | Nilai |
|---|---:|
| Total trade | 54 |
| Win / Loss | 46 / 8 |
| Win rate | **85.19%** |
| Profit factor | 2.67 |
| Net profit | **+$1.467,48** |
| Growth | **+14.67%** |
| Max drawdown | **$217,55 (2.03%)** |
| Avg win | $51,04 |
| Avg loss | $110,02 |
| Total R | +13,79R |
| Expectancy | +0.255R per trade |
| Max consecutive losses | 2 |
| Saldo akhir | **$11.467,48** |

Exit pada sampel ini: **46 take-profit, 8 stop-loss**; tidak ada trade yang
murni keluar karena time stop. Time stop tetap dipertahankan sebagai pengaman.

### Tabel risiko

Simulasi compounding dengan urutan trade resmi:

| Risiko/trade | Saldo akhir | Growth | Max DD historis | MC p95 DD | MC p99 DD |
|---:|---:|---:|---:|---:|---:|
| 0.5% | $10.711,15 | +7.11% | 1.02% | — | — |
| **1.0%** | **$11.467,48** | **+14.67%** | **2.03%** | **4.01%** | **5.09%** |
| 1.25% | $11.863,35 | +18.63% | 2.53% | 4.99% | 6.29% |
| 1.5% | $12.271,43 | +22.71% | 3.04% | 5.96% | 7.56% |
| 2.0% | $13.125,54 | +31.26% | 4.04% | 7.90% | 10.02% |
| 2.5% | $14.032,45 | +40.32% | 5.04% | — | — |
| 3.0% | $14.994,91 | +49.95% | 6.03% | — | — |

Monte Carlo: 50.000 bootstrap resample dari 54 nilai R, compounding, seed tetap.
Bootstrap mengasumsikan trade saling independen; loss yang mengelompok di pasar
nyata bisa memberi DD lebih besar. Pada risiko 1.0%, median growth 14.7%
(p05 7.9%, p95 21.8%). Pada 1.25%, median 18.7% (p05 9.9%, p95 27.9%).
**Rekomendasi 1.0%** karena MC p95 DD masih di bawah 5%; 1.25% sudah tepat di
batas (4.99%) dan p99-nya 6.29%.

## 5. Validasi

### Train / test split

Split tanggal **5 Agustus 2026**: 9 bulan pertama sebagai train, 3 bulan terakhir
sebagai uji holdout-style. Ini bukan klaim bahwa default sama sekali tidak
melihat data test; parameter dipilih dalam riset 12 bulan, lalu stabilitasnya
diperiksa pada split ini.

| Segmen | Trade | Win / Loss | Win rate | Avg R | Total R |
|---|---:|---:|---:|---:|---:|
| Train (2025-11-05 .. 2026-08-04) | 35 | 30 / 5 | 85.71% | +0.265R | +9.26R |
| Test (2026-08-05 .. 2026-11-04) | 19 | 16 / 3 | **84.21%** | +0.238R | +4.53R |

Edge tidak hilang di data test, meskipun jumlah trade test kecil.

### Cost stress (risiko 1.25%)

| Half-spread per sisi | Trade | Win rate | PF | Growth | Max DD |
|---:|---:|---:|---:|---:|---:|
| $0.12 | 54 | 85.19% | 2.66 | +18.63% | 2.53% |
| $0.20 | 54 | 85.19% | 2.55 | +17.49% | 2.57% |
| $0.30 | 53 | 81.13% | 1.81 | +11.29% | 3.38% |
| $0.40 | 53 | 81.13% | 1.72 | +10.10% | 3.47% |

Pada spread $0.40 per sisi strategi masih positif, tetapi expectancy turun
signifikan. Broker dengan spread lebih lebar dari $0.30-$0.40 perlu uji ulang.

### Konsistensi bulanan (risiko 1.25%)

| Bulan | Trade | W / L | Total R | Avg R | PnL | Saldo akhir |
|---|---:|---:|---:|---:|---:|---:|
| 2025-11 | 3 | 2 / 1 | -0.05R | -0.017R | -$7,52 | $9.992,48 |
| 2025-12 | 5 | 5 / 0 | +2.33R | +0.466R | +$293,98 | $10.286,46 |
| 2026-01 | 4 | 3 / 1 | +0.39R | +0.097R | +$49,83 | $10.336,28 |
| 2026-02 | 2 | 1 / 1 | -0.54R | -0.270R | -$69,66 | $10.266,62 |
| 2026-03 | 3 | 3 / 0 | +1.46R | +0.487R | +$188,45 | $10.455,07 |
| 2026-04 | 3 | 3 / 0 | +1.45R | +0.483R | +$190,67 | $10.645,73 |
| 2026-05 | 7 | 5 / 2 | +0.35R | +0.050R | +$43,47 | $10.689,21 |
| 2026-06 | 7 | 7 / 0 | +3.39R | +0.484R | +$460,16 | $11.149,36 |
| 2026-07 | 1 | 1 / 0 | +0.48R | +0.480R | +$67,15 | $11.216,52 |
| 2026-08 | 7 | 7 / 0 | +3.32R | +0.474R | +$472,71 | $11.689,23 |
| 2026-09 | 9 | 7 / 2 | +1.28R | +0.142R | +$186,51 | $11.875,74 |
| 2026-10 | 3 | 2 / 1 | -0.07R | -0.023R | -$12,40 | $11.863,35 |

9 dari 12 bulan positif. Bulan negatif terbesar -0.54R, bukan gap besar.

## 6. Keterbatasan yang Harus Dibaca

1. **Sampel kecil.** Hanya 54 trade dalam 12 bulan, sekitar 4-5 trade/bulan.
   Confidence interval 95% untuk win rate 85.19% dengan n=54 kira-kira
   73%-92%; angka headline bisa terlihat lebih mulus dari realitas.
2. **Long-only dan bergantung regime.** Semua 54 trade long. Strategi tidak
   punya sisi short; pasar bearish yang tajam bisa menghilangkan frekuensi
   failed breakdown yang valid.
3. **30 hari terakhir lemah.** Hanya 3 trade, 2 win/1 loss, -0.07R. Dataset
   one-month (`xauusd_m5.csv`) juga hanya menghasilkan 3 trade, WR 66.67%,
   PF 0.92, growth -0.10%, DD 1.28%. Jangan menyimpulkan edge hilang dari 3
   trade, tetapi juga jangan menganggap hasil 12 bulan berulang persis.
4. **Biaya dan eksekusi.** Backtest memakai $0.12 per sisi. Spread broker yang
   lebih lebar, slippage, requote, atau entry yang tidak terisi di open
   berikutnya akan menurunkan PF.
5. **Volume profile bukan volume institusional.** Data volume dari broker
   (tick volume) berbeda antar broker. Profil $5 dan value area 80% dipilih
   untuk XAUUSD; jangan pindah ke simbol/timeframe lain tanpa uji ulang.
6. **Varian B tidak dipakai.** Konfigurasi alternatif tanpa filter `inside`,
   buffer 0.75 ATR, dan target 0.4R menghasilkan 92 trade, WR 84.8%, PF 2.10,
   tetapi MC p95 DD 6.19% pada risiko 1.25%. Growth lebih tinggi tidak
   sebanding dengan risiko drawdown yang melewati target.
7. **Bukan jaminan.** Semua hasil adalah hindsight pada data historis.

## 7. Catatan Eksekusi

1. **M5 saja.** Sinyal memakai ATR(14) dan profil hari sebelumnya; M1 terlalu
   bising untuk konfigurasi ini.
2. **UTC.** Sesi 09:00-11:59 UTC. Jika server MT5 GMT+2/GMT+3, konversikan;
   jangan hardcode 09:00 di server time.
3. **Profil hari sebelumnya.** Bangun setelah hari sebelumnya selesai; jangan
   memakai bar hari berjalan. Hari Minggu diabaikan.
4. **Volume.** Gunakan volume bar yang konsisten. Jika volume kosong, engine
   memakai 1.0 per bar; itu darurat, bukan pengganti volume asli.
5. **Satu posisi.** Jangan menambah posisi saat trade sebelumnya masih terbuka.
6. **Berita besar.** Tidak ada filter berita. Hindari entry beberapa menit
   sebelum NFP/FOMC/CPI atau saat spread melebar.
7. **Risiko.** Mulai 1.0%; jangan langsung 1.5% hanya karena DD historis 3%.
   MC p95 DD di 1.5% sudah 5.96%.

## 8. Cara Menjalankan

Dari folder `dukascopy-downloader`:

```powershell
python engine\backtest_runner.py `
  --file D:\CSV\xauusd_m5_12m.csv `
  --strategy volume_profile_failed_auction `
  --capital 10000 `
  --risk-pct 1.0 `
  --rr 0.5 `
  --timeframe M5 `
  --trend none `
  --report-out reports\report_volume_profile_failed_auction_risk10.html `
  --json-out reports\result_volume_profile_failed_auction_risk10.json `
  --set-out reports\volume_profile_failed_auction_risk10.set
```

File pendukung:

- [Laporan HTML risiko 1.0%](report_volume_profile_failed_auction_risk10.html)
- [Hasil JSON risiko 1.0%](result_volume_profile_failed_auction_risk10.json)
- [MT5 .set risiko 1.0%](volume_profile_failed_auction_risk10.set)
- [Laporan HTML risiko 1.25%](report_volume_profile_failed_auction_risk125.html)
- [Laporan HTML risiko 1.5%](report_volume_profile_failed_auction_risk15.html)
- [Laporan one-month holdout](report_volume_profile_failed_auction_1m_risk125.html)
- [Hasil one-month JSON](result_volume_profile_failed_auction_1m_risk125.json)

Blueprint MQL5 lengkap ada di field `mql5_blueprint` pada file JSON hasil
backtest; parameter `.set` sudah memakai RR 0.50 dan risiko yang dipilih.

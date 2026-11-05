# Perbandingan 3 Kandidat Strategi XAUUSD

Tiga kandidat baru diuji dengan **engine resmi aplikasi** (`backtest_runner.py`),
bukan hanya simulasi research. Semua memakai:

- XAUUSD M5 12 bulan: 5 November 2025 - 4 November 2026 (70.891 bar).
- Entry di **open bar berikutnya** setelah sinyal close.
- Biaya **$0.12 per sisi** ($0.24 round-turn).
- Same-bar SL/TP dianggap **SL lebih dulu** (konservatif).
- Modal $10.000, compounding per trade.
- Time stop sesuai aturan masing-masing strategi.

Tujuannya: **WR > 75%, max DD < 5%, dan equity growth yang menarik**. Hanya
kandidat yang lolos yang dipertahankan di registry produksi.

## Ringkasan Hasil

| Kandidat | Trade | WR | PF | Growth | Max DD | Putusan |
|---|---:|---:|---:|---:|---:|---|
| **Volume-Profile Failed Auction** (risiko 1.0%) | 54 | **85.19%** | **2.67** | **+14.67%** | **2.03%** | **LOLOS** |
| Volume-Profile Failed Auction (risiko 1.25%) | 54 | 85.19% | 2.66 | +18.63% | 2.53% | Referensi |
| Round-Number Liquidity Sweep (risiko 1.0%) | 2.617 | 78.68% | 0.94 | -30.17% | 47.12% | **GAGAL** |
| XAU/XAG Lead-Lag (risiko 1.0%) | 43 | 74.42% | 0.91 | -1.02% | 5.71% | **GAGAL** |

Round-number memakai konfigurasi awal (step $25, SL 2 ATR, TP 0.5 ATR).
Lead-lag memakai varian dengan WR tertinggi dari grid research; varian yang
growth-nya lebih tinggi justru turun ke WR sekitar 66%. Tidak ada varian
lead-lag yang memenuhi WR, DD, dan growth sekaligus.

## 1. Volume-Profile Failed Auction — LOLOS

**Edge:** harga gagal bertahan di bawah value area 80% hari sebelumnya, lalu
close kembali di atas VAL pada sesi London pagi. POC yang masih di atas close
menjadi target snap-back.

**Aturan inti:**

- Profil volume $5 dari hari sebelumnya; value area 80%; POC/VAL/VAH.
- Long-only, 09:00-11:59 UTC.
- Syarat: prior close di dalam `[VAL, VAH]`, `low < VAL`, `close > VAL`,
  `close > open`, `POC > close`.
- SL = low sinyal - 0.5 x ATR(14); TP = 0.5R; time stop 48 bar M5.
- Satu posisi pada satu waktu.

**Hasil resmi 12 bulan (risiko 1.0%):** 54 trade, 46W/8L, WR 85.19%, PF 2.67,
growth +14.67%, max DD 2.03%, expectancy +0.255R.

**Kenapa dipertahankan:** satu-satunya kandidat yang memenuhi ketiga kriteria
utama secara konsisten. Pada risiko 1.0%, Monte Carlo p95 drawdown 4.01% dan p99
5.09%; pada 1.25%, p95 4.99% (tepat di batas). Train/test: 85.71% / 84.21%.
Cost stress sampai $0.40 per sisi masih positif.

**Peringatan:** sampel hanya 54 trade (4-5/bulan), long-only, dan 30 hari
terakhir hanya 3 trade dengan -0.07R. Baca [dokumen lengkap](STRATEGI_VOLUME_PROFILE_FAILED_AUCTION.md)
sebelum memakai uang riil.

## 2. Round-Number Liquidity Sweep — GAGAL

**Edge yang diuji:** sweep level bulat $25, close kembali di dalam level, lalu
trade reversal dengan SL 2.0 x ATR dan TP 0.5 x ATR. Sesi 07:00-17:59 UTC.

**Hasil resmi 12 bulan (risiko 1.0%):** 2.617 trade, 2.059W/558L, WR 78.68%,
PF **0.94**, growth **-30.17%**, max DD **47.12%**.

**Kenapa gagal:** win rate tinggi memang tercapai, tetapi target 0.5 x ATR
terlalu kecil dibanding stop 2.0 x ATR. Setelah biaya, rata-rata R negatif.
Ini contoh bahwa WR > 75% saja tidak cukup; expectancy dan drawdown yang
menentukan. Pada risiko 1.5%, hasilnya lebih buruk: growth -43.04%, DD 62.17%.

**Status:** tidak masuk registry produksi. Laporan resmi tetap disimpan:
[HTML risiko 1.0%](report_round_number_liquidity_sweep_risk10.html),
[JSON risiko 1.0%](result_round_number_liquidity_sweep_risk10.json).

## 3. XAU/XAG Lead-Lag Catch-Up — GAGAL

**Edge yang diuji:** pergerakan silver M5 yang besar dan z-score tinggi,
sementara gold tertinggal dari pergerakan yang diimplikasikan rolling beta
harga. Trade gold untuk mengejar ketertinggalan.

**Hasil resmi 12 bulan (risiko 1.0%):** 43 trade, 32W/11L, WR 74.42%, PF
**0.91**, growth **-1.02%**, max DD **5.71%**.

**Kenapa gagal:** korelasi return XAU/XAG pada M5 hanya sekitar 0.015;
hubungan lead-lag tidak cukup kuat setelah biaya. Di research grid, varian
dengan WR tertinggi hanya memberi growth sekitar +0.44% (PF 1.05), sedangkan
varian dengan growth lebih baik turun ke WR sekitar 66%. Tidak ada varian yang
memenuhi WR > 75%, DD < 5%, dan growth menarik sekaligus. Pada risiko 1.5%,
official result -1.58% dengan DD 8.47%.

**Status:** tidak masuk registry produksi. Laporan resmi:
[HTML risiko 1.0%](report_xau_xag_lead_lag_risk10.html),
[JSON risiko 1.0%](result_xau_xag_lead_lag_risk10.json).

## Keputusan Akhir

Registry produksi hanya berisi **`volume_profile_failed_auction`**. Dua
kandidat gagal tetap disimpan sebagai modul research dan laporan resmi, tetapi
tidak muncul di UI/CLI strategy list. Dengan begitu aplikasi tidak menawarkan
strategi yang sudah terbukti tidak memenuhi target.

**Rekomendasi risiko:** 1.0% per trade. 1.25% masih memberikan historical DD
2.53% dan growth 18.63%, tetapi Monte Carlo p95 DD-nya 4.99% dan p99 6.29%;
1.5% sudah melewati target DD secara robust (p95 5.96%).

**Langkah berikutnya sebelum live:** forward test 3-6 bulan di demo dengan
spread broker sebenarnya, lalu bandingkan WR/PF/DD dengan hasil ini. Jangan
menaikkan risiko sebelum ada bukti out-of-sample dari broker sendiri.

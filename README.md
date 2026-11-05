# 🏆 Gold Tester (Dukascopy Downloader & Multi-Strategy Quantitative Lab)

[![Electron](https://img.shields.io/badge/GUI-Electron_33-blue?logo=electron)](https://www.electronjs.org/)
[![Python](https://img.shields.io/badge/Engine-Python_3.9+-yellow?logo=python)](https://www.python.org/)
[![MetaTrader 5](https://img.shields.io/badge/Bridge-MetaTrader_5-green)](https://www.metatrader5.com/)
[![License: MIT](https://img.shields.io/badge/License-MIT-purple.svg)](https://opensource.org/licenses/MIT)

All-in-One Desktop Trading Suite: Unduh data historis presisi tinggi dari **Dukascopy Swiss (Ticks, LTF, HTF)**, uji strategi kuantitatif institusional/SMC (**ICT IFVG, Liquidity Sweeps, Order Blocks, ORB**) pada akun standar **$10.000**, dan ekspor langsung ke **MetaTrader 5 (Indikator & Expert Advisor MQL5)**.

---

## 🌟 Fitur Utama

### 1. 📥 Dukascopy Historical Data Downloader
* **Semua Timeframe:**
  * **TICKS:** Raw tick-by-tick market execution.
  * **LTF (Low Timeframe):** `s1` (1 detik), `m1` (1 menit), `m5` (5 menit), `m15`, `m30`.
  * **HTF (High Timeframe):** `h1`, `h4`, `d1` (daily), `mn1` (monthly).
* **Multi-Pair & Custom Symbol:** XAUUSD (Gold), Forex Majors, Crypto (BTCUSD, ETHUSD), Indices (US30, NAS100).
* **Format Bersih:** Output CSV presisi dengan timestamp terformat (`YYYY-MM-DD HH:mm:ss`), Open, High, Low, Close, Volume.
* **1-Click Pipeline:** Tombol cepat *"⚡ Uji di Backtester Sekarang"* setelah download selesai.

### 2. 🧪 Sweep Backtester & Strategy Lab ($10.000 Account Simulator)
* **27 Strategi Bawaan Terintegrasi:**
  * `ict_ifvg` (ICT Inversion Fair Value Gap Retest)
  * `liquidity_imbalance` (Liquidity Sweep + Fair Value Gap)
  * `ict_fvg` (ICT Fair Value Gap + Market Structure Shift)
  * `ict_order_block` (ICT Institutional Order Block Mitigation)
  * `smart_money` (SMC CHoCH & Liquidity Purge)
  * `orb` (Opening Range Breakout)
  * `prev_day_breakout` (PDH/PDL Breakout & Retest)
  * `gold_session_sweep` (Rolling Liquidity Sweep + 50% Rejection Retest)
  * `london_ny_vwap_pullback` (London/NY Session VWAP Reclaim + EMA-200, M5)
  * `volume_profile_failed_auction` (Prior-Day Value-Area Failed Breakdown, M5)
  * `adaptive_selective_entry` (GoldWave-inspired Donchian Regime + Momentum Efficiency + ATR + VWAP Rejection + Structural Dynamic TP, M5)
  * `supply_demand`, `order_flow`, `vwap_bounce`, `session_gap`, `bollinger_bands`, dll.
* **Adaptive Selective Entry (ASE):** Parameter dapat di-tuning manual; aturan, asumsi biaya, batasan OHLC, dan blueprint MT5 ada di [`reports/GOLDWAVE_INSPIRED_ASE.md`](reports/GOLDWAVE_INSPIRED_ASE.md). Strategi ini belum memiliki klaim performa sampai lolos backtest out-of-sample.
* **Simulasi Portofolio Akun $10.000:**
  * 📈 **Growth Scorecard:** Pertumbuhan saldo modal dalam nominal ($) dan persentase (%).
  * 🎯 **Win Rate (WR):** Persentase kemenangan (%) dan rasio Win/Loss.
  * 📉 **Max Drawdown (DD):** Penurunan saldo tertinggi ($) dan persentase (%) *peak-to-valley*.
  * ⚖️ **Profit Factor & Expectancy:** Rasio Gross Profit terhadap Gross Loss.
  * 💰 **Saldo Akhir:** Real-time equity tracking.
* **Visualisasi Kanvas Equity Curve:** Grafik interaktif pergerakan saldo dari $10.000 lengkap dengan batas modal awal.
* **Trade Execution Log Table:** Riwayat transaksi per lilin dengan harga entry, SL, TP, arah Long/Short, PnL ($), dan Saldo.
* **Strategi Unggulan (M5):**
  * `volume_profile_failed_auction` — 85.2% WR, +14.7% growth, max DD 2.03% pada risk 1.0% (XAUUSD M5, 12 bulan). Aturan lengkap, tabel risk, dan validasi ada di [`reports/STRATEGI_VOLUME_PROFILE_FAILED_AUCTION.md`](reports/STRATEGI_VOLUME_PROFILE_FAILED_AUCTION.md).
  * `london_ny_vwap_pullback` — 68.0% WR, +43.1% growth, max DD 4.54% pada risk 1.5% (XAUUSD M5, 6 Okt–4 Nov 2026). Aturan lengkap di [`reports/STRATEGI_LONDON_NY_VWAP.md`](reports/STRATEGI_LONDON_NY_VWAP.md).

### 3. 📊 Interactive HTML Report & Candlestick Viewer
* Embedding langsung laporan visual candlestick beresolusi tinggi di dalam aplikasi tanpa perlu browser eksternal.
* Menampilkan penandaan area sweep, kotak FVG, dan garis transaksi entry/SL/TP.

### 4. 📤 MT5 & MQL5 Exporter
* **Indikator Kustom MQL5 (`mql5/ICT_IFVG_Indicator.mq5`):**
  * Menggambar kotak transparan zona IFVG secara otomatis di chart MT5.
  * Sinyal panah entry Buy/Sell (Wingdings arrow).
  * Filter tren Fast EMA (20) & Slow EMA (50).
  * Popup Sound & Mobile Alert saat sinyal muncul.
* **Expert Advisor MQL5 (`mql5/ICT_IFVG_Gold_EA.mq5`):**
  * Eksekusi otomatis posisi Buy & Sell berdasarkan retest IFVG.
  * Manajemen resiko 1% per trade otomatis dari modal akun.
  * Trailing / Fixed Stop Loss & Take Profit (1:2 RR).
* **Export File `.set`:** Simpan konfigurasi parameter teruji ke file `.set` siap pakai di MT5.

---

## 🚀 Panduan Memulai (Quick Start)

### Persyaratan Sistem
* Node.js v18+ 
* Python 3.9+ (Zero-dependency, murni Python Standard Library!)

### Instalasi & Menjalankan Aplikasi
```bash
# Clone repository
git clone https://github.com/amfitrite/Gold-Tester.git
cd Gold-Tester

# Install dependensi Electron & Dukascopy Node
npm install

# Jalankan aplikasi
npm start
```

Atau cukup klik dua kali pada file **`Start-App.bat`** di Windows.

---

## 📁 Struktur Direktori Proyek

```text
Gold-Tester/
├── assets/
│   ├── icon.ico              # Multi-resolution Windows app icon (256x256 to 16x16)
│   └── icon.png              # High-res app logo
├── engine/                   # Python Quantitative Backtesting Engine
│   ├── src/sweepbt/          # Core Sweep Strategy Pipeline
│   │   ├── strategies/       # Pluggable Strategy Registry (23 Strategies)
│   │   ├── engine.py         # Simulation Engine
│   │   ├── parser.py         # CSV Candle Parser
│   │   └── chart.py          # HTML Candlestick Visualizer
│   ├── backtest_runner.py    # $10k Portfolio Simulator & IPC Bridge
│   └── requirements.txt
├── mql5/                     # MetaTrader 5 Source Code
│   ├── ICT_IFVG_Indicator.mq5# Custom Visual Indicator (Boxes, Arrows, Alerts)
│   └── ICT_IFVG_Gold_EA.mq5  # Automated Trading Expert Advisor
├── renderer/                 # Electron Front-End UI
│   ├── index.html            # Main UI Layout & Sidebar
│   ├── styles.css            # Modern Dark-Themed Styling
│   └── app.js                # Interactive Dashboard Logic
├── main.js                   # Electron Main Process (IPC & Native Dialogs)
├── preload.js                # Secure Context Bridge
├── package.json
├── Start-App.bat             # 1-Click Desktop Launcher
└── README.md
```

---

## 📜 Lisensi
Didistribusikan di bawah Lisensi MIT. Bebas digunakan, dimodifikasi, dan diadaptasi untuk riset maupun trading live.

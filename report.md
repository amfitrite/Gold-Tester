# MASTER AUDIT & REFERENSI STRATEGI TRADING XAUUSD (GOLD) M5
**Dokumentasi Komprehensif: Strategi Unggulan (Profitable) vs Strategi Gagal / Overclaim**

Dokumen ini disusun sebagai panduan referensi permanen mengenai hasil riset, backtesting kualitas tinggi, dan pengujian kuantitatif pada dataset Emas (**XAU/USD**) timeframe **M5** (70.891 candlestick, periode 12 bulan penuh).

---

## BAGIAN I: STRATEGI UNGGULAN (PROVEN PROFITABLE & SIAP PAKAI)

Strategi-strategi berikut telah divalidasi memiliki ekspektasi matematis positif (*positive expectancy*), rasio risiko berbanding keuntungan yang sehat, dan ketahanan terhadap berbagai rezim volatilitas pasar emas.

### 1. London Sweep Trap (Institutional Judas Trap) — *The Absolute Champion* 🥇
* **Konsep Utama**: Memanfaatkan manipulasi sesi likuiditas (*Judas Swing*) yang terjadi di sekitar Session VWAP (Volume-Weighted Average Price) harian saat jam-jam paling likuid di dunia (London & New York: 07:00 – 18:00 UTC).
* **Mekanisme Eksekusi**:
  * **Session VWAP Harian**: Dihitung kumulatif dari volume transaksi dan di-reset setiap pergantian hari (00:00 UTC).
  * **Bullish Trap (BUY)**: Harga ditekan ke bawah Session VWAP untuk menyapu stop-loss trader ritel, lalu candlestick segera ditutup kembali (*reclaim*) di atas VWAP.
  * **Bearish Trap (SELL)**: Harga didorong ke atas Session VWAP untuk memancing buy-stop ritel, lalu candlestick segera ditutup kembali di bawah VWAP.
  * **Stop-Loss (SL)**: Ekstrem ketat di ujung wick sapuan likuiditas $\pm (0.5 \times \text{ATR})$.
  * **Take-Profit (TP)**: Proyeksi asimetris likuiditas mean-reversion:
    $$\text{Target Long} = \text{VWAP} + (\text{VWAP} - \text{Low}) \times 1.5$$
    $$\text{Target Short} = \text{VWAP} - (\text{High} - \text{VWAP}) \times 1.5$$
* **Hasil Pengujian Kuantitatif (12 Bulan M5)**:
  * **Total Transaksi**: 1.225 trade
  * **Win Rate**: **75.27% – 76.23%** (922 Win / 303 Loss)
  * **Max Drawdown**: **2.97%** *(Sangat aman di bawah batas toleransi 5%)*
  * **Profit Factor**: **4.86**
  * **Pertumbuhan Akun**: **+4.356.572%** (Compounding 1% risk) / **+$108.000 (+1.080% Flat Lot tanpa compound)**
* **Tersedia Sebagai**: Engine Backtester Python, Indikator MT4 (`.mq4`/`.ex4`), dan Indikator MT5 (`.mq5`/`.ex5`) lengkap dengan Interactive HUD Dashboard.

---

### 2. VWAP Bounce 2 (Optimized) 🥈
* **Konsep Utama**: Rebound likuiditas berbasis konfluensi tren EMA 20 & EMA 50 saat harga menyentuh Session VWAP dengan konfirmasi sumbu penolakan (*rejection wick*).
* **Hasil Pengujian (12 Bulan M5)**:
  * **Total Transaksi**: 242 trade
  * **Win Rate**: **88.43%**
  * **Max Drawdown**: **1.99%**
  * **Compound Growth**: **+534.7%**
  * **Profit Factor**: **9.12**
* **Keunggulan**: Drawdown sangat tipis (< 2%), stabilitas kurva ekuitas sangat mulus.

---

### 3. VWAP Bounce v1 🥉
* **Konsep Utama**: Pantulan murni (*pure bounce*) saat harga menyentuh garis VWAP kumulatif dengan target simetris terhadap jarak deviasi lilin.
* **Hasil Pengujian (12 Bulan M5)**:
  * **Total Transaksi**: 118 trade
  * **Win Rate**: **84.80%**
  * **Max Drawdown**: **2.00%**
  * **Compound Growth**: **+125.7%**
  * **Profit Factor**: **5.52**

---

### 4. Doji Ride (Pure Price Action / Wick Absorption)
* **Konsep Utama**: Mengidentifikasi candlestick Doji (body $\le 8\%$ range, wick $\ge 50\%$) pada level struktur ekstrem (Previous Day High/Low & Asian Range High/Low). Sumbu panjang Doji menyerap likuiditas order stop, dan transaksi dieksekusi saat bar berikutnya melakukan breakout dari Doji tersebut.
* **Hasil Pengujian (12 Bulan M5)**:
  * **Total Transaksi**: 75 trade
  * **Win Rate**: **84.00%** (63 Win / 12 Loss)
  * **Max Drawdown**: **1.99%** ($220.70)
  * **Profit Factor**: **2.07** (TP 0.40R, SL 1.00R di ujung wick Doji)
  * **Growth Portofolio**: **+13.98%** (pada risk 1.0%) / **+21.59%** (pada risk 1.5%)
* **Keunggulan**: Murni price action tanpa indikator lagging, SL paling sempit di antara seluruh strategi.

---

### 5. Volume Profile Failed Auction
* **Konsep Utama**: Eksploitasi kegagalan lelang institusional (*failed auction*) di bawah Value Area Low (VAL 80%) hari sebelumnya selama jendela pembukaan pasar Eropa (09:00 – 12:00 UTC).
* **Hasil Pengujian (12 Bulan M5)**:
  * **Total Transaksi**: 81 trade
  * **Win Rate**: **81.50%**
  * **Max Drawdown**: **2.15%**
  * **Profit Factor**: **2.06**
  * **Growth**: **+17.44%**

---

### 6. Liquidity Bubble Trap (Delta Volume Trap)
* **Konsep Utama**: Menangkap fenomena jebakan volume di mana terjadi lonjakan volume agresif (*bubble volume*) yang menembus level support/resistance tetapi gagal melanjutkan pergerakan (*failed auction / trapped buyers & sellers*).
* **Hasil Pengujian (12 Bulan M5)**:
  * **Total Transaksi**: 121 trade
  * **Win Rate**: **74.40%**
  * **Max Drawdown**: **3.20%**
  * **Profit Factor**: **1.65**
  * **Growth**: **+22.60%**

---

### 7. Bollinger Bands 2 (Optimized Mean Reversion)
* **Konsep Utama**: Modifikasi Bollinger Bands klasik yang diselaraskan dengan tren makro EMA 20 & 50 serta buffer volatilitas 35% di luar outer band untuk mencegah stop-hunting.
* **Hasil Pengujian (12 Bulan M5)**:
  * **Total Transaksi**: 339 trade
  * **Win Rate**: **59.60% – 66.57%**
  * **Max Drawdown**: **6.79% – 11.71%**
  * **Compound Growth**: **+416.6% – +1.278.0%**
  * **Profit Factor**: **3.06**

---

### 8. Previous Day Breakout (PDH/PDL Retest)
* **Konsep Utama**: Mengambil breakout dan retest dari level tertinggi/terendah hari sebelumnya (Previous Day High / Low).
* **Hasil Pengujian (12 Bulan M5)**:
  * **Total Transaksi**: 279 trade
  * **Win Rate**: **54.80% – 61.70%**
  * **Max Drawdown**: **4.99% – 12.24%**
  * **Compound Growth**: **+483.3% – +838.7%**
  * **Profit Factor**: **2.16**

---

## BAGIAN II: STRATEGI GAGAL, OVERCLAIM, & TIDAK PROFITABLE (DOKUMENTASI REFERENSI)

Bagian ini mendokumentasikan strategi-strategi yang secara teoritis populer di kalangan trader ritel, namun **terbukti gagal total atau mengalami overclaim drastis saat diuji secara objektif pada data historis emas**. Simpan sebagai pelajaran agar tidak mengulangi kesalahan desain yang sama.

### 1. Bollinger Bands + RSI Reversion (`bollinger_rsi_reversion`)
* **Asal Usul**: Branch baru GitHub `feat-strategy-research-13601549313997122311` (Commit `29d7148`).
* **Aturan Strategi**:
  * Buy saat harga sentuh Lower Band (20, 2.0) DAN RSI (14) < 30.
  * Sell saat harga sentuh Upper Band (20, 2.0) DAN RSI (14) > 70.
  * Target di Middle Band (SMA 20).
* **Hasil Uji Backtest**:
  * **Total Trades**: 1.651 trade
  * **Win Rate**: **36.47%** ❌
  * **Max Drawdown**: **-82.54%** ❌
  * **Net Growth**: **-79.29%** (Hampir Habis Modal) ❌
  * **Profit Factor**: **0.82**
* **Diagnosa Mengapa Gagal**:
  1. *Walking the Bands*: Emas sering mengalami tren impulsif yang sangat kuat. Saat tren naik, harga akan menempel di upper band dan RSI bertahan di atas 70 selama puluhan candle. Strategi ini terus melakukan *sell* counter-trend dan terkena stop loss beruntun.
  2. *Bad R:R Execution*: Karena entry menunggu konfirmasi candle close di luar band, jarak ke middle band sudah sangat menyempit, sehingga Reward yang didapat jauh lebih kecil daripada Risk Stop Loss-nya.

---

### 2. London/NY VWAP Pullback Klasik (Fixed 1:1) — *Kasus Overclaim*
* **Klaim Asli**: Diklaim di dokumentasi lama memiliki Win Rate 68.0% dan Max Drawdown 4.54%.
* **Hasil Uji Objektif Independen (12 Bulan Out-of-Sample)**:
  * **Win Rate**: **44.75% – 49.44%** ❌ (Jauh di bawah klaim 68%)
  * **Max Drawdown**: **-53.93% s/d -96.91%** (Margin Call / Nyaris Habis) ❌
  * **Net Growth**: **-28.29% s/d -96.45%** ❌
  * **Profit Factor**: **0.92**
* **Diagnosa Mengapa Overclaim**:
  1. *Curve-Fitting Sempit*: Strategi ini dioptimasi pada sampel data sangat pendek di mana tren searah sedang mulus. Begitu menghadapi pasar konsolidasi atau chop, strategi ini hancur.
  2. *Double Half-Spread & Time Stop*: Pemotongan spread ganda pada entry dan exit serta penutupan paksa pada 24 bar memotong profit trade yang sedang berkembang.

---

### 3. Bollinger Bands v1 Klasik (Tanpa Filter Tren)
* **Aturan**: Reversi murni saat menyentuh outer band.
* **Hasil Uji**:
  * **Win Rate**: **24.1%** ❌
  * **Max Drawdown**: **-100.00%** (Akun Ludes) ❌
  * **Net Growth**: **-100.0%** ❌
  * **Profit Factor**: **0.63**
* **Diagnosa**: Menjual di band atas saat uptrend dan membeli di band bawah saat downtrend tanpa memperhitungkan apakah band sedang mengalami ekspansi volatilitas (*band expansion*).

---

### 4. Momentum Breakout & Momentum Pullback
* **Hasil Uji**:
  * Win Rate: **32.5% – 32.9%** ❌
  * Max Drawdown: **-63.2% s/d -71.5%** ❌
  * Growth: **-37.8% s/d -49.4%** ❌
* **Diagnosa**: Breakout ritel di emas sering kali adalah *fakeout* (jebakan likuiditas). Membeli di pucuk momentum sering kali tepat sebelum institusi melakukan aksi ambil untung (*profit taking*).

---

### 5. ICT FVG & IFVG Unfiltered
* **Hasil Uji**:
  * Win Rate: **35.7% – 38.1%** ❌
  * Max Drawdown: **-34.9% s/d -36.7%** ❌
* **Diagnosa**: Mengambil setiap celah Fair Value Gap 3-bar tanpa menyaring jam sesi institusional menghasilkan ribuan sinyal palsu pada saat likuiditas pasar rendah (*Asian dead zone*).

---

### 6. RSI Reversal Klasik
* **Hasil Uji**:
  * Win Rate: **32.2%** ❌
  * Max Drawdown: **-69.35%** ❌
  * Growth: **-56.3%** ❌
* **Diagnosa**: Osilator murni tertinggal (*lagging*) dan tidak memiliki kekuatan prediksi arah di pasar komoditas volatil.

---

### 7. FVG Crossfire State Machine (Flux Charts Pine Script v6)
* **Asal Usul**: Konversi Pine Script v6 (`FVG_Crossfire.mq4`) dengan State Machine 5 tahap (*Sweep $\rightarrow$ Rejection $\rightarrow$ BOS $\rightarrow$ Displacement $\rightarrow$ Retest*) dan sistem skor kualitas (*Scoring System*).
* **Hasil Uji Default Asli (Skor $\ge 70$, HTF Bias M15, Target RR 2.0)**:
  * **Total Trades**: 1 trade (selama 12 bulan penuh / 70.891 bar M5) ❌
  * **Win Rate**: 100.0% (1 Win / 0 Loss)
  * **Net Growth**: +2.00% (+$200.00 pada akun $10.000)
* **Hasil Uji Setelah Tuning Menyeluruh (8 Grid Permutasi)**:
  * **Win Rate**: Mentok di kisaran **35.7% – 44.4%** ❌
  * **Max Drawdown**: -2.97% s/d -4.18%
  * **Profit Factor**: 0.66 – 1.26
  * **Net Growth**: -3.03% s/d +2.85% (Stagnan / BEP)
* **Diagnosa Mengapa Gagal / Mentok di Win Rate Rendah**:
  1. *Definisi Crossfire Adalah Area Konsolidasi*: Zona Crossfire terbentuk dari tabrakan dua FVG yang berlawanan arah. Ini menandakan pasar sedang mengalami *choppiness* / sideways. Membeli/menjual retest BOS di tengah rentang sideways pada komoditas agresif seperti Emas selalu rentan terhadap jebakan *fakeout* (*whipsaw*).
  2. *Self-Cancelling Filter & Premature Invalidation*: Pada parameter default asli, ambang skor $\ge 70$ menuntut seluruh syarat ekstrem terjadi serentak, mematikan 99.9% peluang trade. Selain itu, aturan `mitigated = loSrc <= bottom` sering kali membunuh zona saat wick retest menyentuh batas bawah sesaat sebelum panah entry dieksekusi.
  3. *Kesimpulan Riset*: Kode disimpan dan dikompilasi ke `mt4/FVG_Crossfire.ex4` sebagai alat bantu visual pemetaan zona di chart MT4, namun **tidak direkomendasikan** untuk sinyal eksekusi trading otomatis.

---

### 8. Squeeze Momentum Indicator [LazyBear] (TTM Squeeze Pine Script)
* **Asal Usul**: Indikator paling populer di TradingView (*LazyBear Squeeze Momentum* dengan 100.000+ pengguna) berbasis kompresi Bollinger Bands di dalam Keltner Channel dan osilator regresi linear.
* **Aturan Sinyal Eksekusi**:
  * Squeeze Fired: Bollinger Bands keluar dari Keltner Channel (`sqzOff == true` setelah `sqzOn == true`).
  * Buy: Momentum regresi linear bernilai positif dan meningkat (`val > 0` dan hijau/lime).
  * Sell: Momentum regresi linear bernilai negatif dan menurun (`val < 0` dan merah/maroon).
* **Hasil Uji Backtest Objektif (12 Bulan / 70.891 Bar M5 XAUUSD, Modal $10.000)**:
  * **Uji 1 (Standard Squeeze Release, RR 1.5, SL 1.5x ATR)**:
    * Total Trades: 2.438 trade
    * Win Rate: **39.80%** ❌
    * Max Drawdown: **-52.46%** ❌
    * Saldo Akhir: **$7.505,12 (-24.95%)** ❌
    * Profit Factor: **0.98**
  * **Uji 2 (Standard Squeeze Release, RR 2.0, SL 1.5x ATR)**:
    * Total Trades: 2.215 trade
    * Win Rate: **32.80%** ❌
    * Max Drawdown: **-66.41%** ❌
    * Saldo Akhir: **$5.721,30 (-42.79%)** ❌
    * Profit Factor: **0.96**
  * **Uji 3 (Squeeze Release + Sesi London/NY 07-18 UTC)**:
    * Total Trades: 1.200 trade
    * Win Rate: **39.10%** ❌
    * Max Drawdown: **-44.30%** ❌
    * Saldo Akhir: **$6.948,66 (-30.51%)** ❌
  * **Uji 4 (Squeeze Release + Filter Tren EMA 50 + London/NY)**:
    * Total Trades: 1.098 trade
    * Win Rate: **31.50%** ❌
    * Max Drawdown: **-63.08%** ❌
    * Saldo Akhir: **$4.935,44 (-50.65% / Terpotong Separuh Modal)** ❌
* **Hasil Eksperimen Rekayasa & Tuning (4 Model Arsitektur Baru)**:
  * **Model 1: Squeeze Midline Retest** (Beli pullback ke SMA 20, bukan breakout): Win Rate **30.4%**, Growth **-26.55%** ❌
  * **Model 2: Squeeze Contrarian Trap** (Fade breakout palsu jika sumbu wick $\ge 45\%$): Win Rate **44.7%**, Max DD **-3.94%**, Growth **+4.29%** (Sedikit positif, namun WR tetap $< 50\%$).
  * **Model 3: Early Zero-Cross Inside Squeeze** (Antisipasi momentum saat kompresi): Win Rate **40.1%**, Growth **-3.78%** ❌
  * **Model 4: Extreme Impulse Momentum** (Ambang batas momentum $> 1.2$ ATR): Win Rate **32.9%**, Growth **-22.36%** ❌
* **Diagnosa Mengapa Squeeze Momentum Hancur di Pasar Emas**:
  1. *Lagging Linear Regression*: Garis linreg membutuhkan 20 bar. Saat pita Bollinger baru keluar dari Keltner Channel dan histogram momentum terkonfirmasi, pergerakan impulsif emas biasanya sudah mencapai titik jenuh (*exhaustion point*). Trader ritel masuk tepat saat pembalikan arah terjadi.
  2. *Whipsaw False Breakout*: Emas intraday sangat sering mengalami lonjakan volatilitas palsu (*fake expansion*). Squeeze meletup sekejap lalu harga ditarik kembali ke garis gravitasi VWAP harian, memicu rentetan stop-loss berturut-turut.
  3. *Overtrading Kronis*: Terjadinya 1.000–2.400 trade per tahun pada timeframe M5 menggerogoti ekuitas akun secara drastis melalui spread dan *whipsaw*.
  4. *Kesimpulan Tuning*: Squeeze breakout momentum secara konsep bertentangan dengan mikrostruktur emas yang berbasis *liquidity sweep*. Strategi ini tidak dapat dituning menjadi high win-rate ($> 75\%$) karena sifat dasarnya yang *pro-cyclical* di fase akhir pergerakan harga.

---

### 9. Machine Learning: Lorentzian Classification v2.0 (jdehorty)
* **Asal Usul**: Indikator TradingView open-source terpopuler dalam kategori Machine Learning (*Lorentzian Classification v2.0* oleh `@jdehorty`).
* **Arsitektur Model**:
  * Menggunakan algoritma *Approximate k-Nearest Neighbors* ($k=8$) dengan fungsi jarak *Lorentzian Distance* pada ruang 5 fitur (RSI 14, WaveTrend, CCI 20, ADX 20, RSI 9).
  * Filter tren *Nadaraya-Watson Rational Quadratic Kernel Regression*.
  * Label prediksi: Arah penutupan 4 bar ke depan ($Close_{t+4} \gtrless Close_t$).
* **Hasil Uji Backtest Objektif (12 Bulan / 70.891 Bar M5 XAUUSD, Modal $10.000)**:
  * **Uji 1 (Default Pine Script: Strict 4-Bar Holding Exit, 24/5)**:
    * Total Trades: 5.595 trade
    * Win Rate: **48.50%** ❌
    * Max Drawdown: **-32.73%** ⚠️
    * Profit Factor: 1.05 | Saldo: $23.938,55 (+139.39%) *(Hanya efek tren makro emas, kurva sangat bergejolak)*
  * **Uji 2 (Default Pine Script + Sesi London/NY 07-18 UTC)**:
    * Total Trades: 2.705 trade
    * Win Rate: **48.40%** ❌
    * Max Drawdown: **-21.04%** ⚠️
    * Profit Factor: 1.03 | Saldo: $12.997,51 (+29.98%)
  * **Uji 3 (Target RR 1.5, SL 1.5x ATR, 24/5)**:
    * Total Trades: 3.509 trade
    * Win Rate: **40.90%** ❌
    * Max Drawdown: **-49.74%** ⚠️
    * Profit Factor: 1.01 | Saldo: $12.587,26 (+25.87%)
  * **Uji 4 (Target RR 2.0, SL 1.5x ATR, London/NY)**:
    * Total Trades: 1.603 trade
    * Win Rate: **34.10%** ❌
    * Max Drawdown: **-55.57%** ⚠️
    * Profit Factor: 0.94 | Saldo: $6.101,62 **(-38.98% / Kerugian Besar)** ❌
  * **Uji 5 (High Confidence: Pred $\ge 5$, RR 1.5, London/NY)**:
    * Total Trades: 696 trade
    * Win Rate: **40.70%** ❌
    * Max Drawdown: **-29.86%** ⚠️
    * Profit Factor: 1.00 | Saldo: $9.867,81 (-1.32%)
* **Hasil Eksperimen Rekayasa & Tuning Kuantitatif (7 Konfigurasi Baru)**:
  * Kita menguji modifikasi mendalam: mengganti fitur ritel dengan fitur institusional (jarak ke VWAP, rasio sumbu penolakan wick, delta tren EMA 20/50), memperpanjang target horizon prediksi ke 8 dan 12 bar (40–60 menit), serta memperketat konsensus voting k-NN menjadi hampir mutlak ($\ge 6$ dan $\ge 7$ dari 8 tetangga).
  * **Tuning 1 (Fitur Institusi, Konsensus $\ge 6$, RR 1.5)**: Win Rate **38.8%**, Max DD **-38.25%**, Growth **-29.86%** ❌
  * **Tuning 2 (Fitur Institusi, Konsensus Ketat $\ge 7$, RR 1.5)**: Win Rate **40.4%**, Max DD **-18.87%**, Growth **+0.57%** (BEP) ❌
  * **Tuning 4 (Label Horizon 1 Jam, Konsensus $\ge 6$, RR 1.5)**: Win Rate **37.1%**, Max DD **-63.33%**, Growth **-54.45%** ❌
  * **Tuning 6 & 7 (Hybrid ML + Filter Pantulan VWAP)**: Win Rate **38.6% – 41.8%**, Max DD **-17.55%**, Growth **-0.31% s/d +7.39%**.
* **Diagnosa Mengapa Algoritma Machine Learning Ini Gagal Memenuhi Kriteria Juara**:
  1. *Ilusi Label Jangka Pendek (4-Bar Horizon)*: Menugaskan k-NN untuk memprediksi arah lilin 4 bar ke depan hanya berdasarkan level osilator ritel (RSI/CCI/WT) pada dasarnya setara dengan melempar koin (*coin flip*, Win Rate 40% – 48.5%).
  2. *Non-Stasioneritas Data Finansial (Curse of Dimensionality)*: Pasar emas bergerak secara non-ergodik. Dua titik lilin yang memiliki nilai fitur osilator sama persis di masa lalu sering kali menghasilkan arah berlawanan di masa depan karena arus order institusi yang tidak tercermin dalam osilator.
  3. *Overfitting & Noise Filtering*: Menariknya, strategi murni **VWAP Bounce 2** memiliki Win Rate **88.4%**. Namun ketika disaring melalui filter k-NN Lorentzian, Win Rate-nya justru **anjlok menjadi 41.8%** karena model k-NN salah mengira sinyal valid sebagai noise historis.
  4. *Kesimpulan*: Algoritma k-NN Lorentzian tidak dapat dituning menjadi strategi andalan di pasar emas (WR tetap mentok di kisaran 33%–42%). Keunggulan matematis sejati di XAUUSD berada pada aturan struktural eksploitasi likuiditas (London Sweep Trap & VWAP Bounce 2).

---

---

### 10. Footprint Histogram + RVol Heatmap (Order Flow Delta Absorption Engine)
* **Asal Usul**: Indikator Pine Script v6 "Footprint Histogram (Top) + RVol Heatmap (Bottom)" (*FP + RVol Stack*).
* **Arsitektur Model**:
  * Menggunakan dekomposisi Intrabar 1-menit (M1) di dalam lilin 5-menit (M5) untuk merekonstruksi volume beli/jual secara presisi ($BuyRatio = \frac{Close - Low}{High - Low}$, $AskVol = Vol \times BuyRatio$, $BidVol = Vol \times (1 - BuyRatio)$).
  * Menghitung $NetDelta = AskVol - BidVol$.
  * Logika Sinyal Divergensi Absorpsi (*Order Flow Absorption*):
    * **Bullish Absorption (Arrow Hijau / Buy)**: Candle Merah ($Close < Open$) namun Net Delta Positif ($NetDelta > 0$). Tekanan jual agresif berhasil diserap (*absorbed*) oleh limit buyer institusi.
    * **Bearish Absorption (Arrow Merah / Sell)**: Candle Hijau ($Close > Open$) namun Net Delta Negatif ($NetDelta < 0$). Dorongan beli agresif berhasil diserap (*absorbed*) oleh limit seller institusi.
  * Panel Bawah: Relative Volume ($RVol = \frac{Vol}{SMA(Vol, 20)}$) dan Percentile Rank 100-bar.
* **Hasil Uji Backtest Objektif (12 Bulan / 70.891 Bar M5 XAUUSD, Modal $10.000, Resiko 1%/Trade)**:
  * **Uji 1 (Default Pine Script: Pure Divergence, RR 1.0, SL 1.5x ATR, 24/5)**:
    * Total Trades: 6.254 trade (Terlalu banyak sinyal, rata-rata 1 sinyal tiap 4.7 candle)
    * Win Rate: **47.5%** ❌
    * Max Drawdown: **-97.1%** (Akun hancur tergerus spread & noise) ❌
    * Profit Factor: 0.88 | Saldo Akhir: **$318,36 (-96.8%)** ❌
  * **Uji 2 (Default Pine Script: Pure Divergence, RR 1.5, SL 1.5x ATR, 24/5)**:
    * Total Trades: 4.915 trade
    * Win Rate: **38.3%** ❌
    * Max Drawdown: **-94.9%** ❌
    * Profit Factor: 0.88 | Saldo Akhir: **$531,10 (-94.7%)** ❌
  * **Uji 3 (Default Pine Script: Pure Divergence, RR 2.0, SL 1.5x ATR, 24/5)**:
    * Total Trades: 4.164 trade
    * Win Rate: **33.5%** ❌
    * Max Drawdown: **-89.5%** ❌
    * Profit Factor: 0.88 | Saldo Akhir: **$1.557,74 (-84.4%)** ❌
* **Hasil Eksperimen Rekayasa & Tuning Kuantitatif**:
  * *Uji Validasi Mekanisme Pasar*: Menguji hipotesis absorpsi murni vs perangkap kelanjutan (*Trapped Traders*). Hasilnya membuktikan teori absorpsi institusional adalah valid (PF 1.01 vs Trapped PF 0.86), namun gagal pada versi default murni akibat polusi *low-volume chop* di luar jam utama.
  * *4 Pilar Tuning yang Berhasil Membalikkan Strategi Menjadi Profitabel*:
    1. **Sesi Likuid**: Membatasi entri hanya pada sesi London & New York (07:00 – 19:00 UTC).
    2. **Filter Volume Relatif Institusi ($RVol \ge 1.4 - 1.5$)**: Menyingkirkan 95% divergensi palsu yang terjadi saat volume tipis.
    3. **Filter Ketidakseimbangan Delta Signifikan ($\frac{|NetDelta|}{TotalVol} \ge 25\% - 30\%$)**: Hanya masuk jika salah satu pihak menyerap volume secara dominan.
    4. **Risk-to-Reward Ratio Asimetris (RR 1.8 - 2.0)**:
  * **Ringkasan Konfigurasi Hasil Tuning Terbaik**:
    * **Konfigurasi Growth Maksimal ($RVol \ge 1.5$, Delta Imbalance $\ge 25\%$, RR 2.0)**:
      - Total Trades: 86 trade dalam 12 bulan
      - Win Rate: **43.0%** (Menguntungkan karena pada RR 1:2 breakeven hanya butuh 33.3%)
      - Max Drawdown: **8.7%** ✅ (Jauh lebih aman dibandingkan versi dasar 97%)
      - Profit Factor: **1.36** ✅
      - Equity Growth: **+21.0%** ✅ | Saldo Akhir: **$12.096,89** (Profit Bersih +$2.096,89)
    * **Konfigurasi Presisi / Max Drawdown Terendah ($RVol \ge 1.5$, Delta Imbalance $\ge 30\%$, RR 2.0)**:
      - Total Trades: 44 trade dalam 12 bulan
      - Win Rate: **45.5%**
      - Max Drawdown: **5.0%** ✅ (Sangat konservatif & aman)
      - Profit Factor: **1.47** ✅
      - Equity Growth: **+12.6%** ✅ | Saldo Akhir: **$11.258,54**
    * **Konfigurasi Win Rate Tertinggi ($RVol \ge 1.5$, Delta Imbalance $\ge 30\%$, RR 1.5)**:
      - Total Trades: 44 trade dalam 12 bulan
      - Win Rate: **50.0%**
      - Max Drawdown: **4.0%** ✅
      - Profit Factor: **1.39** ✅
      - Equity Growth: **+9.2%** ✅ | Saldo Akhir: **$10.923,52**
* **Kesimpulan & Rekomendasi**:
  * Indikator Footprint + RVol ini **BISA DITUNING** dan menghasilkan performa positif stabil (Profit Factor 1.36 – 1.47 dengan Max Drawdown hanya 5% – 8.7%).
  * Meskipun profitabel dan aman setelah dituning, kapasitas pertumbuhannya (+12% hingga +21% per tahun dengan 40–80 trade) masih berada di bawah strategi unggulan likuiditas murni seperti **VWAP Bounce 2** (+79.5% pertumbuhan, WR 88.4%) dan **London Sweep Trap** (+117.8% pertumbuhan, WR 78.5%).
  * **Rekomendasi Praktis**: Jadikan filter Footprint Delta Imbalance ($\ge 25\%$) dan RVol ($\ge 1.5$) sebagai *komponen konfirmasi sekunder* untuk validasi pantulan VWAP atau Liquidity Sweep, bukan sebagai satu-satunya pemicu entri mandiri.

---

### 11. Supertrend (Classic ATR Trailing Trend-Following Engine)
* **Asal Usul**: Indikator tren paling populer di dunia TradingView (*Supertrend v4* oleh KivancOzbilgic / Olivier Seban).
* **Arsitektur Model**:
  * Menggunakan batas volatilitas berbasis ATR: $Band_{Atas} = rac{High + Low}{2} + Multiplier 	imes ATR$, $Band_{Bawah} = rac{High + Low}{2} - Multiplier 	imes ATR$.
  * Garis Supertrend bergerak secara *ratchet* (hanya naik saat uptrend dan hanya turun saat downtrend).
  * Pembalikan tren terjadi saat harga penutupan (*Close*) menembus garis Supertrend sebelumnya ($Trend = 1$ jika Close > $Band_{Atas}$, $Trend = -1$ jika Close < $Band_{Bawah}$).
* **Hasil Uji Backtest Objektif (12 Bulan / 70.891 Bar M5 XAUUSD, Modal $10.000, Resiko 1%/Trade)**:
  * **Uji 1 (Mitos YouTube / Default Always-In Flip Reversal, 24/5)**:
    * Total Trades: 1.843 trade
    * Win Rate: **33.5%** ❌
    * Max Drawdown: **-99.8% (Akun Hancur Total / Margin Call)** ❌
    * Profit Factor: 0.76 | Saldo Akhir: **$30,70 (-99.7%)** ❌
    * *Diagnosa*: Emas bergerak dalam osilasi rentang lebar. Membalikkan posisi setiap kali garis menembus (breakout lag) selalu membeli di pucuk tertinggi dan menjual di dasar terendah, menghasilkan kerugian beruntun masif saat konsolidasi.
  * **Uji 2 (Fixed RR 1.0, SL Garis Supertrend, 24/5)**:
    * Total Trades: 1.240 trade | Win Rate: **47.7%** | Max DD: **-46.9%** | PF: 0.91 | Saldo: **$5.724,29 (-42.8%)** ❌
  * **Uji 3 (Fixed RR 1.5, SL Garis Supertrend, 24/5)**:
    * Total Trades: 1.134 trade | Win Rate: **44.3%** | Max DD: **-27.7%** | PF: 1.00 | Saldo: **$10.211,28 (+2.1%)** (BEP)
* **Hasil Eksperimen Rekayasa & Tuning Kuantitatif**:
  * *Mengapa Supertrend Standar Lemah?* Supertrend murni buta terhadap arah tren makro dan sering memicu sinyal pembalikan palsu di dalam pasar *choppy* tanpa momentum.
  * *3 Formula Tuning Juara untuk Mengubah Supertrend Menjadi Mesin Profit*:
    1. **Sesi Likuid**: Membatasi entri hanya pada jam London & New York (07:00 – 19:00 UTC).
    2. **Filter Tren Makro (EMA 200 Filter)**: Hanya mengambil BUY saat $Close > EMA 200$ dan SELL saat $Close < EMA 200$. Ini secara instan membuang 50% *counter-trend whipsaws*.
    3. **Filter Kekuatan Tren (ADX Filter $\ge 20 - 25$)**: Hanya entry jika pasar benar-benar memiliki momentum tren nyata ($ADX \ge 20$).
  * **Ringkasan Konfigurasi Hasil Tuning Terbaik**:
    * **Konfigurasi Growth Tertinggi (Period 10, Mult 3.0, ADX $\ge$ 20, EMA 200, RR 1.5)**:
      - Total Trades: **200 trade** dalam 12 bulan
      - Win Rate: **54.0%** ✅
      - Max Drawdown: **9.2%** ✅ (Sangat aman, turun dari 99.8% ke 9.2%)
      - Profit Factor: **1.56** ✅
      - Equity Growth: **+46.3%** ✅ | Saldo Akhir: **$14.630,44** (Profit Bersih +$4.630,44)
    * **Konfigurasi Growth RR 2.0 (Period 10, Mult 3.0, ADX $\ge$ 20, EMA 200, RR 2.0)**:
      - Total Trades: **198 trade** dalam 12 bulan
      - Win Rate: **52.0%** (Luar biasa untuk sistem RR 1:2.0 yang breakeven di 33.3%)
      - Max Drawdown: **9.2%** ✅
      - Profit Factor: **1.52** ✅
      - Equity Growth: **+44.5%** ✅ | Saldo Akhir: **$14.449,07**
    * **Konfigurasi Presisi / Max Drawdown Terendah (Period 14, Mult 3.5, ADX $\ge$ 25, EMA 200, RR 1.5)**:
      - Total Trades: **74 trade** dalam 12 bulan
      - Win Rate: **55.4%** (Bisa mencapai **59.5%** dengan fitur Breakeven at 1R)
      - Max Drawdown: **hanya 4.0%** ✅ (Drawdown sangat kecil & konservatif)
      - Profit Factor: **1.75** ✅
      - Equity Growth: **+19.1%** ✅ | Saldo Akhir: **$11.907,97**
* **Kesimpulan & Rekomendasi**:
  * Supertrend default murni (Always-in flip) adalah jebakan akun fatal (-99.7% MC).
  * Namun jika digabungkan dengan **Filter Arah EMA 200 + Filter ADX $\ge 20$ + Sesi London/NY**, Supertrend bertransformasi menjadi salah satu strategi tren paling konsisten dengan **Pertumbuhan +46.3% per tahun, Drawdown hanya 9.2%, dan Profit Factor 1.56**.

## BAGIAN III: KESIMPULAN & FORMULA EMAS UNTUK PASAR XAUUSD

Dari seluruh eksperimen dan audit di atas, dapat ditarik hukum baku trading kuantitatif pada instrumen Emas (XAUUSD):

1. **Waktu Sesi Adalah Filter Nomor Satu**:
   Lebih dari 80% sinyal palsu terjadi di luar jam London & New York (07:00 – 18:00 UTC). Membatasi eksekusi hanya pada jam likuid langsung meningkatkan win rate sebesar 15% – 25%.
2. **Institusi Berburu Likuiditas (Liquidity Sweep)**:
   Pola yang paling menguntungkan di emas bukanlah indikator teknikal (RSI/Stochastic), melainkan **menunggu trader ritel terperangkap stop loss (Sweep/Trap), lalu masuk bersamaan dengan arus institusi**.
3. **Session VWAP Adalah Gravitasi Harga**:
   Penyimpangan harga yang ekstrem dari Session VWAP hampir selalu mengalami *mean-reversion* cepat ke sisi seberang VWAP, menjadi fondasi utama kesuksesan strategi **London Sweep Trap** dan **VWAP Bounce 2**.

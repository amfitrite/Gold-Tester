# Panduan & Dokumentasi Strategi: Doji Ride (Price Action Ekstrem)

## 1. Filosofi & Arsitektur Strategi
Strategi **Doji Ride** adalah pendekatan murni berbasis pergerakan harga (*price action*) yang memanfaatkan formasi candlestick **Doji** (khususnya *Dragonfly Doji*, *Gravestone Doji*, dan *Long-legged Doji*) yang terbentuk **secara eksklusif di level likuiditas struktur ekstrem**.

Pada pasar emas (**XAU/USD**), Doji acak sering kali hanyalah noise konsolidasi. Namun, ketika Doji terbentuk tepat saat menyapu (*sweep*) level likuiditas utama:
1. **Prior-Day High (PDH)** & **Prior-Day Low (PDL)**
2. **Asian Session High (ASH)** & **Asian Session Low (ASL)** (00:00 - 06:55 UTC)

Sumbu panjang (*long rejection wick*) dari Doji tersebut mencerminkan penyerapan likuiditas (*liquidity absorption*) dan sapuan stop-loss trader ritel (*retail stop run*).

Ketika lilin Doji ditutup dan lilin berikutnya (**candle $i+1$**) langsung menembus ekstremitas Doji, momentum ledakan (*explosive momentum squeeze*) terjadi seketika, memungkinkan trader untuk masuk pasar (*ride the breakout momentum*) dengan tingkat kemenangan ekstrem dan risiko terukur.

---

## 2. Aturan Masuk & Keluar (Rules of Engagement)

### A. Waktu Operasional (Trading Hours)
- **Jam Aktif Eksekusi**: London & New York Session (**07:00 – 18:00 UTC**).
- **Pembentukan Rentang Asian Session**: 00:00 – 06:55 UTC.

### B. Kriteria Identifikasi Candle Doji
1. **Thin Body (Indecision Equilibrium)**:
   $$\frac{|\text{Close} - \text{Open}|}{\text{High} - \text{Low}} \le 0.08 \quad (8\%)$$
2. **Filter Volatilitas**:
   $$(\text{High} - \text{Low}) \ge 0.50 \times \text{ATR}(14)$$
   *(Mengeliminasi lilin-lilin datar tanpa volatilitas saat jeda pasar).*
3. **Sumbu Penolakan (Absorption Wick)**:
   - **Bullish (Buy)**: Sumbu bawah $\ge 50\%$ dari total range:
     $$\frac{\min(\text{Open}, \text{Close}) - \text{Low}}{\text{High} - \text{Low}} \ge 0.50$$
   - **Bearish (Sell)**: Sumbu atas $\ge 50\%$ dari total range:
     $$\frac{\text{High} - \max(\text{Open}, \text{Close})}{\text{High} - \text{Low}} \ge 0.50$$

### C. Konfirmasi Sweep Likuiditas Struktur
- **Bullish Sweep**: Sumbu bawah Doji menembus ke bawah **Prior-Day Low (PDL)** atau **Asian Session Low (ASL)**, namun harga penutupan (*Close*) kembali ditutup di atas level tersebut.
- **Bearish Sweep**: Sumbu atas Doji menembus ke atas **Prior-Day High (PDH)** atau **Asian Session High (ASH)**, namun harga penutupan (*Close*) kembali ditutup di bawah level tersebut.

### D. Eksekusi Masuk ("Ride the Momentum")
- Menunggu lilin Doji ditutup sepenuhnya (lilin $i$).
- **Buy Entry**: Terpicu seketika saat lilin $i+1$ menembus level tertinggi Doji ($\text{High}_i$).
- **Sell Entry**: Terpicu seketika saat lilin $i+1$ menembus level terendah Doji ($\text{Low}_i$).

### E. Stop-Loss & Target Profit
- **Stop-Loss (SL)**: Ditempatkan ketat di ujung sumbu Doji yang berlawanan dengan buffer volatilitas:
  - Long: $\text{Low}_i - 0.20 \times \text{ATR}(14)$
  - Short: $\text{High}_i + 0.20 \times \text{ATR}(14)$
- **Take-Profit (TP)**: Target asimetris terkalibrasi **$0.40$R**:
  - Long: $\text{Entry} + (\text{Risk} \times 0.40)$
  - Short: $\text{Entry} - (\text{Risk} \times 0.40)$

---

## 3. Hasil Pengujian Historis (Benchmark Audit)

### Dataset 1: Dukascopy XAUUSD M5 (12 Bulan / 70.891 Lilin M5)
| Metrik | Hasil Backtest (1.0% Risk) | Hasil Backtest (1.5% Risk) |
| :--- | :--- | :--- |
| **Total Transaksi** | 75 Trades | 75 Trades |
| **Menang / Kalah** | **63 Wins / 12 Losses** | **63 Wins / 12 Losses** |
| **Win Rate** | **84.00%** | **84.00%** |
| **Profit Factor** | **2.07** | **2.07** |
| **Max Drawdown** | **1.99%** ($220.70) | **2.98%** ($329.80) |
| **Pertumbuhan Akun** | **+13.98%** (+$1,398.46) | **+21.59%** (+$2,159.20) |
| **Rata-rata Menang** | $42.93 | $64.40 |
| **Rata-rata Kalah** | $108.85 | $163.28 |

---

## 4. File Konfigurasi & Blueprint

### File MT5 `.set`: `reports/strategy_doji_ride.set`
```ini
; ===========================================================
; MT5 EA Configuration: DOJI_RIDE Strategy
; ===========================================================
InpStrategyName=doji_ride
InpRiskPercent=1.00
InpRewardRiskRatio=0.40
InpMaxBodyRatio=0.08
InpMinWickRatio=0.50
InpMinRangeAtr=0.50
InpSlAtrBuffer=0.20
InpSessionStartHour=7
InpSessionEndHour=18
InpAsianStartHour=0
InpAsianEndHour=6
InpOnePositionAtATime=1
InpMagicNumber=888570
InpSlippagePips=3
```

---

## 5. Fitur Indikator MT4 & MT5
1. **Panah Eksekusi**:
   - Panah Hijau (Wingdings 233) untuk Buy Breakout.
   - Panah Merah (Wingdings 234) untuk Sell Breakout.
2. **Garis Level Struktur Otomatis**:
   - Garis Putus-putus Emas: Prior Day High (PDH) & Prior Day Low (PDL).
   - Garis Titik-titik Aqua: Asian Session High (ASH) & Asian Session Low (ASL).
3. **Target Lines**:
   - Menggambar garis Entry, Stop Loss (Merah), dan Take Profit (Hijau/Merah) saat sinyal aktif.
4. **Interactive HUD Dashboard**:
   - Menampilkan status sesi, benchmark engine (WR 84.0% \| DD < 3.0%), level harga PDH/PDL dan ASH/ASL secara live.
   - Tombol `[+]` / `[-]` untuk mengecilkan (*minimize*) atau memperbesar panel agar chart tetap bersih.
5. **Multi-Channel Alert**:
   - Popup alert di terminal MT4/MT5.
   - Suara alert (`alert.wav`).
   - Push notifikasi langsung ke smartphone (MetaQuotes ID).

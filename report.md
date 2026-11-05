# Riset Strategi Trading XAUUSD M5 (Win Rate Tinggi, Drawdown Rendah, Equity Growth Bagus)

Berdasarkan riset dan backtesting di seluruh strategi yang tersedia pada dataset XAUUSD M5 (selama 1 bulan dan 1 tahun), berikut adalah hasilnya:

## 1. Bollinger Bands 2 (Optimized Mean Reversion)
Strategi ini menggunakan Bollinger Bands yang dioptimasi dengan EMA 20 dan 50, serta buffer volatilitas.

*   **Hasil 1 Bulan:**
    *   **Win Rate:** 70.59%
    *   **Max Drawdown:** 3.00%
    *   **Equity Growth:** +10.86%
*   **Hasil 1 Tahun:**
    *   **Win Rate:** 66.57%
    *   **Max Drawdown:** 11.71%
    *   **Equity Growth:** +416.60%

**Kesimpulan:** Strategi ini **sesuai klaim**. Memiliki Win Rate tinggi secara konsisten (di atas 65%), Drawdown yang terjaga (terutama di simulasi jangka pendek, max 11% dalam 1 tahun), dan growth ekuitas yang sangat solid. Layak dipertahankan.

## 2. Previous Day Breakout (PDH/PDL Breakout & Retest)
Strategi ini mengambil breakout dari area tertinggi/terendah hari sebelumnya. (Risk 1.5%, RR 1.5)

*   **Hasil 1 Bulan:**
    *   **Win Rate:** 58.33%
    *   **Max Drawdown:** 4.50%
    *   **Equity Growth:** +30.04%
*   **Hasil 1 Tahun:**
    *   **Win Rate:** 61.70%
    *   **Max Drawdown:** 12.24%
    *   **Equity Growth:** +838.71%

**Kesimpulan:** Strategi ini memiliki **Equity Growth sangat tinggi (luar biasa bagus)** dan max drawdown yang relatif rendah untuk return sebesar itu. Meskipun Win Rate tidak setinggi Bollinger Bands 2, namun di atas rata-rata (>60%). Sangat layak dipertahankan.

## 3. Strategi Overclaim: London/NY VWAP Pullback
Strategi ini sebelumnya diklaim di dokumen `STRATEGI_LONDON_NY_VWAP.md` memiliki Win Rate 68% dan drawdown 4.54%. Namun, setelah diuji pada data tahun 2023 (1 bulan & 1 tahun) murni, kinerjanya sangat buruk.

*   **Hasil 1 Tahun:**
    *   **Win Rate:** 44.75% (Jauh di bawah klaim 68%)
    *   **Max Drawdown:** 96.91% (Margin Call / Hancur)
    *   **Equity Growth:** -96.45% (Hampir habis modal)

**Kesimpulan:** Strategi ini **OVERCLAIM** ketika diuji di periode data yang berbeda. Ini menunjukkan *curve-fitting* berlebihan pada sampel laporan bawaannya, sehingga tidak robust untuk kondisi pasar secara umum. **Laporan overclaim ini patut dicatat.**

---

**Rekomendasi Utama:**
Gunakan **`bollinger_bands_2`** jika prioritas utama adalah **Win Rate tinggi & konsistensi** (Drawdown kecil).
Gunakan **`prev_day_breakout`** jika prioritas utama adalah **Equity Growth (Cuan maksimal)** dengan Win Rate yang masih positif (>50%) dan Drawdown terjaga (sekitar 10-12%).

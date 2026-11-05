# Adaptive Selective Entry (ASE) — GoldWave-inspired reconstruction

## Scope and attribution

ASE is an original, deterministic strategy inspired by the publicly described GoldWave architecture (market-regime selection, momentum quality, volatility filtering and adaptive exits). It does not reproduce GoldWave proprietary source code or undisclosed entry formula. No WR, growth or drawdown is claimed until independently backtested.

Designed primarily for XAUUSD M5. Signals are evaluated after a candle closes; entry is at the next candle open. The CSV timestamp basis is used for daily VWAP reset.

## Entry pipeline

1. **Donchian regime:** calculate upper/lower/mid from the previous N completed bars, excluding the signal candle. Channel midpoint must be non-decreasing for longs or non-increasing for shorts; close must be on the matching side of the midpoint.
2. **Volatility gate:** Wilder ATR; reject when Donchian width / ATR is outside the configured minimum and maximum.
3. **Momentum quality:** absolute candle body / full candle range must meet the minimum efficiency. Direction must agree with the regime.
4. **VWAP rejection:** daily cumulative VWAP uses typical price (H+L+C)/3 weighted by bar volume (fallback weight 1 when missing). Long: low touches/crosses VWAP and candle closes bullish above VWAP. Short is mirrored.
5. **Next-open entry:** apply adverse half-spread to the entry.
6. **Hard stop:** beyond the rejection candle extreme by SL buffer × ATR.
7. **Dynamic structural target:** previous Donchian upper for long / lower for short. Reject the setup unless remaining structural room is at least minimum RR × risk.
8. **Exit:** stop, structural target, or maximum holding bars. Same-bar SL/TP collision is resolved as SL first. One trade at a time; no grid, averaging, martingale, or position stacking.

## Default M5 parameters

| Parameter | Default |
|---|---:|
| Donchian period | 20 |
| ATR period | 14 |
| Minimum body efficiency | 0.55 |
| Minimum channel width / ATR | 1.00 |
| Maximum channel width / ATR | 8.00 |
| SL buffer | 0.25 ATR |
| Minimum structural RR | 1.20 |
| Maximum holding time | 24 bars |
| Adverse half-spread | 0.12 price units |

All ASE parameters are exposed in the Gold Tester UI and CLI for manual tuning.

## Important data and backtest limitations

- Daily VWAP is only as reliable as the volume field. Dukascopy XAUUSD volume is generally tick volume, not consolidated global gold traded volume.
- If timestamps are absent, the VWAP cannot reset by calendar day; use timestamped candles.
- OHLC bars cannot reveal intrabar order. The engine uses a pessimistic stop-first collision rule.
- The spread input is a fixed half-spread in price units, not a full dynamic broker spread/slippage model.
- A time-stop exit is marked to the final bar close with adverse exit cost.
- The generic EMA filter is disabled for ASE because it has its own regime and VWAP filters.
- Run on a separate holdout period and include commissions, variable spread and slippage before assessing live suitability.

## What to inspect

Compare ASE against existing Gold Tester strategies on the same XAUUSD M5 data and cost assumptions. Report WR, PF, net growth, balance DD, equity DD, trade count, average win/loss, exposure and monthly/quarterly stability. Do not optimize on the same sample used to report final performance.
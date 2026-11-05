// Dukascopy & Gold Sweep Lab Frontend Logic

document.addEventListener('DOMContentLoaded', async () => {
  // Navigation elements
  const navItems = document.querySelectorAll('.sidebar-nav .nav-item');
  const tabViews = document.querySelectorAll('.tab-view');
  const pageTitle = document.getElementById('pageTitle');
  const pageSubtitle = document.getElementById('pageSubtitle');
  const btnQuickOpenFolder = document.getElementById('btnQuickOpenFolder');
  const sidebarCapitalDisplay = document.getElementById('sidebarCapitalDisplay');
  const navTradeCountBadge = document.getElementById('navTradeCountBadge');

  // Downloader elements
  const symbolInput = document.getElementById('symbolInput');
  const pairChips = document.querySelectorAll('.chip-pair');
  const tfCheckboxes = document.querySelectorAll('input[name="timeframe"]');
  const btnOnlyTicks = document.getElementById('btnOnlyTicks');
  const btnOnlyM1M5 = document.getElementById('btnOnlyM1M5');
  const btnAllLTF = document.getElementById('btnAllLTF');
  const btnAllHTF = document.getElementById('btnAllHTF');
  const btnResetTF = document.getElementById('btnResetTF');

  const dateFromInput = document.getElementById('dateFrom');
  const dateToInput = document.getElementById('dateTo');
  const presetButtons = document.querySelectorAll('[data-preset]');

  const outputDirInput = document.getElementById('outputDir');
  const btnBrowseDir = document.getElementById('btnBrowseDir');
  const btnDownload = document.getElementById('btnDownload');
  const btnCancelDownload = document.getElementById('btnCancelDownload');

  const progressDlBar = document.getElementById('progressDlBar');
  const progressDlPercent = document.getElementById('progressDlPercent');
  const progressDlStatus = document.getElementById('progressDlStatus');
  const terminalDlLog = document.getElementById('terminalDlLog');
  const btnClearDlLog = document.getElementById('btnClearDlLog');

  const postDlBanner = document.getElementById('postDlBanner');
  const postDlFilename = document.getElementById('postDlFilename');
  const btnSendToTester = document.getElementById('btnSendToTester');

  // Backtester elements
  const btDataFile = document.getElementById('btDataFile');
  const btnRefreshCsvList = document.getElementById('btnRefreshCsvList');
  const btnBrowseCsvFile = document.getElementById('btnBrowseCsvFile');

  const btStrategy = document.getElementById('btStrategy');
  const strategyDesc = document.getElementById('strategyDesc');
  const btCapital = document.getElementById('btCapital');
  const btRiskPct = document.getElementById('btRiskPct');
  const btRR = document.getElementById('btRR');
  const btTimeframe = document.getElementById('btTimeframe');
  const btTrend = document.getElementById('btTrend');
  const btSwingStrength = document.getElementById('btSwingStrength');
  const btMinFvg = document.getElementById('btMinFvg');
  const btSlBuffer = document.getElementById('btSlBuffer');
  const btPullback = document.getElementById('btPullback');
  const btCloseConfirm = document.getElementById('btCloseConfirm');
  const btAseDonchian = document.getElementById('btAseDonchian');
  const btAseAtr = document.getElementById('btAseAtr');
  const btAseBody = document.getElementById('btAseBody');
  const btAseMinWidth = document.getElementById('btAseMinWidth');
  const btAseMaxWidth = document.getElementById('btAseMaxWidth');
  const btAseSlBuffer = document.getElementById('btAseSlBuffer');
  const btAseMinRr = document.getElementById('btAseMinRr');
  const btAseHold = document.getElementById('btAseHold');
  const btAseSpread = document.getElementById('btAseSpread');

  const btnRunBacktest = document.getElementById('btnRunBacktest');
  const btnCancelBacktest = document.getElementById('btnCancelBacktest');
  const terminalBtLog = document.getElementById('terminalBtLog');
  const btnClearBtLog = document.getElementById('btnClearBtLog');
  const btnOpenReportsFolder = document.getElementById('btnOpenReportsFolder');

  // Scorecard elements
  const scorecardContainer = document.getElementById('scorecardContainer');
  const resGrowthPct = document.getElementById('resGrowthPct');
  const resNetProfit = document.getElementById('resNetProfit');
  const resWinRate = document.getElementById('resWinRate');
  const resWinLossRatio = document.getElementById('resWinLossRatio');
  const resMaxDdPct = document.getElementById('resMaxDdPct');
  const resMaxDdAmt = document.getElementById('resMaxDdAmt');
  const resFinalBalance = document.getElementById('resFinalBalance');
  const resInitialBalance = document.getElementById('resInitialBalance');
  const resProfitFactor = document.getElementById('resProfitFactor');
  const resTotalTrades = document.getElementById('resTotalTrades');

  // Results Grid elements
  const btResultsGrid = document.getElementById('btResultsGrid');
  const equityCanvas = document.getElementById('equityCanvas');
  const chartTagText = document.getElementById('chartTagText');
  const tradesTableBody = document.getElementById('tradesTableBody');
  const tradeCountText = document.getElementById('tradeCountText');

  // Report elements
  const reportIframe = document.getElementById('reportIframe');
  const emptyReportPlaceholder = document.getElementById('emptyReportPlaceholder');
  const currentReportPath = document.getElementById('currentReportPath');
  const btnOpenReportExternal = document.getElementById('btnOpenReportExternal');
  const btnReloadReport = document.getElementById('btnReloadReport');

  // MT5 elements
  const btnDownloadSetFile = document.getElementById('btnDownloadSetFile');
  const btnCopySetFile = document.getElementById('btnCopySetFile');
  const setFilePreviewBox = document.getElementById('setFilePreviewBox');
  const btnCopyMql5 = document.getElementById('btnCopyMql5');
  const mql5CodeBox = document.getElementById('mql5CodeBox');

  // State
  let lastDownloadedFile = null;
  let lastBacktestResult = null;
  let strategiesData = [];

  // ==========================================
  // NAVIGATION HANDLER
  // ==========================================
  const tabTitles = {
    'tab-downloader': {
      title: 'Dukascopy Historical Data Downloader',
      sub: 'Download data harga presisi (Ticks, LTF, HTF) langsung dari Dukascopy Swiss'
    },
    'tab-backtester': {
      title: 'Gold & Forex Sweep Backtester Lab',
      sub: 'Simulasi strategi trading kuantitatif pada akun standar $10.000'
    },
    'tab-report': {
      title: 'Interactive Candlestick & Sweep Chart',
      sub: 'Visualisasi grafik candlestick resolusi tinggi lengkap dengan penandaan sweep dan FVG'
    },
    'tab-mt5': {
      title: 'Jembatan Adaptasi ke MetaTrader 5 (MQL5)',
      sub: 'Ekspor parameter teruji ke file .set dan salin blueprint logika Expert Advisor MQL5'
    }
  };

  function switchTab(tabId) {
    navItems.forEach(item => {
      item.classList.toggle('active', item.getAttribute('data-tab') === tabId);
    });
    tabViews.forEach(view => {
      view.classList.toggle('active', view.id === tabId);
    });

    if (tabTitles[tabId]) {
      pageTitle.textContent = tabTitles[tabId].title;
      pageSubtitle.textContent = tabTitles[tabId].sub;
    }
  }

  navItems.forEach(item => {
    item.addEventListener('click', () => {
      switchTab(item.getAttribute('data-tab'));
    });
  });

  btnQuickOpenFolder.addEventListener('click', async () => {
    await window.api.openDirectory(outputDirInput.value);
  });

  // Capital input listener
  btCapital.addEventListener('input', () => {
    const val = parseFloat(btCapital.value) || 10000;
    sidebarCapitalDisplay.textContent = `$${val.toLocaleString('id-ID', { minimumFractionDigits: 2 })}`;
  });

  // ==========================================
  // DOWNLOADER INITIALIZATION
  // ==========================================
  try {
    const defaultDir = await window.api.getDefaultDirectory();
    if (defaultDir) outputDirInput.value = defaultDir;
  } catch (e) {}

  function setDatePreset(type) {
    const now = new Date();
    const pad = (n) => String(n).padStart(2, '0');
    const formatDate = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;

    let from = new Date();
    let to = new Date();

    if (type === '7d') from.setDate(now.getDate() - 7);
    else if (type === '30d') from.setDate(now.getDate() - 30);
    else if (type === 'last-month') {
      from = new Date(now.getFullYear(), now.getMonth() - 1, 1);
      to = new Date(now.getFullYear(), now.getMonth(), 0);
    } else if (type === '1y') from.setFullYear(now.getFullYear() - 1);

    dateFromInput.value = formatDate(from);
    dateToInput.value = formatDate(to);
  }
  setDatePreset('30d');

  presetButtons.forEach(btn => {
    btn.addEventListener('click', () => {
      presetButtons.forEach(b => b.classList.remove('active-preset'));
      btn.classList.add('active-preset');
      setDatePreset(btn.getAttribute('data-preset'));
    });
  });

  pairChips.forEach(chip => {
    chip.addEventListener('click', () => {
      pairChips.forEach(c => c.classList.remove('active'));
      chip.classList.add('active');
      symbolInput.value = chip.getAttribute('data-symbol');
    });
  });

  symbolInput.addEventListener('input', () => {
    const val = symbolInput.value.trim().toLowerCase();
    pairChips.forEach(chip => {
      chip.classList.toggle('active', chip.getAttribute('data-symbol') === val);
    });
  });

  btnOnlyTicks.addEventListener('click', () => {
    tfCheckboxes.forEach(cb => { cb.checked = (cb.value === 'tick'); });
  });
  btnOnlyM1M5.addEventListener('click', () => {
    tfCheckboxes.forEach(cb => { cb.checked = (cb.value === 'm1' || cb.value === 'm5'); });
  });
  btnAllLTF.addEventListener('click', () => {
    const ltf = ['s1', 'm1', 'm5', 'm15', 'm30'];
    tfCheckboxes.forEach(cb => { cb.checked = ltf.includes(cb.value); });
  });
  btnAllHTF.addEventListener('click', () => {
    const htf = ['h1', 'h4', 'd1', 'mn1'];
    tfCheckboxes.forEach(cb => { cb.checked = htf.includes(cb.value); });
  });
  btnResetTF.addEventListener('click', () => {
    tfCheckboxes.forEach(cb => { cb.checked = false; });
  });

  btnBrowseDir.addEventListener('click', async () => {
    const sel = await window.api.selectDirectory(outputDirInput.value);
    if (sel) {
      outputDirInput.value = sel;
      await refreshCsvDropdown();
    }
  });

  function appendDlLog(text, type = 'info') {
    const line = document.createElement('div');
    line.className = `log-line log-${type}`;
    const time = new Date().toTimeString().split(' ')[0];
    line.textContent = `[${time}] ${text}`;
    terminalDlLog.appendChild(line);
    terminalDlLog.scrollTop = terminalDlLog.scrollHeight;
  }

  btnClearDlLog.addEventListener('click', () => { terminalDlLog.innerHTML = ''; });

  window.api.onDownloadLog(data => {
    appendDlLog(data.text, data.type || 'info');
  });

  window.api.onDownloadStatus(data => {
    if (data.progress !== undefined) {
      progressDlBar.style.width = `${data.progress}%`;
      progressDlPercent.textContent = `${data.progress}%`;
    }
    if (data.message) progressDlStatus.textContent = data.message;

    if (data.status === 'completed' || data.status === 'partial') {
      btnDownload.style.display = 'flex';
      btnCancelDownload.style.display = 'none';

      if (data.downloadedFiles && data.downloadedFiles.length > 0) {
        lastDownloadedFile = data.downloadedFiles[0];
        postDlFilename.textContent = lastDownloadedFile.split(/[\\/]/).pop();
        postDlBanner.style.display = 'flex';
        refreshCsvDropdown(lastDownloadedFile);
      }
    } else if (data.status === 'cancelled') {
      btnDownload.style.display = 'flex';
      btnCancelDownload.style.display = 'none';
    }
  });

  btnDownload.addEventListener('click', async () => {
    const instrument = symbolInput.value.trim().toLowerCase();
    const selectedTfs = Array.from(tfCheckboxes).filter(cb => cb.checked).map(cb => cb.value);

    if (!instrument) { alert('Pilih atau ketik instrumen pair!'); return; }
    if (selectedTfs.length === 0) { alert('Pilih minimal satu timeframe!'); return; }

    btnDownload.style.display = 'none';
    btnCancelDownload.style.display = 'flex';
    postDlBanner.style.display = 'none';
    progressDlBar.style.width = '0%';
    progressDlPercent.textContent = '0%';

    appendDlLog(`Memulai download ${instrument.toUpperCase()} [${selectedTfs.join(', ')}]...`, 'cmd');

    await window.api.startDownload({
      instrument,
      timeframes: selectedTfs,
      dateFrom: dateFromInput.value,
      dateTo: dateToInput.value,
      priceType: 'bid',
      volumes: true,
      directory: outputDirInput.value
    });
  });

  btnCancelDownload.addEventListener('click', async () => {
    await window.api.cancelDownload();
  });

  btnSendToTester.addEventListener('click', () => {
    switchTab('tab-backtester');
    if (lastDownloadedFile) {
      btDataFile.value = lastDownloadedFile;
      // Auto-detect timeframe from filename if available
      const fname = lastDownloadedFile.toLowerCase();
      if (fname.includes('_m1.') || fname.includes('-m1.')) btTimeframe.value = 'M1';
      else if (fname.includes('_m5.') || fname.includes('-m5.')) btTimeframe.value = 'M5';
      else if (fname.includes('_m15.') || fname.includes('-m15.')) btTimeframe.value = 'M15';
      else if (fname.includes('_h1.') || fname.includes('-h1.')) btTimeframe.value = 'H1';
    }
  });

  // ==========================================
  // BACKTESTER INITIALIZATION
  // ==========================================
  async function loadStrategies() {
    try {
      strategiesData = await window.api.getStrategies();
      btStrategy.innerHTML = '';
      strategiesData.forEach(st => {
        const opt = document.createElement('option');
        opt.value = st.id;
        opt.textContent = `${st.name} — ${st.description}`;
        btStrategy.appendChild(opt);
      });
      updateStrategyDescription();
    } catch (e) {
      console.error('Failed to load strategies', e);
    }
  }

  function updateStrategyDescription() {
    const selectedId = btStrategy.value;
    const st = strategiesData.find(s => s.id === selectedId);
    if (st) {
      strategyDesc.textContent = `💡 ${st.name}: ${st.description}`;
    }

    // Some strategies have a target that is part of the tested edge.  Lock the
    // RR input so the global 2.0R default cannot silently disagree with them.
    const fixedRrMap = {
      doji_ride: {
        value: '0.4',
        title: 'Strategi Doji Ride memakai target 0.40R terkalibrasi (WR 84.0%).'
      },
      liquidity_bubble_trap: {
        value: '0.85',
        title: 'Strategi ini memakai target 0.85R terkalibrasi (WR 80.8%).'
      },
      london_ny_vwap_pullback: {
        value: '1.0',
        title: 'Strategi ini memakai target 1:1 internal (1.25 x ATR).'
      },
      volume_profile_failed_auction: {
        value: '0.5',
        title: 'Strategi ini memakai target 0.5R internal; RR tidak dapat diubah.'
      }
    };
    const fixedRr = fixedRrMap[selectedId];
    if (fixedRr) {
      if (!btRR.disabled) btRR.dataset.previousValue = btRR.value;
      btRR.value = fixedRr.value;
      btRR.disabled = true;
      btRR.title = fixedRr.title;
    } else if (btRR.disabled) {
      btRR.value = btRR.dataset.previousValue || '2.0';
      btRR.disabled = false;
      btRR.title = '';
    }
  }

  btStrategy.addEventListener('change', updateStrategyDescription);

  async function refreshCsvDropdown(selectPath = null) {
    try {
      const files = await window.api.getCsvFiles(outputDirInput.value);
      btDataFile.innerHTML = '';
      if (files.length === 0) {
        const opt = document.createElement('option');
        opt.value = '';
        opt.textContent = '-- Belum ada file CSV di folder --';
        btDataFile.appendChild(opt);
        return;
      }

      files.forEach(f => {
        const opt = document.createElement('option');
        opt.value = f.path;
        opt.textContent = `${f.name} (${f.sizeKb} KB)`;
        btDataFile.appendChild(opt);
      });

      if (selectPath) {
        btDataFile.value = selectPath;
      }
    } catch (e) {
      console.error('Failed to list CSV files', e);
    }
  }

  btnRefreshCsvList.addEventListener('click', () => refreshCsvDropdown());
  btnBrowseCsvFile.addEventListener('click', async () => {
    const file = await window.api.selectFile(outputDirInput.value);
    if (file) {
      await refreshCsvDropdown(file);
      btDataFile.value = file;
    }
  });

  function appendBtLog(text, type = 'info') {
    const line = document.createElement('div');
    line.className = `log-line log-${type}`;
    const time = new Date().toTimeString().split(' ')[0];
    line.textContent = `[${time}] ${text}`;
    terminalBtLog.appendChild(line);
    terminalBtLog.scrollTop = terminalBtLog.scrollHeight;
  }

  btnClearBtLog.addEventListener('click', () => { terminalBtLog.innerHTML = ''; });

  if (btnOpenReportsFolder) {
    btnOpenReportsFolder.addEventListener('click', async () => {
      // Open the reports directory in File Explorer
      const defDir = await window.api.getDefaultDirectory();
      // Reports directory is inside the app directory
      await window.api.openDirectory('D:\\CSV\\dukascopy-downloader\\reports');
    });
  }

  window.api.onBacktestLog(data => {
    appendBtLog(data.text, data.type || 'info');
  });

  // Run Backtest
  btnRunBacktest.addEventListener('click', async () => {
    const file = btDataFile.value;
    if (!file) {
      alert('Pilih file CSV candle terlebih dahulu!');
      return;
    }

    const capital = parseFloat(btCapital.value) || 10000;
    const riskPct = parseFloat(btRiskPct.value) || 1.0;
    const rr = parseFloat(btRR.value) || 2.0;
    const strategy = btStrategy.value;
    const timeframe = btTimeframe.value;
    const trend = btTrend.value;
    const swingStrength = parseInt(btSwingStrength.value, 10) || 5;
    const minFvg = parseFloat(btMinFvg.value) || 0.5;
    const slBuffer = parseFloat(btSlBuffer ? btSlBuffer.value : 0.0) || 0.0;
    const pullback = parseInt(btPullback ? btPullback.value : 10, 10) || 10;
    const closeConfirm = btCloseConfirm.checked;
    const aseDonchianPeriod = Number.parseInt(btAseDonchian.value, 10) || 20;
    const aseAtrPeriod = Number.parseInt(btAseAtr.value, 10) || 14;
    const aseMinBodyEfficiency = Number.parseFloat(btAseBody.value) || 0.55;
    const aseMinChannelAtr = Number.parseFloat(btAseMinWidth.value) || 1.0;
    const aseMaxChannelAtr = Number.parseFloat(btAseMaxWidth.value) || 8.0;
    const aseSlAtrBuffer = Number.parseFloat(btAseSlBuffer.value) || 0.25;
    const aseMinRr = Number.parseFloat(btAseMinRr.value) || 1.2;
    const aseMaxHoldBars = Number.parseInt(btAseHold.value, 10) || 24;
    const aseHalfSpread = Number.parseFloat(btAseSpread.value) || 0.12;

    btnRunBacktest.style.display = 'none';
    btnCancelBacktest.style.display = 'inline-flex';
    scorecardContainer.style.display = 'none';
    btResultsGrid.style.display = 'none';

    appendBtLog(`Memulai simulasi: ${strategy} pada ${file.split(/[\\/]/).pop()}...`, 'cmd');

    try {
      const result = await window.api.runBacktest({
        file,
        strategy,
        capital,
        riskPct,
        rr,
        timeframe,
        trend,
        swingStrength,
        minFvg,
        slBuffer,
        pullback,
        closeConfirm,
        aseDonchianPeriod,
        aseAtrPeriod,
        aseMinBodyEfficiency,
        aseMinChannelAtr,
        aseMaxChannelAtr,
        aseSlAtrBuffer,
        aseMinRr,
        aseMaxHoldBars,
        aseHalfSpread
      });

      btnRunBacktest.style.display = 'inline-flex';
      btnCancelBacktest.style.display = 'none';

      if (result.success && result.summary) {
        lastBacktestResult = result;
        renderResults(result);
      } else {
        alert(result.message || 'Backtest tidak menghasilkan data.');
      }
    } catch (err) {
      btnRunBacktest.style.display = 'inline-flex';
      btnCancelBacktest.style.display = 'none';
      alert(`Error backtest: ${err.message}`);
    }
  });

  btnCancelBacktest.addEventListener('click', async () => {
    await window.api.cancelBacktest();
    btnRunBacktest.style.display = 'inline-flex';
    btnCancelBacktest.style.display = 'none';
  });

  // ==========================================
  // RENDER RESULTS & SCORECARD
  // ==========================================
  function renderResults(data) {
    const s = data.summary;

    // Show containers
    scorecardContainer.style.display = 'grid';
    btResultsGrid.style.display = 'grid';

    // Badge trade count
    navTradeCountBadge.style.display = 'inline-block';
    navTradeCountBadge.textContent = s.total_trades;

    // Growth Card
    const sign = s.net_profit >= 0 ? '+' : '';
    resGrowthPct.textContent = `${sign}${s.growth_pct.toFixed(2)}%`;
    resGrowthPct.style.color = s.growth_pct >= 0 ? 'var(--accent-green)' : 'var(--accent-rose)';
    resNetProfit.textContent = `${sign}$${Math.abs(s.net_profit).toLocaleString('id-ID', { minimumFractionDigits: 2 })} Net PnL`;

    // Win Rate Card
    resWinRate.textContent = `${s.win_rate.toFixed(1)}%`;
    resWinLossRatio.textContent = `${s.wins} Win / ${s.losses} Loss (${s.unresolved || 0} Open)`;

    // Max Drawdown Card
    resMaxDdPct.textContent = `-${s.max_drawdown_pct.toFixed(2)}%`;
    resMaxDdAmt.textContent = `-$${s.max_drawdown_amount.toLocaleString('id-ID', { minimumFractionDigits: 2 })} Peak Drawdown`;

    // Balance Card
    resFinalBalance.textContent = `$${s.final_balance.toLocaleString('id-ID', { minimumFractionDigits: 2 })}`;
    resInitialBalance.textContent = `Dari Modal Awal: $${s.initial_balance.toLocaleString('id-ID')}`;

    // Profit Factor
    resProfitFactor.textContent = s.profit_factor >= 999 ? '∞' : s.profit_factor.toFixed(2);
    resTotalTrades.textContent = `Total: ${s.total_trades} Trades`;

    // Chart tag
    chartTagText.textContent = `Modal $${s.initial_balance.toLocaleString('id-ID')} ➔ Saldo $${s.final_balance.toLocaleString('id-ID')}`;
    tradeCountText.textContent = `${s.trades.length} Transaksi`;

    // Draw Equity Chart
    drawEquityCurve(s.equity_curve, s.initial_balance);

    // Populate Trade Log Table
    tradesTableBody.innerHTML = '';
    s.trades.forEach(t => {
      const row = document.createElement('tr');
      const isWin = t.verdict === 'WIN' || t.r_multiple > 0;
      const isLong = t.direction === 'LONG';
      const pnlSign = t.pnl >= 0 ? '+' : '';

      row.innerHTML = `
        <td>${t.id}</td>
        <td>${t.time}</td>
        <td><span class="${isLong ? 'badge-long' : 'badge-short'}">${t.direction}</span></td>
        <td>${t.entry_price.toFixed(2)}</td>
        <td>${t.stop_loss.toFixed(2)}</td>
        <td>${t.take_profit.toFixed(2)}</td>
        <td><span class="${isWin ? 'badge-win' : 'badge-loss'}">${t.verdict}</span></td>
        <td style="color: ${isWin ? 'var(--accent-green)' : 'var(--accent-rose)'}; font-weight: 600;">
          ${pnlSign}$${t.pnl.toFixed(2)}
        </td>
        <td>$${t.balance.toLocaleString('id-ID', { minimumFractionDigits: 2 })}</td>
      `;
      tradesTableBody.appendChild(row);
    });

    // Update Report Iframe
    if (data.report_file) {
      reportIframe.src = `file://${data.report_file.replace(/\\/g, '/')}`;
      reportIframe.style.display = 'block';
      emptyReportPlaceholder.style.display = 'none';
      currentReportPath.textContent = data.report_file;
    }

    // Update MT5 Tab
    if (data.set_content && setFilePreviewBox) {
      setFilePreviewBox.textContent = data.set_content;
    }
    if (data.mql5_blueprint) {
      mql5CodeBox.textContent = data.mql5_blueprint;
    }
  }

  // Draw Smooth Canvas Chart
  function drawEquityCurve(points, initial) {
    if (!points || points.length === 0) return;
    const ctx = equityCanvas.getContext('2d');
    const width = equityCanvas.width;
    const height = equityCanvas.height;

    ctx.clearRect(0, 0, width, height);

    // Padding
    const padX = 50;
    const padY = 30;
    const plotW = width - padX * 1.5;
    const plotH = height - padY * 2;

    const values = points.map(p => p.balance);
    const minVal = Math.min(...values, initial * 0.98);
    const maxVal = Math.max(...values, initial * 1.02);
    const range = (maxVal - minVal) || 1;

    const getX = (idx) => padX + (idx / (points.length - 1 || 1)) * plotW;
    const getY = (val) => padY + plotH - ((val - minVal) / range) * plotH;

    // Draw grid lines
    ctx.strokeStyle = '#1e293b';
    ctx.lineWidth = 1;
    ctx.font = '10px Consolas, monospace';
    ctx.fillStyle = '#64748b';

    const gridSteps = 4;
    for (let i = 0; i <= gridSteps; i++) {
      const gridVal = minVal + (range / gridSteps) * i;
      const y = getY(gridVal);
      ctx.beginPath();
      ctx.moveTo(padX, y);
      ctx.lineTo(padX + plotW, y);
      ctx.stroke();
      ctx.fillText(`$${Math.round(gridVal)}`, 5, y + 3);
    }

    // Initial Balance baseline (dotted amber)
    const initY = getY(initial);
    ctx.save();
    ctx.setLineDash([4, 4]);
    ctx.strokeStyle = 'rgba(245, 158, 11, 0.5)';
    ctx.beginPath();
    ctx.moveTo(padX, initY);
    ctx.lineTo(padX + plotW, initY);
    ctx.stroke();
    ctx.restore();

    // Area fill gradient
    const grad = ctx.createLinearGradient(0, padY, 0, padY + plotH);
    grad.addColorStop(0, 'rgba(16, 185, 129, 0.3)');
    grad.addColorStop(1, 'rgba(14, 165, 233, 0.0)');

    ctx.beginPath();
    ctx.moveTo(getX(0), getY(points[0].balance));
    for (let i = 1; i < points.length; i++) {
      ctx.lineTo(getX(i), getY(points[i].balance));
    }
    ctx.lineTo(getX(points.length - 1), padY + plotH);
    ctx.lineTo(getX(0), padY + plotH);
    ctx.closePath();
    ctx.fillStyle = grad;
    ctx.fill();

    // Line curve
    ctx.beginPath();
    ctx.moveTo(getX(0), getY(points[0].balance));
    for (let i = 1; i < points.length; i++) {
      ctx.lineTo(getX(i), getY(points[i].balance));
    }
    ctx.strokeStyle = '#10b981';
    ctx.lineWidth = 2.5;
    ctx.stroke();

    // Draw end point marker
    const lastX = getX(points.length - 1);
    const lastY = getY(points[points.length - 1].balance);
    ctx.beginPath();
    ctx.arc(lastX, lastY, 4, 0, Math.PI * 2);
    ctx.fillStyle = '#fff';
    ctx.fill();
    ctx.strokeStyle = '#10b981';
    ctx.lineWidth = 2;
    ctx.stroke();
  }

  // ==========================================
  // REPORT TAB HANDLERS
  // ==========================================
  btnOpenReportExternal.addEventListener('click', async () => {
    if (lastBacktestResult && lastBacktestResult.report_file) {
      await window.api.openFileExternal(lastBacktestResult.report_file);
    } else {
      alert('Belum ada laporan yang tersedia.');
    }
  });

  btnReloadReport.addEventListener('click', () => {
    if (reportIframe.src) {
      const src = reportIframe.src;
      reportIframe.src = '';
      setTimeout(() => { reportIframe.src = src; }, 100);
    }
  });

  // ==========================================
  // MT5 TAB HANDLERS
  // ==========================================
  btnDownloadSetFile.addEventListener('click', async () => {
    if (!lastBacktestResult) {
      alert('Jalankan backtest terlebih dahulu untuk mendapatkan file konfigurasi parameter!');
      return;
    }

    const strategy = lastBacktestResult.strategy || 'sweep_strategy';
    const params = lastBacktestResult.params || {};

    const content = lastBacktestResult.set_content || [
      '; ===========================================================',
      `; MT5 EA Configuration: ${strategy.toUpperCase()}`,
      `; Generated by Dukascopy & Gold Sweep Lab`,
      `; Date: ${new Date().toISOString()}`,
      '; ===========================================================',
      `InpStrategyName=${strategy}`,
      `InpInitialCapital=${params.capital || 10000}`,
      `InpRiskPercent=${params.risk_pct || 1.0}`,
      `InpRewardRiskRatio=${params.rr || 2.0}`,
      `InpSwingStrength=${params.swing_strength || 5}`,
      `InpMinFVGPoints=${params.min_fvg || 0.5}`,
      `InpTrendFilter=${params.trend || 'ema'}`,
      `InpCloseConfirmation=${params.close_confirm ? 1 : 0}`,
      `InpMagicNumber=999888`
    ].join('\r\n');

    const res = await window.api.saveFileAs({
      defaultName: `${strategy}_xauusd.set`,
      content
    });

    if (res.success) {
      alert(`File .set berhasil disimpan ke:\n${res.path}`);
    }
  });

  if (btnCopySetFile && setFilePreviewBox) {
    btnCopySetFile.addEventListener('click', () => {
      navigator.clipboard.writeText(setFilePreviewBox.textContent);
      btnCopySetFile.textContent = '✅ Berhasil Disalin!';
      setTimeout(() => { btnCopySetFile.textContent = '📋 Salin Teks .set'; }, 2000);
    });
  }

  btnCopyMql5.addEventListener('click', () => {
    navigator.clipboard.writeText(mql5CodeBox.textContent);
    btnCopyMql5.textContent = '✅ Berhasil Disalin!';
    setTimeout(() => { btnCopyMql5.textContent = '📋 Salin Kode MQL5'; }, 2000);
  });

  // Initial load
  await loadStrategies();
  await refreshCsvDropdown();
});

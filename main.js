const { app, BrowserWindow, ipcMain, dialog, shell } = require('electron');
const path = require('path');
const { spawn } = require('child_process');
const fs = require('fs');

let mainWindow = null;
let activeDownloadProcess = null;
let activeBacktestProcess = null;

function createWindow() {
  mainWindow = new BrowserWindow({
    width: 1240,
    height: 900,
    minWidth: 1000,
    minHeight: 700,
    backgroundColor: '#0a0e17',
    icon: path.join(__dirname, 'assets', 'icon.png'),
    webPreferences: {
      preload: path.join(__dirname, 'preload.js'),
      nodeIntegration: false,
      contextIsolation: true,
      sandbox: false,
      webviewTag: true
    },
    autoHideMenuBar: true
  });

  mainWindow.loadFile(path.join(__dirname, 'renderer', 'index.html'));

  mainWindow.on('closed', () => {
    mainWindow = null;
    if (activeDownloadProcess) {
      try { activeDownloadProcess.kill(); } catch (e) {}
    }
    if (activeBacktestProcess) {
      try { activeBacktestProcess.kill(); } catch (e) {}
    }
  });
}

app.whenReady().then(() => {
  createWindow();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});

// IPC: Select directory
ipcMain.handle('select-directory', async (event, defaultPath) => {
  const result = await dialog.showOpenDialog(mainWindow, {
    title: 'Pilih Folder Simpan CSV',
    defaultPath: defaultPath || 'D:\\CSV',
    properties: ['openDirectory', 'createDirectory']
  });

  if (!result.canceled && result.filePaths.length > 0) {
    return result.filePaths[0];
  }
  return null;
});

// IPC: Select file
ipcMain.handle('select-file', async (event, defaultPath) => {
  const result = await dialog.showOpenDialog(mainWindow, {
    title: 'Pilih File CSV Candle',
    defaultPath: defaultPath || 'D:\\CSV',
    filters: [{ name: 'CSV Files', extensions: ['csv'] }],
    properties: ['openFile']
  });

  if (!result.canceled && result.filePaths.length > 0) {
    return result.filePaths[0];
  }
  return null;
});

// IPC: Open directory in File Explorer
ipcMain.handle('open-directory', async (event, dirPath) => {
  if (dirPath && fs.existsSync(dirPath)) {
    shell.openPath(dirPath);
    return true;
  }
  return false;
});

// IPC: Open file in default external application
ipcMain.handle('open-file-external', async (event, filePath) => {
  if (filePath && fs.existsSync(filePath)) {
    shell.openPath(filePath);
    return true;
  }
  return false;
});

// IPC: Get default directory
ipcMain.handle('get-default-directory', () => {
  const defaultDir = 'D:\\CSV';
  if (fs.existsSync(defaultDir)) {
    return defaultDir;
  }
  return app.getPath('documents');
});

// IPC: Scan for CSV files in directory
ipcMain.handle('get-csv-files', async (event, dirPath) => {
  const targetDir = dirPath || 'D:\\CSV';
  if (!fs.existsSync(targetDir)) {
    return [];
  }
  try {
    const files = fs.readdirSync(targetDir);
    const csvFiles = files
      .filter(f => f.toLowerCase().endsWith('.csv'))
      .map(f => {
        const full = path.join(targetDir, f);
        const stats = fs.statSync(full);
        return {
          name: f,
          path: full,
          sizeKb: Math.round(stats.size / 1024),
          modified: stats.mtime
        };
      })
      .sort((a, b) => b.modified - a.modified);
    return csvFiles;
  } catch (err) {
    return [];
  }
});

// IPC: Get Strategy List from Python
ipcMain.handle('get-strategies', async () => {
  return new Promise((resolve) => {
    const runnerScript = path.join(__dirname, 'engine', 'backtest_runner.py');
    const py = spawn('python', [runnerScript, '--list-strategies'], {
      cwd: path.join(__dirname, 'engine')
    });

    let output = '';
    py.stdout.on('data', chunk => { output += chunk.toString(); });
    py.on('close', code => {
      try {
        const list = JSON.parse(output);
        resolve(list);
      } catch (e) {
        // Fallback default strategies
        resolve([
          { id: 'doji_ride', name: 'Doji Ride', description: 'Structural Liquidity Sweep & Doji Absorption Breakout (WR 84.0%, DD < 3.0%)' },
          { id: 'liquidity_bubble_trap', name: 'Liquidity Bubble Trap', description: 'Bookmap Volume Bubble + Swing Sweep Absorption (WR 80.8%, DD < 3.8%)' },
          { id: 'liquidity_imbalance', name: 'Liquidity Imbalance', description: 'Liquidity Sweep + Fair Value Gap (FVG) confirmation' },
          { id: 'prev_day_breakout', name: 'Prev Day Breakout', description: 'Previous Day High/Low (PDH/PDL) Breakout & Retest' },
          { id: 'orb', name: 'Orb', description: 'Opening Range Breakout (ORB) on session open' },
          { id: 'ict_fvg', name: 'Ict Fvg', description: 'ICT Fair Value Gap entry with market structure shift' },
          { id: 'smart_money', name: 'Smart Money', description: 'Smart Money Concepts (SMC) CHoCH & Liquidity Purge' }
        ]);
      }
    });
    py.on('error', () => {
      resolve([]);
    });
  });
});

// IPC: Start Download from Dukascopy
ipcMain.handle('start-download', async (event, options) => {
  const {
    instrument,
    timeframes,
    dateFrom,
    dateTo,
    priceType = 'bid',
    volumes = true,
    dateFormat = 'YYYY-MM-DD HH:mm:ss',
    directory = 'D:\\CSV',
    flats = false
  } = options;

  if (!instrument || !timeframes || timeframes.length === 0) {
    return { success: false, message: 'Instrumen dan Timeframe harus dipilih' };
  }

  if (!fs.existsSync(directory)) {
    try {
      fs.mkdirSync(directory, { recursive: true });
    } catch (err) {
      return { success: false, message: `Gagal membuat folder: ${err.message}` };
    }
  }

  const cliPath = path.join(__dirname, 'node_modules', 'dukascopy-node', 'dist', 'cli', 'index.js');
  if (!fs.existsSync(cliPath)) {
    return { success: false, message: 'Modul dukascopy-node CLI tidak ditemukan' };
  }

  const total = timeframes.length;
  let completed = 0;
  let failed = 0;
  let downloadedFiles = [];

  for (let i = 0; i < timeframes.length; i++) {
    const tf = timeframes[i];
    const progressPercent = Math.round((i / total) * 100);

    mainWindow.webContents.send('download-status', {
      status: 'downloading',
      progress: progressPercent,
      currentTf: tf,
      currentStep: i + 1,
      totalSteps: total,
      message: `Mengunduh ${instrument.toUpperCase()} [${tf}] (${i + 1}/${total})...`
    });

    const expectedName = `${instrument.toLowerCase()}_${tf}.csv`;
    const args = [
      cliPath,
      '-i', instrument.toLowerCase(),
      '-from', dateFrom,
      '-to', dateTo,
      '-t', tf,
      '-f', 'csv',
      '-p', priceType,
      '-dir', directory,
      '-fn', expectedName
    ];

    if (volumes) args.push('-v');
    if (flats) args.push('-fl');
    if (dateFormat) args.push('-df', dateFormat);

    mainWindow.webContents.send('download-log', {
      type: 'cmd',
      text: `> Mengambil data: ${instrument.toUpperCase()} | TF: ${tf} | Rentang: ${dateFrom} s/d ${dateTo}`
    });

    try {
      const result = await runDownloadProcess(args);
      if (result.success) {
        completed++;
        // Check created file (might have appended .csv)
        const fullP = path.join(directory, expectedName);
        const altP = path.join(directory, expectedName + '.csv');
        let finalPath = fullP;
        if (fs.existsSync(altP)) {
          try {
            if (fs.existsSync(fullP)) fs.unlinkSync(fullP);
            fs.renameSync(altP, fullP);
          } catch(e) { finalPath = altP; }
        }
        downloadedFiles.push(finalPath);

        mainWindow.webContents.send('download-log', {
          type: 'success',
          text: `[OK] Berhasil mengunduh ${instrument.toUpperCase()} [${tf}] ke: ${finalPath}`
        });
      } else {
        failed++;
        mainWindow.webContents.send('download-log', {
          type: 'error',
          text: `[GAGAL] ${tf}: ${result.error || 'Terjadi kesalahan'}`
        });
      }
    } catch (err) {
      if (err.message === 'CANCELLED') {
        mainWindow.webContents.send('download-log', {
          type: 'warning',
          text: 'Download dibatalkan oleh pengguna.'
        });
        mainWindow.webContents.send('download-status', {
          status: 'cancelled',
          progress: progressPercent,
          message: 'Download dibatalkan'
        });
        return { success: false, cancelled: true };
      }
      failed++;
      mainWindow.webContents.send('download-log', {
        type: 'error',
        text: `[ERROR] ${tf}: ${err.message}`
      });
    }
  }

  const allSuccess = failed === 0;
  mainWindow.webContents.send('download-status', {
    status: allSuccess ? 'completed' : 'partial',
    progress: 100,
    message: allSuccess
      ? `Semua selesai! ${completed} file berhasil diunduh.`
      : `Selesai: ${completed} berhasil, ${failed} gagal.`,
    downloadedFiles
  });

  return { success: allSuccess, completed, failed, downloadedFiles };
});

function runDownloadProcess(args) {
  return new Promise((resolve, reject) => {
    activeDownloadProcess = spawn('node', args, {
      windowsHide: true,
      cwd: __dirname
    });

    let stdoutData = '';
    let stderrData = '';

    activeDownloadProcess.stdout.on('data', chunk => {
      const str = chunk.toString();
      stdoutData += str;
      const cleanLines = str.split(/\r?\n/).filter(line => line.trim().length > 0);
      cleanLines.forEach(line => {
        mainWindow.webContents.send('download-log', { type: 'info', text: line });
      });
    });

    activeDownloadProcess.stderr.on('data', chunk => {
      const str = chunk.toString();
      stderrData += str;
      const cleanLines = str.split(/\r?\n/).filter(line => line.trim().length > 0);
      cleanLines.forEach(line => {
        mainWindow.webContents.send('download-log', { type: 'warning', text: line });
      });
    });

    activeDownloadProcess.on('close', code => {
      activeDownloadProcess = null;
      if (code === 0) {
        resolve({ success: true, output: stdoutData });
      } else {
        resolve({ success: false, error: stderrData || `Exit code ${code}` });
      }
    });

    activeDownloadProcess.on('error', err => {
      activeDownloadProcess = null;
      reject(err);
    });
  });
}

// IPC: Cancel download
ipcMain.handle('cancel-download', () => {
  if (activeDownloadProcess) {
    try {
      activeDownloadProcess.kill('SIGTERM');
      activeDownloadProcess = null;
      return true;
    } catch (e) {
      return false;
    }
  }
  return false;
});

// IPC: Run Backtest
ipcMain.handle('run-backtest', async (event, options) => {
  const {
    file,
    strategy = 'liquidity_imbalance',
    capital = 10000.0,
    riskPct = 1.0,
    rr = 2.0,
    timeframe = 'M5',
    trend = 'ema',
    swingStrength = 5,
    minFvg = 0.5,
    slBuffer = 0.0,
    pullback = 10,
    closeConfirm = false
  } = options;

  if (!file || !fs.existsSync(file)) {
    return { success: false, message: `File CSV tidak ditemukan: ${file}` };
  }

  const reportsDir = path.join(__dirname, 'reports');
  if (!fs.existsSync(reportsDir)) {
    fs.mkdirSync(reportsDir, { recursive: true });
  }

  const timestamp = Date.now();
  const reportPath = path.join(reportsDir, `report_${strategy}_${timestamp}.html`);
  const jsonPath = path.join(reportsDir, `result_${strategy}_${timestamp}.json`);
  const setPath = path.join(reportsDir, `strategy_${strategy}_${timestamp}.set`);

  const runnerScript = path.join(__dirname, 'engine', 'backtest_runner.py');

  const args = [
    runnerScript,
    '--file', file,
    '--strategy', strategy,
    '--capital', String(capital),
    '--risk-pct', String(riskPct),
    '--rr', String(rr),
    '--timeframe', timeframe,
    '--trend', trend,
    '--swing-strength', String(swingStrength),
    '--min-fvg', String(minFvg),
    '--sl-buffer', String(slBuffer),
    '--pullback', String(pullback),
    '--report-out', reportPath,
    '--json-out', jsonPath,
    '--set-out', setPath
  ];

  if (closeConfirm) {
    args.push('--close-confirm');
  }

  mainWindow.webContents.send('backtest-log', {
    type: 'cmd',
    text: `> Memulai Backtest: Strategi [${strategy}] | Data: ${path.basename(file)} | Modal: $${capital.toLocaleString()} | Risk: ${riskPct}% | RR: ${rr}`
  });

  return new Promise((resolve) => {
    activeBacktestProcess = spawn('python', args, {
      cwd: path.join(__dirname, 'engine'),
      windowsHide: true
    });

    let fullOutput = '';
    let errorOutput = '';

    activeBacktestProcess.stdout.on('data', chunk => {
      const str = chunk.toString();
      fullOutput += str;
      const cleanLines = str.split(/\r?\n/).filter(line => line.trim().length > 0);
      cleanLines.forEach(line => {
        if (!line.startsWith('{"success"') && !line.startsWith('__JSON_')) {
          mainWindow.webContents.send('backtest-log', { type: 'info', text: line });
        }
      });
    });

    activeBacktestProcess.stderr.on('data', chunk => {
      const str = chunk.toString();
      errorOutput += str;
      const cleanLines = str.split(/\r?\n/).filter(line => line.trim().length > 0);
      cleanLines.forEach(line => {
        mainWindow.webContents.send('backtest-log', { type: 'warning', text: line });
      });
    });

    activeBacktestProcess.on('close', code => {
      activeBacktestProcess = null;
      if (code === 0 && fs.existsSync(jsonPath)) {
        try {
          const raw = fs.readFileSync(jsonPath, 'utf8');
          const data = JSON.parse(raw);
          if (fs.existsSync(setPath)) {
            data.set_content = fs.readFileSync(setPath, 'utf8');
          }

          // Append to persistent history log
          try {
            const historyLogPath = path.join(reportsDir, 'history.log');
            const now = new Date();
            const timeStr = now.getFullYear() + '-' +
              String(now.getMonth() + 1).padStart(2, '0') + '-' +
              String(now.getDate()).padStart(2, '0') + ' ' +
              String(now.getHours()).padStart(2, '0') + ':' +
              String(now.getMinutes()).padStart(2, '0') + ':' +
              String(now.getSeconds()).padStart(2, '0');
            const logEntry = `[${timeStr}] Strategy: ${data.strategy.padEnd(20)} | TF: ${data.timeframe.padEnd(3)} | Growth: ${(data.summary.growth_pct >= 0 ? '+' : '') + data.summary.growth_pct.toFixed(2)}% | WR: ${data.summary.win_rate.toFixed(1)}% | DD: -${data.summary.max_drawdown_pct.toFixed(2)}% | Trades: ${String(data.summary.total_trades).padEnd(3)} | PnL: $${data.summary.net_profit.toFixed(2)}\n`;
            fs.appendFileSync(historyLogPath, logEntry, 'utf8');
          } catch (e) {}

          mainWindow.webContents.send('backtest-log', {
            type: 'success',
            text: `[SELESAI] Backtest sukses! Growth: ${data.summary.growth_pct > 0 ? '+' : ''}${data.summary.growth_pct}% | WR: ${data.summary.win_rate}% | Max DD: -${data.summary.max_drawdown_pct}%`
          });
          resolve(data);
        } catch (e) {
          resolve({ success: false, message: `Gagal membaca hasil JSON: ${e.message}` });
        }
      } else {
        mainWindow.webContents.send('backtest-log', {
          type: 'error',
          text: `[GAGAL] Backtest gagal dengan exit code ${code}: ${errorOutput}`
        });
        resolve({ success: false, message: errorOutput || `Process exited with code ${code}` });
      }
    });

    activeBacktestProcess.on('error', err => {
      activeBacktestProcess = null;
      mainWindow.webContents.send('backtest-log', {
        type: 'error',
        text: `[ERROR] Gagal menjalankan Python: ${err.message}`
      });
      resolve({ success: false, message: err.message });
    });
  });
});

// IPC: Cancel Backtest
ipcMain.handle('cancel-backtest', () => {
  if (activeBacktestProcess) {
    try {
      activeBacktestProcess.kill('SIGTERM');
      activeBacktestProcess = null;
      return true;
    } catch (e) {
      return false;
    }
  }
  return false;
});

// IPC: Save File As dialog (e.g. for .set or .mq5 file)
ipcMain.handle('save-file-as', async (event, { defaultName, content }) => {
  const result = await dialog.showSaveDialog(mainWindow, {
    title: 'Simpan Konfigurasi MT5',
    defaultPath: path.join(app.getPath('desktop'), defaultName),
    filters: [
      { name: 'MT5 Config / Code', extensions: ['set', 'mq5', 'txt'] },
      { name: 'All Files', extensions: ['*'] }
    ]
  });

  if (!result.canceled && result.filePath) {
    try {
      fs.writeFileSync(result.filePath, content, 'utf8');
      return { success: true, path: result.filePath };
    } catch (err) {
      return { success: false, message: err.message };
    }
  }
  return { success: false, cancelled: true };
});

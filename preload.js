const { contextBridge, ipcRenderer } = require('electron');

contextBridge.exposeInMainWorld('api', {
  // Directories & Files
  selectDirectory: (defaultPath) => ipcRenderer.invoke('select-directory', defaultPath),
  selectFile: (defaultPath) => ipcRenderer.invoke('select-file', defaultPath),
  openDirectory: (dirPath) => ipcRenderer.invoke('open-directory', dirPath),
  openFileExternal: (filePath) => ipcRenderer.invoke('open-file-external', filePath),
  getDefaultDirectory: () => ipcRenderer.invoke('get-default-directory'),
  getCsvFiles: (dirPath) => ipcRenderer.invoke('get-csv-files', dirPath),
  saveFileAs: (options) => ipcRenderer.invoke('save-file-as', options),

  // Downloader
  startDownload: (options) => ipcRenderer.invoke('start-download', options),
  cancelDownload: () => ipcRenderer.invoke('cancel-download'),
  onDownloadLog: (callback) => {
    const handler = (event, data) => callback(data);
    ipcRenderer.on('download-log', handler);
    return () => ipcRenderer.removeListener('download-log', handler);
  },
  onDownloadStatus: (callback) => {
    const handler = (event, data) => callback(data);
    ipcRenderer.on('download-status', handler);
    return () => ipcRenderer.removeListener('download-status', handler);
  },

  // Backtester
  getStrategies: () => ipcRenderer.invoke('get-strategies'),
  runBacktest: (options) => ipcRenderer.invoke('run-backtest', options),
  cancelBacktest: () => ipcRenderer.invoke('cancel-backtest'),
  onBacktestLog: (callback) => {
    const handler = (event, data) => callback(data);
    ipcRenderer.on('backtest-log', handler);
    return () => ipcRenderer.removeListener('backtest-log', handler);
  }
});

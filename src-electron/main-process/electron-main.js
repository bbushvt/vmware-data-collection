import {
  app, BrowserWindow, nativeTheme, ipcMain, dialog,
} from 'electron';

const PowerShell = require('powershell');
const fs = require('fs');

try {
  if (process.platform === 'win32' && nativeTheme.shouldUseDarkColors === true) {
    // eslint-disable-next-line
    require('fs').unlinkSync(require('path').join(app.getPath('userData'), 'DevTools Extensions'));
  }
  // eslint-disable-next-line
} catch (_) { }

/**
 * Set `__statics` path to static files in production;
 * The reason we are setting it here is that the path needs to be evaluated at runtime
 */
if (process.env.PROD) {
  // eslint-disable-next-line
  global.__statics = __dirname;
}

let mainWindow;

function createWindow() {
  /**
   * Initial window options
   */
  mainWindow = new BrowserWindow({
    width: 1000,
    height: 600,
    useContentSize: true,
    webPreferences: {
      // Change from /quasar.conf.js > electron > nodeIntegration;
      // More info: https://quasar.dev/quasar-cli/developing-electron-apps/node-integration
      nodeIntegration: process.env.QUASAR_NODE_INTEGRATION,
      nodeIntegrationInWorker: process.env.QUASAR_NODE_INTEGRATION,

      // More info: /quasar-cli/developing-electron-apps/electron-preload-script
      // preload: path.resolve(__dirname, 'electron-preload.js')
    },
  });

  mainWindow.loadURL(process.env.APP_URL);

  mainWindow.on('closed', () => {
    mainWindow = null;
  });
}

function processData(data) {
  const obj = JSON.parse(data);
  return obj;
}

ipcMain.on('save_file', async (e, args) => {
  const savePath = await dialog.showSaveDialog(null);
  // Save the file if the dialog wasn't canceled
  if (!savePath.canceled) {
    fs.writeFileSync(savePath.filePath, JSON.stringify(args));
  }
});

ipcMain.on('get_vmware_data', async (e, args) => {
  // eslint-disable-next-line

  const command = `./vmware-data-collection.ps1 -vcenter ${args.vcenter_hostname} -username ${args.vcenter_username} -password ${args.vcenter_password} -json`;
  let output = '';
  const ps = new PowerShell(command, { debug: true });
  ps.on('error', (err) => {
    // eslint-disable-next-line
    console.log(err);
  });
  ps.on('output', (data) => {
    // eslint-disable-next-line
    output += data;
  });
  ps.on('error-output', (data) => {
    // eslint-disable-next-line
    console.log(data);
  });
  ps.on('end', (code) => {
    // eslint-disable-next-line
    console.log(code);

    if (code === 0) {
      const jsonData = output.split('BEGIN_DATA_PARSE_SECTION')[1];
      // eslint-disable-next-line
      const vmwareData = {};
      vmwareData.data = processData(jsonData);
      vmwareData.success = true;
      // No longer writtng the output file here
      // fs.writeFileSync(args.output_file, JSON.stringify(vmwareData));
      e.sender.send('receive_vmare_data', vmwareData);
    } else {
      e.sender.send('receive_vmare_data', { success: false });
    }
  });
});

app.on('ready', createWindow);

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});

app.on('activate', () => {
  if (mainWindow === null) {
    createWindow();
  }
});

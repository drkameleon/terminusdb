const electron = require('electron')
const path = require('path')
const fs = require('fs')
const execFile = require('child_process').execFile
const ps = require('ps-node')

let MAIN_WINDOW
let SYSTEM_TRAY

let QUIT_OK = false

electron.app.on('will-quit', (event) => {
  if (!QUIT_OK) {
    event.preventDefault()
    ps.lookup({
      command: 'swipl',
      arguments: 'serve'
    }, (err, list) => {
      if (err) throw new Error(err)
      console.log('finding DB process...')
      list.forEach((p) => {
        if (p) {
          console.log('found', p.pid)
          console.log( 'PID: %s, COMMAND: %s, ARGUMENTS: %s',
            p.pid, p.command, p.arguments)
          try {
            process.kill(p.pid, 'SIGTERM')
          } catch (e) {
            console.log('error', e)
          }
        }
      })
      QUIT_OK = true
      console.log('Quitting...')
      electron.app.quit() 
    })
  }
})

electron.app.on('certificate-error',
  (event, webContents, url, error, certificate, accept) => {
    if (url.startsWith('https://127.0.0.1')) {
      accept(true)
    } else {
      accept(false)
    }
  }
)

electron.app.on('ready', () => {
  electron.session.defaultSession.clearCache()

  const appDir = path.dirname(require.main.filename)
  const appImagePath = `${appDir}/TerminusDB-amd64.AppImage`
  const exePath = `${appDir}/windows/start_windows.bat`
  const macOSPath = `${appDir}/SWI-Prolog.app/Contents/MacOS/swipl`

  let binPath
  let binArgs
  if (fs.existsSync(appImagePath)) {
    binPath = appImagePath
    binArgs = ['serve']
    binInitArgs = ['store', 'init', '--key', 'root']
  } else if (fs.existsSync(exePath)) {
    binPath = exePath
    binArgs = ['serve']
    binInitArgs = ['store', 'init', '--key', 'root']
  } else if (fs.existsSync(macOSPath)) {
    binPath = macOSPath
    binArgs = [`${appDir}/terminusdb-server/src/start.pl`, 'serve']
    binInitArgs = ['-g', 'halt', `${appDir}/terminusdb-server/src/start.pl`,
      'store', 'init', '--key', 'root']
  }

  const homeDir = process.env.HOME
  const cwd = `${homeDir}/.terminusdb`

  if (binPath) {
    if (homeDir) {
      process.env.TERMINUSDB_SERVER_PACK_DIR = `${appDir}/pack`
      process.env.TERMINUSDB_SERVER_DB_PATH = `${cwd}/db`
      process.env.TERMINUSDB_SERVER_REGISTRY_PATH = `${cwd}/registry.pl`
      process.env.TERMINUSDB_SERVER_INDEX_PATH = `${cwd}/index.html`
      process.env.TERMINUSDB_AUTOLOGIN_ENABLED = 'true'

      if (!fs.existsSync(`${cwd}`)) {
          fs.mkdirSync(cwd)
      }

      if (!fs.existsSync(`${cwd}/db`)) {
          const initDb = execFile(binPath, binInitArgs)
          initDb.stdout.on('data', (data) => console.log(data))
          initDb.stderr.on('data', (data) => console.log(data))
      }
    }  

    console.log('binPath', binPath)
    console.log('binArgs', binArgs)
    console.log('binInitArgs', binInitArgs)

    let serverReady = false
    console.log('Starting TerminusDB')
    const child = execFile(binPath, binArgs)
    child.stderr.on('data', (data) => {
      if (!serverReady) {
        console.log('stderr: ' + data)
        if (data.toString().substring(2, 16) === 'Started server') {
          serverReady = true
          console.log('Terminusdb started')
          createWindow()
        }
      }
    })
  } else {
    QUIT_OK = true
    console.log('TerminusDB not found in path')
    console.log('Please start TerminusDB')
    createWindow()
  }
})

function createWindow () {
  MAIN_WINDOW = new electron.BrowserWindow({
    width: 1024,
    height: 768,
    nodeIntegration: false,
    webPreferences: {
      spellcheck: false
    },
    icon: path.join(__dirname, 'assets/icons/favicon.png')
  })

  MAIN_WINDOW.on('minimize', function (event) {
    event.preventDefault()
    MAIN_WINDOW.hide()
  })

  MAIN_WINDOW.on('close', function (event) {
    if (!electron.app.isQuiting) {
      event.preventDefault()
      MAIN_WINDOW.hide()
    }
    return false
  })

  MAIN_WINDOW.webContents.on('new-window', function (e, url) {
    e.preventDefault()
    electron.shell.openExternal(url)
  })

  MAIN_WINDOW.loadURL('https://127.0.0.1:6363/')

  if (process.platform !== 'darwin') {
    const appMenu = new electron.Menu()
    appMenu.append(new electron.MenuItem({
      label: 'Reload (Ctrl+R)',
      accelerator: 'Control+R',
      click () {
        MAIN_WINDOW.reload()
      }
    }))
    appMenu.append(new electron.MenuItem({
      label: 'Reload (F5)',
      accelerator: 'f5',
      click () {
        MAIN_WINDOW.reload()
      }
    }))
    appMenu.append(new electron.MenuItem({
      label: 'Back',
      accelerator: 'Alt+Left',
      click () {
        MAIN_WINDOW.webContents.goBack()
      }
    }))
    appMenu.append(new electron.MenuItem({
      label: 'Back',
      accelerator: 'Alt+Right',
      click () {
        MAIN_WINDOW.webContents.goForward()
      }
    }))
    appMenu.append(new electron.MenuItem({
      accelerator: 'Control+B',
      label: 'Open in Browser',
      click () {
        electron.shell.openExternal('https://127.0.0.1:6363')
      }
    }))
    appMenu.append(new electron.MenuItem({
      accelerator: 'Ctrl+Shift+I',
      label: 'Developer Tools',
      click () {
        MAIN_WINDOW.webContents.toggleDevTools()
      }
    }))

    electron.Menu.setApplicationMenu(appMenu)
    MAIN_WINDOW.setMenuBarVisibility(false)
  }

  const trayMenu = new electron.Menu()

  trayMenu.append(new electron.MenuItem({
    label: 'TerminusDB',
    click () {
      MAIN_WINDOW.show()
    }
  }))
  trayMenu.append(new electron.MenuItem({ type: 'separator' }))
  trayMenu.append(new electron.MenuItem({
    label: 'Hide',
    click () {
      MAIN_WINDOW.hide()
    }
  }))
  trayMenu.append(new electron.MenuItem({
    label: 'Reload',
    click () {
      MAIN_WINDOW.show()
      MAIN_WINDOW.reload()
    }
  }))
  trayMenu.append(new electron.MenuItem({
    label: 'Quit',
    click () {
      electron.app.isQuiting = true
      electron.app.quit()
    }
  }))

  SYSTEM_TRAY = new electron.Tray(path.join(__dirname,
    'assets/icons/favicon.png'))

  SYSTEM_TRAY.setContextMenu(trayMenu)
  SYSTEM_TRAY.setToolTip('TerminusDB')

  SYSTEM_TRAY.on('click', () => SYSTEM_TRAY.popUpContextMenu(trayMenu))
}


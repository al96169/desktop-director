// ddir macOS backend — entry point.
// Same command surface as the Windows build; `ddir <cmd>` is a one-shot client that
// reads/writes ~/.ddir (no daemon yet, matching v0.7.x).

import Foundation

store.ensureHome()
Present.tick()

let argv = Array(CommandLine.arguments.dropFirst())
let cmd = argv.first?.lowercased() ?? "help"
let rest = Array(argv.dropFirst())

var code: Int32 = 0
switch cmd {
case "mode": code = cmdMode(rest)
case "displays": code = cmdDisplays(rest)
case "list": code = cmdList(rest)
case "status": code = cmdStatus()
case "plan": code = cmdClaim(rest, dry: true)
case "claim": code = cmdClaim(rest, dry: false)
case "move": code = cmdMove(rest)
case "hide": code = cmdShowHide(rest, hide: true)
case "show": code = cmdShowHide(rest, hide: false)
case "close": code = cmdClose(rest)
case "own": code = cmdOwn(rest, disown: false)
case "disown": code = cmdOwn(rest, disown: true)
case "release": code = cmdRelease()
case "board": code = cmdBoard()
case "selftest": code = cmdSelftest(rest)
case "auto": code = cmdAuto(rest)
case "config": code = cmdConfig(rest)
case "flush": code = cmdFlush()
case "heartbeat", "hb": code = cmdHeartbeat()
case "focus": code = cmdFocus(rest)
case "demo": code = cmdDemo()
case "log", "logs": code = cmdLog(rest)
case "hud": code = cmdHud(rest)
case "doctor": code = cmdDoctor(rest)
case "stage": code = cmdStage(rest)
case "play": code = cmdPlay(rest)
case "web": code = cmdWeb(rest)
case "prompt": code = cmdPrompt(rest)
case "tray": code = cmdTray(rest)
case "autostart": code = cmdAutostart(rest)
case "version", "--version", "-v", "-V":
    print("ddir \(VERSION) (macos)")
case "help", "--help", "-h":
    usage()
default:
    usage()
}

exit(code)
